import Foundation

/// A `github.com` URL resolved to the repository it belongs to, so a shared link can prefill
/// `NewSessionRequest.repos` (`repoPath` is the host-prefixed form the sessions API expects).
public struct GitHubLink: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// `github.com/owner/repo` — nothing but the repository.
        case repository
        case pullRequest(Int)
        case issue(Int)
        /// Anything deeper inside the repo (a file, a commit, a branch, a release, …).
        case other
    }

    public let owner: String
    public let repo: String
    public let kind: Kind
    public let url: URL

    /// `github.com/owner/repo`.
    public var repoPath: String { "github.com/\(owner)/\(repo)" }

    /// Top-level github.com paths that are not a user or organisation.
    static let reservedOwners: Set<String> = [
        "about", "apps", "codespaces", "collections", "contact", "customer-stories", "enterprise",
        "events", "explore", "features", "issues", "login", "marketplace", "new", "notifications",
        "orgs", "pricing", "pulls", "search", "security", "settings", "sponsors", "team", "topics",
        "trending", "users",
    ]

    public init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased(), host == "github.com" || host == "www.github.com"
        else { return nil }

        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        let owner = parts[0]
        var repo = parts[1]
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        guard Self.isValidSegment(owner), Self.isValidSegment(repo),
              !Self.reservedOwners.contains(owner.lowercased())
        else { return nil }

        self.owner = owner
        self.repo = repo
        self.url = url
        switch (parts.count, parts.dropFirst(2).first, parts.dropFirst(3).first.flatMap { Int($0) }) {
        case (2, _, _):
            kind = .repository
        case (_, "pull", let number?):
            kind = .pullRequest(number)
        case (_, "issues", let number?):
            kind = .issue(number)
        default:
            kind = .other
        }
    }

    private static func isValidSegment(_ segment: String) -> Bool {
        !segment.isEmpty && segment.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
    }

    /// Every GitHub link found in free text, in order of appearance, without duplicates.
    public static func links(in text: String) -> [GitHubLink] {
        guard let regex = try? NSRegularExpression(pattern: #"https?://(?:www\.)?github\.com/[^\s<>()\[\]"']+"#, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        var seen: Set<GitHubLink> = []
        return regex.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            var raw = String(text[range])
            while let last = raw.last, ".,;:!?".contains(last) { raw.removeLast() }
            guard let url = URL(string: raw), let link = GitHubLink(url: url), seen.insert(link).inserted else { return nil }
            return link
        }
    }
}
