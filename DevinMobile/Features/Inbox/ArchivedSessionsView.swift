import SwiftUI
import Observation
import DevinKit

enum InboxTab: String, CaseIterable, Identifiable {
    case active = "Active"
    case archived = "Archived"

    var id: Self { self }
}

/// Archived sessions are fetched on demand (`is_archived=true`) and never polled;
/// they only change when the user acts on them.
@Observable
@MainActor
final class ArchivedSessionsModel {
    let store: SessionStore

    private(set) var sessions: [Session] = []
    private(set) var isLoading = false
    var error: DevinError?

    init(store: SessionStore) {
        self.store = store
    }

    func filtered(by query: String) -> [Session] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return sessions }
        return sessions.filter {
            $0.displayTitle.lowercased().contains(needle)
                || $0.tags.contains { $0.lowercased().contains(needle) }
                || $0.sessionID.lowercased().contains(needle)
        }
    }

    func refresh() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await store.client.sessions(org: store.orgID, query: SessionQuery(first: 100, isArchived: true))
            sessions = page.items.sorted { $0.updatedAt > $1.updatedAt }
            error = nil
        } catch let e as DevinError {
            error = e
        } catch {
            self.error = .transport(error.localizedDescription)
        }
    }

    /// The restored session is handed to the inbox store so it shows up in Active
    /// before the next poll confirms it.
    func unarchive(_ session: Session) async {
        do {
            let restored = try await store.client.unarchive(org: store.orgID, id: session.id)
            sessions.removeAll { $0.id == session.id }
            store.apply(restored)
            error = nil
        } catch let e as DevinError {
            error = e
        } catch {
            self.error = .transport(error.localizedDescription)
        }
    }
}

struct ArchivedSessionsView: View {
    @State private var model: ArchivedSessionsModel
    @Environment(\.openURL) private var openURL
    let query: String

    init(store: SessionStore, query: String) {
        _model = State(initialValue: ArchivedSessionsModel(store: store))
        self.query = query
    }

    var body: some View {
        content
            .task { await model.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        let sessions = model.filtered(by: query)
        if model.sessions.isEmpty && model.isLoading {
            ProgressView("Loading archived sessions…")
        } else if let error = model.error, model.sessions.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load archived sessions", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Retry") { Task { await model.refresh() } }
            }
        } else if sessions.isEmpty {
            ContentUnavailableView(
                query.isEmpty ? "No archived sessions" : "No matches",
                systemImage: query.isEmpty ? "archivebox" : "magnifyingglass",
                description: Text(query.isEmpty ? "Swipe a session in Active to archive it." : "Try a different search.")
            )
        } else {
            List {
                ForEach(sessions) { session in
                    SessionRow(session: session)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            unarchiveButton(for: session)
                        }
                        .contextMenu {
                            unarchiveButton(for: session)
                            Button("Open in Devin", systemImage: "safari") { openURL(session.url) }
                        }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await model.refresh() }
            .overlay(alignment: .bottom) {
                if let error = model.error {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .padding(8)
                        .background(.red.opacity(0.9), in: Capsule())
                        .foregroundStyle(.white)
                        .padding()
                        .transition(.move(edge: .bottom))
                }
            }
        }
    }

    private func unarchiveButton(for session: Session) -> some View {
        Button("Unarchive", systemImage: "tray.and.arrow.up") {
            Task { await model.unarchive(session) }
        }
        .tint(.green)
    }
}
