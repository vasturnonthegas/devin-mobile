import Foundation

// MARK: Knowledge notes, folders and secrets

public extension DevinClient {
    /// `search` is matched server-side; `folderPath`/`pinnedRepo` narrow the list further.
    func knowledgeNotes(
        org: String,
        search: String? = nil,
        folderPath: String? = nil,
        pinnedRepo: String? = nil,
        after: String? = nil,
        first: Int = 100
    ) async throws -> Page<KnowledgeNote> {
        var items = [URLQueryItem(name: "first", value: String(first))]
        if let after { items.append(URLQueryItem(name: "after", value: after)) }
        if let search, !search.isEmpty { items.append(URLQueryItem(name: "search", value: search)) }
        if let folderPath { items.append(URLQueryItem(name: "folder_path", value: folderPath)) }
        if let pinnedRepo { items.append(URLQueryItem(name: "pinned_repo", value: pinnedRepo)) }
        return try await request(.get, "/v3/organizations/\(org)/knowledge/notes", query: items)
    }

    /// Follows the cursor until every note has been fetched.
    func allKnowledgeNotes(org: String) async throws -> [KnowledgeNote] {
        var all: [KnowledgeNote] = []
        var cursor: String? = nil
        repeat {
            let page = try await knowledgeNotes(org: org, after: cursor, first: 200)
            all += page.items
            cursor = page.hasNextPage ? page.endCursor : nil
        } while cursor != nil
        return all
    }

    func knowledgeFolders(org: String) async throws -> KnowledgeFolderTree {
        try await request(.get, "/v3/organizations/\(org)/knowledge/folders")
    }

    /// Secret metadata only — the API never returns values.
    func secrets(org: String, after: String? = nil, first: Int = 100) async throws -> Page<OrgSecret> {
        var items = [URLQueryItem(name: "first", value: String(first))]
        if let after { items.append(URLQueryItem(name: "after", value: after)) }
        return try await request(.get, "/v3/organizations/\(org)/secrets", query: items)
    }

    /// Follows the cursor until every secret has been fetched.
    func allSecrets(org: String) async throws -> [OrgSecret] {
        var all: [OrgSecret] = []
        var cursor: String? = nil
        repeat {
            let page = try await secrets(org: org, after: cursor, first: 200)
            all += page.items
            cursor = page.hasNextPage ? page.endCursor : nil
        } while cursor != nil
        return all
    }
}
