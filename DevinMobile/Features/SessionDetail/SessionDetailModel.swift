import Foundation
import Observation
import DevinKit

@Observable
@MainActor
final class SessionDetailModel {
    let store: SessionStore
    let sessionID: String

    private(set) var messages: [SessionMessage] = []
    private(set) var isLoadingTranscript = false
    private(set) var isSending = false
    var draft = ""
    var error: String?

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(store: SessionStore, sessionID: String) {
        self.store = store
        self.sessionID = sessionID
    }

    var session: Session? { store.session(id: sessionID) }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && (session?.isActive ?? false)
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
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await store.client.send(message: text, org: store.orgID, id: sessionID)
            draft = ""
            // Optimistically show the message; the next poll replaces it with the server copy.
            messages.append(SessionMessage(eventID: "local-\(UUID().uuidString)", source: .user, message: text, createdAt: .now))
            await refresh()
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
