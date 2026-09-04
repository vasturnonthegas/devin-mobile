import Foundation
import Observation
import DevinKit

/// Edits one session's tags optimistically: the UI shows the desired set immediately, the
/// server's answer replaces it on success, and the store's copy is shown again on failure.
@Observable
@MainActor
final class SessionTagsModel {
    let store: SessionStore
    let sessionID: String

    var draft = ""
    var error: String?
    /// Desired tag set while writes are in flight; nil means the store's copy is authoritative.
    private(set) var pending: [String]?
    @ObservationIgnored private var inFlight = 0

    init(store: SessionStore, sessionID: String) {
        self.store = store
        self.sessionID = sessionID
    }

    private var committed: [String] { store.session(id: sessionID)?.tags ?? [] }

    var tags: [String] { pending ?? committed }
    var isSaving: Bool { inFlight > 0 }
    var canAddMore: Bool { tags.count < SessionTags.maxCount }

    func isPending(_ tag: String) -> Bool {
        pending != nil && !committed.contains(tag)
    }

    /// Commits `draft` as a new tag. Returns false when nothing was sent (empty, duplicate, or over the cap).
    @discardableResult
    func add() async -> Bool {
        guard let tag = SessionTags.normalize(draft) else {
            draft = ""
            return false
        }
        guard !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else {
            draft = ""
            return false
        }
        guard canAddMore else {
            error = "Sessions can have at most \(SessionTags.maxCount) tags."
            return false
        }

        draft = ""
        error = nil
        pending = tags + [tag]
        inFlight += 1
        do {
            let result = try await store.client.appendTags([tag], org: store.orgID, id: sessionID)
            commit(result)
            return true
        } catch {
            rollback(error)
            draft = tag
            return false
        }
    }

    func remove(_ tag: String) async {
        let desired = tags.filter { $0 != tag }
        guard desired.count != tags.count else { return }

        error = nil
        pending = desired
        inFlight += 1
        do {
            let result = try await store.client.replaceTags(desired, org: store.orgID, id: sessionID)
            commit(result)
        } catch {
            rollback(error)
        }
    }

    private func commit(_ serverTags: [String]) {
        inFlight -= 1
        if var session = store.session(id: sessionID) {
            session.tags = serverTags
            store.apply(session)
        }
        if inFlight == 0 { pending = nil }
    }

    private func rollback(_ error: Error) {
        inFlight -= 1
        pending = nil
        self.error = error.localizedDescription
    }
}
