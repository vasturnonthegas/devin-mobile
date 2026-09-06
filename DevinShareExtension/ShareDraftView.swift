import SwiftUI
import DevinKit

/// The share sheet's UI: what the New Session form will be prefilled with, editable enough to drop a
/// wrong repo or picture, then "Continue in Devin".
struct ShareDraftView: View {
    @Bindable var model: ShareModel

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .loading:
                    ProgressView("Reading shared items…")
                case .ready:
                    form
                case .handedOff(let opened):
                    handedOff(opened: opened)
                }
            }
            .navigationTitle("New Devin session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.cancel() }
                }
                if model.phase == .ready {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Continue") { model.continueInApp() }
                            .disabled(!model.canContinue)
                    }
                }
            }
        }
        .task { await model.load() }
    }

    private var form: some View {
        Form {
            Section {
                TextField("What should Devin do?", text: $model.draft.prompt, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("Task")
            } footer: {
                if model.draft.prompt.isEmpty, model.draft.repos.isEmpty == false || model.draft.attachments.isEmpty == false {
                    Text("You can write the task here or in Devin.")
                }
            }

            if !model.draft.repos.isEmpty {
                Section("Repositories") {
                    ForEach(model.draft.repos, id: \.self) { repo in
                        HStack {
                            Image(systemName: "folder")
                            Text(repo).lineLimit(1)
                            Spacer()
                            Button { model.removeRepo(repo) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(repo)")
                        }
                    }
                }
            }

            if !model.draft.attachments.isEmpty || !model.skipped.isEmpty {
                Section {
                    ForEach(model.draft.attachments) { attachment in
                        HStack(spacing: 12) {
                            thumbnail(for: attachment)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(attachment.filename).font(.subheadline).lineLimit(1)
                                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { model.removeAttachment(attachment.id) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(attachment.filename)")
                        }
                    }
                } header: {
                    Text("Attachments")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if !model.draft.attachments.isEmpty {
                            Text("Uploaded when the session is created.")
                        }
                        ForEach(model.skipped, id: \.self) { Text($0) }
                    }
                }
            }

            if let error = model.saveError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }

            Section {
                Button { model.continueInApp() } label: {
                    Label("Continue in Devin", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canContinue)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                if model.draft.isEmpty {
                    Text("Nothing here Devin can use — share a link, some text or a picture.")
                } else if !model.isSignedIn {
                    Text("You're not signed in to Devin yet. The draft waits until you are.")
                } else {
                    Text("Devin opens with the New Session form filled in; nothing starts until you tap Start there.")
                }
            }
        }
    }

    private func handedOff(opened: Bool) -> some View {
        ContentUnavailableView {
            Label(opened ? "Continuing in Devin" : "Saved for Devin", systemImage: opened ? "checkmark.circle" : "tray.and.arrow.down")
        } description: {
            Text(opened
                 ? "The New Session form is waiting in the app."
                 : "Open Devin to finish — the New Session form will be filled in for you.")
        } actions: {
            Button("Done") { model.done() }.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func thumbnail(for attachment: SharedDraft.Attachment) -> some View {
        if let image = model.thumbnails[attachment.id] {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: attachment.isImage ? "photo" : "doc")
                .font(.title2)
                .frame(width: 56, height: 56)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
