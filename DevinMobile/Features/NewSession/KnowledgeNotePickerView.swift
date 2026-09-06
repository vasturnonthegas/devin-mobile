import SwiftUI
import DevinKit

/// Multi-select list of knowledge notes grouped by folder, filtered client-side by `.searchable`.
struct KnowledgeNotePickerView: View {
    let model: SessionResourcesModel
    @Binding var selection: Set<String>

    @State private var search = ""

    var body: some View {
        let groups = model.noteGroups(matching: search)
        List {
            if groups.isEmpty {
                ContentUnavailableView.search(text: search)
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.notes) { note in
                        KnowledgeNoteRow(note: note, isSelected: selection.contains(note.noteID)) {
                            toggle(note.noteID)
                        }
                    }
                } header: {
                    Label(group.folder, systemImage: group.folder == KnowledgeNote.rootFolderName ? "tray" : "folder")
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search notes")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .navigationTitle("Knowledge notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !selection.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear") { selection.removeAll() }
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
}

private struct KnowledgeNoteRow: View {
    let note: KnowledgeNote
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .imageScale(.large)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(note.displayName)
                            .foregroundStyle(.primary)
                        if !note.isEnabled {
                            Text("Off")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !note.trigger.isEmpty {
                        Text(note.trigger)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let repo = note.pinnedRepo, !repo.isEmpty {
                        Label(repo.split(separator: "/").suffix(2).joined(separator: "/"), systemImage: "folder")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
