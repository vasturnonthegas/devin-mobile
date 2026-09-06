import Foundation
import Observation
import DevinKit

@Observable
@MainActor
final class SessionDetailModel {
    let store: SessionStore
    let sessionID: String
    let attachments: ComposerAttachments

    private(set) var messages: [SessionMessage] = []
    private(set) var isLoadingTranscript = false
    private(set) var isSending = false
    var draft = ""
    var error: String?

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(store: SessionStore, sessionID: String) {
        self.store = store
        self.sessionID = sessionID
        self.attachments = ComposerAttachments(client: store.client, orgID: store.orgID)
    }

    var session: Session? { store.session(id: sessionID) }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Text or attachments; never while an upload is in flight or failed (the user removes/retries first).
    var canSend: Bool {
        (!trimmedDraft.isEmpty || attachments.isReadyToSend)
            && !attachments.isUploading && !attachments.hasFailures
            && !isSending && (session?.messaging.acceptsMessages ?? false)
    }

    func refresh() async {
        isLoadingTranscript = messages.isEmpty
        defer { isLoadingTranscript = false }
        do {
            _ = try await store.reload(id: sessionID)
            messages = try await store.client.allMessages(org: store.orgID, id: sessionID)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let active = self?.session?.isActive ?? false
                try? await Task.sleep(for: .seconds(active ? 5 : 30))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func send() async {
        let urls = attachments.uploadedURLs
        let text = trimmedDraft.isEmpty && !urls.isEmpty ? attachments.fallbackMessage : trimmedDraft
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await store.client.send(message: text, attachmentURLs: urls, org: store.orgID, id: sessionID)
            draft = ""
            attachments.clear()
            // Optimistically show the message; the next poll replaces it with the server copy.
            messages.append(SessionMessage(eventID: "local-\(UUID().uuidString)", source: .user, message: text, createdAt: .now))
            // A message to a sleeping session resumes it: restart polling so the 30 s idle cadence
            // doesn't hide the suspended → resuming → running transition.
            startPolling()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func archive() async -> Bool {
        guard let session else { return false }
        do {
            try await store.archive(session)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func terminate() async -> Bool {
        guard let session else { return false }
        do {
            try await store.terminate(session)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
