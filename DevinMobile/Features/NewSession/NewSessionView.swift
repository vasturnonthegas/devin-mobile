import SwiftUI
import DevinKit

struct NewSessionView: View {
    let store: SessionStore
    var onCreated: (Session) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var prompt = ""
    @State private var repoInput = ""
    @State private var selectedRepos: [String] = []
    @State private var recentRepos = RecentRepos.load()
    @State private var mode: DevinMode = .normal
    @State private var playbooks: [Playbook] = []
    @State private var playbookID: String?
    @State private var previewingPlaybook: PlaybookPreviewTarget?
    @State private var limitACUs = false
    @State private var acuLimit = 10
    @State private var tagsInput = ""
    @State private var advanced = NewSessionAdvancedOptions()
    @State private var isCreating = false
    @State private var errorMessage: String?
    @FocusState private var promptFocused: Bool

    private var canCreate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCreating && advanced.isValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("What should Devin do?", text: $prompt, axis: .vertical)
                        .lineLimit(4...12)
                        .focused($promptFocused)
                }

                Section {
                    if !selectedRepos.isEmpty {
                        ForEach(selectedRepos, id: \.self) { repo in
                            HStack {
                                Image(systemName: "folder")
                                Text(repo).lineLimit(1)
                                Spacer()
                                Button { selectedRepos.removeAll { $0 == repo } } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    HStack {
                        TextField("github.com/owner/repo", text: $repoInput)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .onSubmit(addRepo)
                        Button("Add", action: addRepo)
                            .disabled(repoInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    let suggestions = recentRepos.filter { !selectedRepos.contains($0) }
                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(suggestions, id: \.self) { repo in
                                    Button(repo.split(separator: "/").suffix(2).joined(separator: "/")) {
                                        selectedRepos.append(repo)
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.caption)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Repositories")
                } footer: {
                    Text("Optional. Devin can also pick repos from your prompt.")
                }

                Section("Options") {
                    Picker("Mode", selection: $mode) {
                        ForEach(DevinMode.allCases.filter { $0 != .fusion }) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    if !playbooks.isEmpty {
                        Picker("Playbook", selection: $playbookID) {
                            Text("None").tag(String?.none)
                            ForEach(playbooks) { playbook in
                                Text(playbook.title).tag(Optional(playbook.playbookID))
                            }
                        }
                        if let playbookID {
                            Button {
                                previewingPlaybook = PlaybookPreviewTarget(id: playbookID)
                            } label: {
                                Label("Preview playbook", systemImage: "doc.text.magnifyingglass")
                            }
                        }
                    }
                    Toggle("Cap ACUs", isOn: $limitACUs.animation())
                    if limitACUs {
                        Stepper("Max \(acuLimit) ACU", value: $acuLimit, in: 1...200)
                    }
                    TextField("Tags (comma separated)", text: $tagsInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                NewSessionAdvancedSection(options: $advanced)

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                    } else {
                        Button("Start", action: create).disabled(!canCreate)
                    }
                }
            }
            .task { await loadPlaybooks() }
            .sheet(item: $previewingPlaybook) { target in
                PlaybookPreviewSheet(store: store, playbookID: target.id)
            }
            .onAppear { promptFocused = true }
            .interactiveDismissDisabled(!prompt.isEmpty)
        }
    }

    private func addRepo() {
        let repo = RecentRepos.normalize(repoInput)
        guard !repo.isEmpty else { return }
        if !selectedRepos.contains(repo) { selectedRepos.append(repo) }
        repoInput = ""
    }

    private func loadPlaybooks() async {
        guard let page = try? await store.client.playbooks(org: store.orgID) else { return }
        playbooks = page.items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func create() {
        guard canCreate else { return }
        if !repoInput.trimmingCharacters(in: .whitespaces).isEmpty { addRepo() }
        isCreating = true
        errorMessage = nil

        let tags = tagsInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let request = NewSessionRequest(
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            repos: selectedRepos.isEmpty ? nil : selectedRepos,
            playbookID: playbookID,
            devinMode: mode == .normal ? nil : mode,
            maxACULimit: limitACUs ? acuLimit : nil,
            tags: tags.isEmpty ? nil : tags
        )

        Task {
            defer { isCreating = false }
            do {
                let session = try await store.create(advanced.applied(to: request))
                RecentRepos.remember(selectedRepos)
                dismiss()
                onCreated(session)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
