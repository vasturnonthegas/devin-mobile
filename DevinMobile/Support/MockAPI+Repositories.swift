#if DEBUG
import Foundation
import DevinKit

/// `GET /v3beta1/organizations/{org}/repositories` for the mock: `repositoryCount` repos across two
/// hosts, filtered by `filter_name` (case-insensitive substring of `repo_name`) and paged by an
/// integer offset cursor so the picker's search + pagination can be exercised without a PAT.
extension MockAPI {
    static let repositoryCount = 120

    static let repositories: [Repository] = {
        let now = Date(timeIntervalSince1970: 1_756_900_000)
        let names = ["api", "web", "mobile", "infra", "docs", "billing", "auth", "search", "notifications", "analytics",
                     "design-system", "cli", "sdk-swift", "sdk-go", "sdk-python", "gateway", "worker", "scheduler"]
        let owners = ["acme", "acme-labs", "cognition"]
        let languages: [String?] = ["Swift", "TypeScript", "Go", "Python", nil, "Rust"]
        let descriptions: [String?] = ["Public REST API", "Customer-facing web app", nil, "Terraform + Helm charts",
                                       "Developer documentation", "Invoicing and metering"]
        return (0..<repositoryCount).map { i in
            let owner = owners[i % owners.count]
            let name = i < names.count ? names[i] : "\(names[i % names.count])-\(i / names.count)"
            let onGitLab = i % 9 == 8
            return Repository(
                providerRepositoryID: String(100_000 + i),
                gitConnectionID: onGitLab ? "gc-gitlab" : "gc-github",
                gitConnectionHost: onGitLab ? "gitlab.example.com" : "github.com",
                repoName: name,
                repoPath: onGitLab ? "gitlab.example.com/\(owner)/\(name)" : "\(owner)/\(name)",
                repoDescription: descriptions[i % descriptions.count],
                lastUpdatedAt: now.addingTimeInterval(-Double(i) * 7_200),
                repoLanguage: languages[i % languages.count]
            )
        }
    }()

    static func repositoriesPage(queryItems: [URLQueryItem]) -> Page<Repository> {
        let first = queryItems.first { $0.name == "first" }?.value.flatMap(Int.init) ?? 100
        let offset = queryItems.first { $0.name == "after" }?.value.flatMap(Int.init) ?? 0
        let filter = queryItems.first { $0.name == "filter_name" }?.value?.trimmingCharacters(in: .whitespaces) ?? ""
        let matching = filter.isEmpty ? repositories : repositories.filter { $0.repoName.localizedCaseInsensitiveContains(filter) }
        let slice = Array(matching.dropFirst(offset).prefix(first))
        let end = offset + slice.count
        return Page(items: slice,
                    endCursor: end < matching.count ? String(end) : nil,
                    hasNextPage: end < matching.count,
                    total: matching.count)
    }
}
#endif
