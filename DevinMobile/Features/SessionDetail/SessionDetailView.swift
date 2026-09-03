import SwiftUI
import UIKit
import DevinKit

struct SessionDetailView: View {
    @State private var model: SessionDetailModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var confirmTerminate = false
    @FocusState private var composerFocused: Bool

    init(store: SessionStore, sessionID: String) {
        _model = State(initialValue: SessionDetailModel(store: store, sessionID: sessionID))
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                header(for: session)
                    .padding(.bottom, 4)

                if model.isLoadingTranscript {
                    ProgressView().frame(maxWidth: .infinity)
                } else if model.messages.isEmpty {
                    Text("No messages yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(model.messages) { message in
                    MessageBubble(message: message)
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
    }

    private func header(for session: Session) -> some View {
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

            if !session.tags.isEmpty {
                Text(session.tags.map { "#\($0)" }.joined(separator: "  "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Composer

    private func composer(for session: Session) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
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

    private var isUser: Bool { message.source == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
            Text(LocalizedStringKey(message.message))
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isUser ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .foregroundStyle(isUser ? .white : .primary)
            Text(message.createdAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(isUser ? .leading : .trailing, 40)
    }
}
