import Foundation

// MARK: Repositories

public extension DevinClient {
    /// Repositories the organization's git connections expose. Searchable via `RepositoryQuery.filterName`;
    /// follow `Page.endCursor` with `RepositoryQuery.after` for the next page.
    func repositories(org: String, query: RepositoryQuery = RepositoryQuery()) async throws -> Page<Repository> {
        try await request(.get, "/v3beta1/organizations/\(org)/repositories", query: query.queryItems)
    }
}
