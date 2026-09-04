import Foundation
import Observation
import DevinKit

/// Main-actor snapshot of `MemberDirectory` so rows can resolve `Session.userID` synchronously.
/// Nothing is shown until the directory has loaded; a 403 keeps it empty for the session lifetime.
@Observable
@MainActor
final class MemberLookup {
    private let directory: MemberDirectory
    private(set) var membersByID: [String: OrgMember] = [:]
    private(set) var isAvailable = false

    init(client: DevinClient, orgID: String) {
        directory = MemberDirectory(client: client, org: orgID)
    }

    func load() async {
        guard !isAvailable else { return }
        let state = await directory.load()
        guard state == .available else { return }
        let members = await directory.members
        membersByID = Dictionary(uniqueKeysWithValues: members.map { ($0.userID, $0) })
        isAvailable = true
    }

    func owner(of session: Session) -> OrgMember? {
        guard isAvailable, let userID = session.userID else { return nil }
        return membersByID[userID]
    }
}
