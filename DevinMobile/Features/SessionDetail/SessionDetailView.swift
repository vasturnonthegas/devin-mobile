import SwiftUI
import UIKit
import DevinKit

struct SessionDetailView: View {
    @State private var model: SessionDetailModel
    @State private var attachments: SessionAttachmentsModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var confirmTerminate = false
    @FocusState private var composerFocused: Bool

    init(store: SessionStore, sessionID: String) {
        _model = State(initialValue: SessionDetailModel(store: store, sessionID: sessionID))
        _attachments = State(initialValue: SessionAttachmentsModel(store: store, sessionID: sessionID))
    }

    var body: some View {
        Group {
            if let session = model.session {
                transcript(for: session)
                    .safeAreaInset(edge: .bottom, spacing: 0) { composer(for: session) }
                    .navigationTitle(session.displayTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbar(for: session) }
            } else {
                ContentUnavailableView("Session not found", systemImage: "questionmark.folder")
            }
        }
        .task {
            model.startPolling()
        }
        .onDisappear { model.stopPolling() }
        .confirmationDialog("Terminate this session?", isPresented: $confirmTerminate, titleVisibility: .visible) {
            Button("Terminate", role: .destructive) {
                Task { if await model.terminate() { dismiss() } }
            }
        } message: {
            Text("The VM is destroyed and the session can't be resumed. Use Sleep if you might come back to it.")
        }
    }

    // MARK: Transcript

    private func transcript(for session: Session) -> some View {
        let placed = attachments.placement(in: model.messages)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                header(for: session, attachments: placed.unplaced)
                    .padding(.bottom, 4)

                if model.isLoadingTranscript {
                    ProgressView().frame(maxWidth: .infinity)
                } else if model.messages.isEmpty {
                    Text("No messages yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(model.messages) { message in
                    MessageBubble(message: message, attachments: placed.byMessage[message.id] ?? [], attachmentsModel: attachments)
                }

                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        // Attachments arrive with messages, so a transcript change is the cue to re-list them.
        .task(id: model.messages.count) { await attachments.load() }
    }

    private func header(for session: Session, attachments unplaced: [SessionAttachment]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusBadge(session: session)
                Spacer()
                if let mode = session.devinMode {
                    Text(mode.displayName).font(.caption).foregroundStyle(.secondary)
                }
                Text("\(session.acusConsumed, format: .number.precision(.fractionLength(0...2))) ACU")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if session.needsAttention {
                Label(
                    session.statusDetail == .waitingForApproval
                        ? "Devin is waiting for you to approve an action. Reply below or open the web app."
                        : "Devin asked you something. Reply below to unblock it.",
                    systemImage: "hand.raised.fill"
                )
                .font(.footnote)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }

            ForEach(session.pullRequests, id: \.url) { pr in
                PullRequestLink(pullRequest: pr)
                    .font(.subheadline)
            }

            SessionMetadataLine(session: session)

            SessionTagsEditor(store: model.store, sessionID: session.sessionID)

            if !unplaced.isEmpty {
                AttachmentsSection(attachments: unplaced, model: attachments)
            }

            if session.hasChildren {
                ChildSessionsSection(store: model.store, parent: session)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Composer

    private func composer(for session: Session) -> some View {
        VStack(spacing: 0) {
            Divider()
            if !model.attachments.items.isEmpty || model.attachments.error != nil {
                ComposerAttachmentsBar(attachments: model.attachments)
            }
            HStack(alignment: .bottom, spacing: 8) {
                AttachmentPickerButton(attachments: model.attachments)
                    .disabled(!session.isActive)

                TextField(
                    session.isActive ? "Message Devin…" : "Session is asleep — messages resume it",
                    text: $model.draft,
                    axis: .vertical
                )
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
                .focused($composerFocused)

                Button {
                    Task { await model.send() }
                } label: {
                    if model.isSending {
                        ProgressView().frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                    }
                }
                .disabled(!model.canSend)
                .sensoryFeedback(.success, trigger: model.isSending) { old, new in old && !new }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func toolbar(for session: Session) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Open in Devin", systemImage: "safari") { openURL(session.url) }
                ShareLink(item: session.url) { Label("Share link", systemImage: "square.and.arrow.up") }
                Button("Copy session ID", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = session.sessionID
                }
                Divider()
                Button("Sleep & archive", systemImage: "moon.zzz") {
                    Task { if await model.archive() { dismiss() } }
                }
                Button("Terminate", systemImage: "xmark.octagon", role: .destructive) {
                    confirmTerminate = true
                }
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
        }
    }
}

struct MessageBubble: View {
    let message: SessionMessage
    var attachments: [SessionAttachment] = []
    var attachmentsModel: SessionAttachmentsModel? = nil

    private var isUser: Bool { message.source == .user }
    private var background: AnyShapeStyle { isUser ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary) }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
            MarkdownMessageBody(markdown: message.message, fade: background)
                .tint(isUser ? .white : .accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(background, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(isUser ? .white : .primary)
            if let attachmentsModel, !attachments.isEmpty {
                AttachmentStrip(attachments: attachments, model: attachmentsModel)
                    .padding(.top, 3)
            }
            Text(message.createdAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(isUser ? .leading : .trailing, 40)
    }
}
