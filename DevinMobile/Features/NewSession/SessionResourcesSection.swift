import SwiftUI
import DevinKit

/// "Knowledge & secrets" section of the New Session form. Owns the loading model; the selected IDs
/// are bound back to the form so `NewSessionRequest` can carry them. Disappears entirely when
/// both endpoints return 403.
struct SessionResourcesSection: View {
    @State private var model: SessionResourcesModel
    @Binding var knowledgeIDs: Set<String>
    @Binding var secretIDs: Set<String>

    init(store: SessionStore, knowledgeIDs: Binding<Set<String>>, secretIDs: Binding<Set<String>>) {
        _model = State(initialValue: SessionResourcesModel(store: store))
        _knowledgeIDs = knowledgeIDs
        _secretIDs = secretIDs
    }

    var body: some View {
        if !model.isHidden {
            Section {
                if model.showsKnowledge {
                    knowledgeRow
                }
                if model.showsSecrets {
                    secretsRow
                }
            } header: {
                // Modifiers on the Section itself would stop Form from treating it as one.
                Text("Knowledge & secrets")
                    .task { await model.load() }
            } footer: {
                Text("Optional. Notes are added to Devin's context; secrets are made available in the session without ever being shown here.")
            }
        }
    }

    @ViewBuilder
    private var knowledgeRow: some View {
        switch model.knowledgeState {
        case .loading:
            ResourceRow(title: "Knowledge notes", systemImage: "book.closed", detail: nil) { ProgressView() }
        case .failed(let message):
            ResourceRetryRow(title: "Knowledge notes", systemImage: "book.closed", message: message) {
                await model.loadKnowledge()
            }
        case .loaded where model.notes.isEmpty:
            ResourceRow(title: "Knowledge notes", systemImage: "book.closed", detail: nil) {
                Text("None").foregroundStyle(.secondary)
            }
        case .loaded, .forbidden:
            NavigationLink {
                KnowledgeNotePickerView(model: model, selection: $knowledgeIDs)
            } label: {
                ResourceRow(title: "Knowledge notes", systemImage: "book.closed",
                            detail: selectedSummary(knowledgeIDs.compactMap { model.note(id: $0)?.displayName })) {
                    countLabel(knowledgeIDs.count, of: model.notes.count)
                }
            }
        }
    }

    @ViewBuilder
    private var secretsRow: some View {
        switch model.secretsState {
        case .loading:
            ResourceRow(title: "Secrets", systemImage: "key", detail: nil) { ProgressView() }
        case .failed(let message):
            ResourceRetryRow(title: "Secrets", systemImage: "key", message: message) {
                await model.loadSecrets()
            }
        case .loaded where model.secrets.isEmpty:
            ResourceRow(title: "Secrets", systemImage: "key", detail: nil) {
                Text("None").foregroundStyle(.secondary)
            }
        case .loaded, .forbidden:
            NavigationLink {
                SecretPickerView(model: model, selection: $secretIDs)
            } label: {
                ResourceRow(title: "Secrets", systemImage: "key",
                            detail: selectedSummary(secretIDs.compactMap { model.secret(id: $0)?.displayName })) {
                    countLabel(secretIDs.count, of: model.secrets.count)
                }
            }
        }
    }

    private func selectedSummary(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.joined(separator: ", ")
    }

    private func countLabel(_ selected: Int, of total: Int) -> some View {
        Text(selected == 0 ? "\(total) available" : "\(selected) of \(total)")
            .foregroundStyle(selected == 0 ? .secondary : .primary)
            .monospacedDigit()
    }
}

private struct ResourceRow<Trailing: View>: View {
    let title: String
    let systemImage: String
    let detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } icon: {
                Image(systemName: systemImage)
            }
            Spacer()
            trailing
        }
    }
}

private struct ResourceRetryRow: View {
    let title: String
    let systemImage: String
    let message: String
    let retry: @MainActor () async -> Void

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            } icon: {
                Image(systemName: systemImage)
            }
            Spacer()
            Button("Retry") { Task { await retry() } }
                .buttonStyle(.borderless)
        }
    }
}
