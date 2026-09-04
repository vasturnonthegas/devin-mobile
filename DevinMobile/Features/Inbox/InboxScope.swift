import Foundation
import Observation
import DevinKit

/// Which sessions the inbox shows: the signed-in user's own, or the whole organization's.
enum InboxScope: String, CaseIterable, Identifiable, Sendable {
    case mine, everyone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mine: "Mine"
        case .everyone: "Everyone"
        }
    }

    var systemImage: String {
        switch self {
        case .mine: "person"
        case .everyone: "person.3"
        }
    }

    var emptyTitle: String {
        switch self {
        case .mine: "No sessions of yours"
        case .everyone: "No sessions yet"
        }
    }

    var emptyDescription: String {
        switch self {
        case .mine: "Sessions you start appear here. Switch to Everyone to see the whole organization."
        case .everyone: "Tap + to give Devin something to do."
        }
    }
}

/// Owns the persisted scope choice and resolves who "me" is via `GET /v3/self`.
///
/// `Session.userID` is only comparable once the principal's `userID` is known, so the last
/// resolved ID is cached per organization to avoid a flash of everyone's sessions on launch.
/// Service-user keys have no `userID`; for them Mine is unavailable and Everyone is shown.
@Observable
@MainActor
final class InboxScopeModel {
    private static let scopeKey = "inboxScope"
    private static func userKey(_ orgID: String) -> String { "inboxCurrentUserID.\(orgID)" }

    private let client: DevinClient
    private let orgID: String
    private let defaults: UserDefaults

    var scope: InboxScope {
        didSet { defaults.set(scope.rawValue, forKey: Self.scopeKey) }
    }

    private(set) var currentUserID: String?
    private(set) var isResolved = false

    init(client: DevinClient, orgID: String, defaults: UserDefaults = .standard) {
        self.client = client
        self.orgID = orgID
        self.defaults = defaults
        self.scope = defaults.string(forKey: Self.scopeKey).flatMap(InboxScope.init) ?? .mine
        self.currentUserID = defaults.string(forKey: Self.userKey(orgID))
    }

    var isMineAvailable: Bool { currentUserID != nil || !isResolved }

    /// First launch with no cached ID: nothing can be classified as Mine yet.
    var isIdentityPending: Bool { currentUserID == nil && !isResolved }

    /// The scope actually applied to the list.
    var effectiveScope: InboxScope { isMineAvailable ? scope : .everyone }

    func resolveIdentity() async {
        defer { isResolved = true }
        guard let me = try? await client.me() else { return }
        currentUserID = me.userID
        defaults.set(me.userID, forKey: Self.userKey(orgID))
    }

    func includes(_ session: Session) -> Bool {
        switch effectiveScope {
        case .everyone: true
        case .mine: currentUserID != nil && session.userID == currentUserID
        }
    }

    func filter(_ groups: [(bucket: Session.Bucket, sessions: [Session])]) -> [(bucket: Session.Bucket, sessions: [Session])] {
        guard effectiveScope == .mine else { return groups }
        return groups.compactMap { group in
            let matches = group.sessions.filter(includes)
            return matches.isEmpty ? nil : (group.bucket, matches)
        }
    }
}
