import Foundation

// MARK: Playbook detail

public extension DevinClient {
    /// Full playbook including `body`; the list endpoint returns the same shape, but callers that
    /// only hold an ID (session filters, deep links) need this to show the prompt template.
    func playbook(org: String, id: String) async throws -> Playbook {
        try await request(.get, "/v3/organizations/\(org)/playbooks/\(id)")
    }
}
