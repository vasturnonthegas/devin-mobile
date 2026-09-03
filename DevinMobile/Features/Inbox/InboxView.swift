import SwiftUI
import DevinKit

struct InboxView: View {
    @Bindable var store: SessionStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var showNewSession = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Sessions")
                .navigationDestination(for: Session.self) { session in
                    SessionDetailView(store: store, sessionID: session.id)
                }
                .searchable(text: $query, prompt: "Title, tag, or ID")
                .refreshable { await store.refresh() }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showSettings = true } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showNewSession = true } label: {
                            Label("New session", systemImage: "plus")
                        }
                    }
                }
                .sheet(isPresented: $showNewSession) {
                    NewSessionView(store: store) { created in
                        path.append(created)
                    }
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                }
        }
        .task { store.startPolling() }
        .onDisappear { store.stopPolling() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: store.startPolling()
            case .background, .inactive: store.stopPolling()
            @unknown default: break
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let groups = store.filtered(by: query)
        if store.sessions.isEmpty && store.isLoading {
            ProgressView("Loading sessions…")
        } else if let error = store.error, store.sessions.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load sessions", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Retry") { Task { await store.refresh() } }
            }
        } else if groups.isEmpty {
            ContentUnavailableView(
                query.isEmpty ? "No sessions yet" : "No matches",
                systemImage: query.isEmpty ? "tray" : "magnifyingglass",
                description: Text(query.isEmpty ? "Tap + to give Devin something to do." : "Try a different search.")
            )
        } else {
            List {
                ForEach(groups, id: \.bucket) { group in
                    Section {
                        ForEach(group.sessions) { session in
                            NavigationLink(value: session) {
                                SessionRow(session: session)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Archive", systemImage: "archivebox") {
                                    Task { try? await store.archive(session) }
                                }
                                .tint(.indigo)
                            }
                        }
                    } header: {
                        HStack {
                            Text(group.bucket.title)
                            if group.bucket == .needsYou {
                                Text("\(group.sessions.count)")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.orange, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay(alignment: .bottom) {
                if let error = store.error {
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
}

struct SessionRow: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.displayTitle)
                    .font(.body.weight(session.needsAttention ? .semibold : .regular))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(session.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                StatusBadge(session: session)
                if !session.pullRequests.isEmpty {
                    Label("\(session.pullRequests.count)", systemImage: "arrow.triangle.pull")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if session.hasChildren {
                    Label("\(session.childCount)", systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if session.acusConsumed > 0 {
                    Text("\(session.acusConsumed, format: .number.precision(.fractionLength(0...1))) ACU")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let mode = session.devinMode, mode != .normal {
                    Text(mode.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
            }
            if !session.tags.isEmpty {
                Text(session.tags.map { "#\($0)" }.joined(separator: "  "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
