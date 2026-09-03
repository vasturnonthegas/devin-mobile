import Foundation

// MARK: Session tags

public extension DevinClient {
    func sessionTags(org: String, id: String) async throws -> [String] {
        let response: SessionTags = try await request(.get, "/v3/organizations/\(org)/sessions/\(id)/tags")
        return response.tags
    }

    /// Replaces the full tag set. Returns the tags as stored by the server.
    func replaceTags(_ tags: [String], org: String, id: String) async throws -> [String] {
        let response: SessionTags = try await request(.put, "/v3/organizations/\(org)/sessions/\(id)/tags", body: SessionTags(tags: tags))
        return response.tags
    }

    /// Appends tags; the server deduplicates against existing ones. Returns the resulting tag set.
    func appendTags(_ tags: [String], org: String, id: String) async throws -> [String] {
        let response: SessionTags = try await request(.post, "/v3/organizations/\(org)/sessions/\(id)/tags", body: SessionTags(tags: tags))
        return response.tags
    }
}
