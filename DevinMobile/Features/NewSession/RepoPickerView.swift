import SwiftUI
import DevinKit

/// Multi-select repository picker for the New Session form. `selection` holds host-prefixed paths
/// (`Repository.fullPath`) in the order they were picked. Recents are pinned on top; the API list
/// below is searched server-side; a typed `owner/repo` the API doesn't know can still be added.
struct RepoPickerView: View {
    @Binding var selection: [String]
    @Environment(\.dismiss) private var dismiss

    @State private var model: RepoPickerModel
    @State private var recents = RecentRepos.load()

    init(store: SessionStore, selection: Binding<[String]>) {
        _selection = selection
        _model = State(initialValue: RepoPickerModel(client: store.client, orgID: store.orgID))
    }

    private var trimmedSearch: String { model.search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var pinned: [String] {
        guard !trimmedSearch.isEmpty else { return recents }
        return recents.filter { $0.localizedCaseInsensitiveContains(trimmedSearch) }
    }

    /// A typed path that neither recents nor the current API results already offer.
    private var manualCandidate: String? {
        let path = RecentRepos.normalize(trimmedSearch)
        guard path.contains("/"), !path.hasSuffix("/"), !path.contains(" ") else { return nil }
        let known = pinned.contains { $0.caseInsensitiveCompare(path) == .orderedSame }
            || model.repos.contains { $0.fullPath.caseInsensitiveCompare(path) == .orderedSame || $0.shortPath.caseInsensitiveCompare(path) == .orderedSame }
        return known ? nil : path
    }

    var body: some View {
        NavigationStack {
            list
                .navigationTitle("Repositories")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(selection.isEmpty ? "Done" : "Done (\(selection.count))") { dismiss() }
                    }
                }
        }
    }

    private var list: some View {
        List {
            if !pinned.isEmpty {
                Section("Recent") {
                    ForEach(pinned, id: \.self) { path in
                        let repo = model.repository(for: path)
                        RepoPickerRow(
                            title: repo?.shortPath ?? SessionFilter.normalizeRepoName(path),
                            subtitle: repo?.repoDescription ?? path,
                            language: repo?.repoLanguage,
                            isSelected: isSelected(path)
                        ) { toggle(path) }
                    }
                }
            }

            if model.isUnavailable {
                Section {
                    Label("This token can't list the organization's repositories. Type an `owner/repo` path above to add one.",
                          systemImage: "lock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    if model.isLoading && model.repos.isEmpty {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if let error = model.error, model.repos.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Button("Retry") { Task { await model.retry() } }
                                .buttonStyle(.borderless)
                        }
                        .font(.footnote)
                    } else if model.hasLoaded && model.repos.isEmpty {
                        Text(trimmedSearch.isEmpty ? "No repositories are connected to this organization."
                             : "No repositories match “\(trimmedSearch)”.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.repos) { repo in
                        RepoPickerRow(
                            title: repo.shortPath,
                            subtitle: repo.repoDescription ?? repo.fullPath,
                            language: repo.repoLanguage,
                            isSelected: isSelected(repo.fullPath)
                        ) { toggle(repo.fullPath) }
                        .onAppear { model.loadMoreIfNeeded(current: repo) }
                    }
                    if model.hasMore {
                        HStack {
                            Spacer()
                            if model.isLoadingMore {
                                ProgressView()
                            } else {
                                Button("Load more") { Task { await model.loadMore() } }
                                    .buttonStyle(.borderless)
                            }
                            Spacer()
                        }
                        .frame(minHeight: 32)
                    }
                } header: {
                    HStack {
                        Text("All repositories")
                        if model.isLoading && !model.repos.isEmpty { ProgressView().controlSize(.mini) }
                    }
                }
            }

            if let manualCandidate {
                Section {
                    Button {
                        toggle(manualCandidate)
                        model.search = ""
                    } label: {
                        Label("Add “\(manualCandidate)”", systemImage: "plus.circle")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $model.search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search repositories")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .task { await model.start() }
    }

    private func isSelected(_ path: String) -> Bool {
        selection.contains { $0.caseInsensitiveCompare(path) == .orderedSame }
    }

    private func toggle(_ path: String) {
        if let index = selection.firstIndex(where: { $0.caseInsensitiveCompare(path) == .orderedSame }) {
            selection.remove(at: index)
        } else {
            selection.append(path)
        }
    }
}

struct RepoPickerRow: View {
    let title: String
    let subtitle: String
    let language: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .imageScale(.large)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .lineLimit(1)
                    if !subtitle.isEmpty, subtitle != title {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
