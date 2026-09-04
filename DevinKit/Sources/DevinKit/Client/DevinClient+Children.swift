import Foundation

public extension DevinClient {
    /// Sessions spawned by `parentID`, including archived ones so the list matches `child_session_ids`.
    func childSessions(org: String, of parentID: String, first: Int = 100) async throws -> Page<Session> {
        try await sessions(org: org, query: SessionQuery(first: first, isArchived: nil, parentSessionID: parentID))
    }
}
