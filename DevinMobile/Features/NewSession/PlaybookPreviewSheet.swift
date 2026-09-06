import SwiftUI
import Observation
import DevinKit

/// `sheet(item:)` payload; a bare `String` is not `Identifiable`.
struct PlaybookPreviewTarget: Identifiable, Hashable {
    let id: String
}

/// Body of the playbook chosen in the New Session picker, fetched fresh via `GET …/playbooks/{id}`
/// so the preview reflects the current template rather than the (possibly stale) list entry.
struct PlaybookPreviewSheet: View {
    let store: SessionStore
    let playbookID: String

    @Environment(\.dismiss) private var dismiss
    @State private var model: PlaybookPreviewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(model?.playbook?.title ?? "Playbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            let model = PlaybookPreviewModel(store: store, playbookID: playbookID)
            self.model = model
            await model.load()
        }
    }

    @ViewBuilder
    private func content(_ model: PlaybookPreviewModel) -> some View {
        if let playbook = model.playbook {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PlaybookMetadataLine(playbook: playbook)
                    if playbook.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("This playbook has no body.")
                            .foregroundStyle(.secondary)
                    } else {
                        MarkdownView(document: MarkdownDocument(markdown: playbook.body))
                    }
                }
                .padding()
            }
        } else if let error = model.error {
            ContentUnavailableView {
                Label("Couldn't load playbook", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ProgressView()
        }
    }
}

private struct PlaybookMetadataLine: View {
    let playbook: Playbook

    var body: some View {
        FlowLayout(spacing: 6) {
            if let macro = playbook.macro {
                Text(macro)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
            if let access = playbook.accessType {
                Label(access.displayName, systemImage: access == .enterprise ? "building.2" : "person.3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let updated = playbook.updatedAt {
                Text("Updated \(updated, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@Observable
@MainActor
final class PlaybookPreviewModel {
    let store: SessionStore
    let playbookID: String

    private(set) var playbook: Playbook?
    private(set) var error: String?

    init(store: SessionStore, playbookID: String) {
        self.store = store
        self.playbookID = playbookID
    }

    func load() async {
        error = nil
        do {
            playbook = try await store.client.playbook(org: store.orgID, id: playbookID)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
