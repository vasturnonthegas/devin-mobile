import SwiftUI
import DevinKit

/// Inline chip editor for a session's tags. Lives in the detail header.
struct SessionTagsEditor: View {
    @State private var model: SessionTagsModel
    @State private var isAdding = false
    @FocusState private var draftFocused: Bool

    init(store: SessionStore, sessionID: String) {
        _model = State(initialValue: SessionTagsModel(store: store, sessionID: sessionID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(model.tags, id: \.self) { tag in
                    TagChip(tag: tag, isPending: model.isPending(tag)) {
                        Task { await model.remove(tag) }
                    }
                }

                if isAdding {
                    TextField("New tag", text: $model.draft)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($draftFocused)
                        .onSubmit { submitDraft() }
                        .frame(width: 110)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.background, in: Capsule())
                        .overlay(Capsule().strokeBorder(.tint, lineWidth: 1))
                } else if model.canAddMore {
                    Button {
                        isAdding = true
                        draftFocused = true
                    } label: {
                        Label("Tag", systemImage: "plus")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .overlay(Capsule().strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3])))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Add tag")
                }
            }
            .animation(.snappy(duration: 0.2), value: model.tags)

            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: draftFocused) { _, focused in
            if !focused && model.draft.isEmpty { isAdding = false }
        }
    }

    private func submitDraft() {
        Task {
            if await model.add() {
                draftFocused = true
            } else if model.draft.isEmpty {
                isAdding = false
            }
        }
    }
}

private struct TagChip: View {
    let tag: String
    let isPending: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("#\(tag)")
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove tag \(tag)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
        .opacity(isPending ? 0.5 : 1)
    }
}
