import SwiftUI
import DevinKit

/// Edits a draft of `store.filter`; nothing is applied until "Done".
struct SessionFilterSheet: View {
    @Bindable var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: SessionFilter
    @State private var playbooks: [Playbook] = []

    init(store: SessionStore) {
        self.store = store
        _draft = State(initialValue: store.filter)
    }

    private var repoSuggestions: [String] {
        var seen = Set(draft.repoNames)
        return RecentRepos.load().map(SessionFilter.normalizeRepoName).filter { seen.insert($0).inserted }
    }

    private var tagSuggestions: [String] {
        var seen = Set(draft.tags)
        return store.sessions.flatMap(\.tags).filter { seen.insert($0).inserted }.sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Repositories") {
                    TokenField(
                        values: $draft.repoNames,
                        prompt: "owner/repo",
                        suggestions: repoSuggestions,
                        normalize: SessionFilter.normalizeRepoName
                    )
                    .keyboardType(.URL)
                }

                Section("Tags") {
                    TokenField(values: $draft.tags, prompt: "Tag", suggestions: tagSuggestions)
                }

                Section("Origin") {
                    ForEach(SessionOrigin.allCases) { origin in
                        Button {
                            if draft.origins.contains(origin) {
                                draft.origins.remove(origin)
                            } else {
                                draft.origins.insert(origin)
                            }
                        } label: {
                            HStack {
                                Text(origin.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if draft.origins.contains(origin) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }

                Section("Playbook") {
                    Picker("Playbook", selection: playbookSelection) {
                        Text("Any").tag(String?.none)
                        if let id = draft.playbookID, !playbooks.contains(where: { $0.playbookID == id }) {
                            Text(draft.playbookTitle ?? id).tag(Optional(id))
                        }
                        ForEach(playbooks) { playbook in
                            Text(playbook.title).tag(Optional(playbook.playbookID))
                        }
                    }
                }

                Section {
                    TokenField(values: $draft.userIDs, prompt: "user-…", suggestions: [])
                } header: {
                    Text("Started by")
                } footer: {
                    Text("Devin user IDs, e.g. from Settings → Members on the web.")
                }

                Section("Created") {
                    OptionalDateRow(title: "After", date: $draft.createdAfter, defaultDate: .weekAgo)
                    OptionalDateRow(title: "Before", date: $draft.createdBefore, defaultDate: .now)
                }

                Section("Updated") {
                    OptionalDateRow(title: "After", date: $draft.updatedAfter, defaultDate: .weekAgo)
                    OptionalDateRow(title: "Before", date: $draft.updatedBefore, defaultDate: .now)
                }

                if !draft.isEmpty {
                    Section {
                        Button("Reset filters", role: .destructive) { draft = SessionFilter() }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.filter = draft
                        dismiss()
                    }
                }
            }
            .task { await loadPlaybooks() }
        }
    }

    private var playbookSelection: Binding<String?> {
        Binding(
            get: { draft.playbookID },
            set: { id in
                draft.playbookID = id
                draft.playbookTitle = playbooks.first { $0.playbookID == id }?.title
            }
        )
    }

    private func loadPlaybooks() async {
        guard let page = try? await store.client.playbooks(org: store.orgID) else { return }
        playbooks = page.items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

/// A list of removable values plus an input row and tappable suggestions.
private struct TokenField: View {
    @Binding var values: [String]
    let prompt: String
    let suggestions: [String]
    var normalize: (String) -> String = { $0 }

    @State private var input = ""

    var body: some View {
        ForEach(values, id: \.self) { value in
            HStack {
                Text(value).lineLimit(1)
                Spacer()
                Button { values.removeAll { $0 == value } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        HStack {
            TextField(prompt, text: $input)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit(add)
            Button("Add", action: add)
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        if !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { append(suggestion) }
                            .buttonStyle(.bordered)
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func add() {
        for token in SessionFilter.tokens(input) {
            append(normalize(token))
        }
        input = ""
    }

    private func append(_ value: String) {
        guard !value.isEmpty, !values.contains(value) else { return }
        values.append(value)
    }
}

private struct OptionalDateRow: View {
    let title: String
    @Binding var date: Date?
    let defaultDate: Date

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { date != nil },
            set: { date = $0 ? defaultDate : nil }
        ).animation())
        if let bound = Binding($date) {
            DatePicker("", selection: bound)
                .labelsHidden()
        }
    }
}

private extension Date {
    static var weekAgo: Date {
        Calendar.current.startOfDay(for: .now).addingTimeInterval(-7 * 86_400)
    }
}
