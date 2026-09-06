import Foundation

/// Typed view of `SessionPullRequest.pr_state`, which the API declares as a free-form nullable
/// string. Anything not modelled here (or `null`) is `.unknown` and must render neutrally.
public enum PullRequestState: Hashable, Sendable {
    case open, draft, merged, closed
    case unknown(String?)

    public init(rawValue: String?) {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "open", "opened": self = .open
        case "draft": self = .draft
        case "merged": self = .merged
        case "closed": self = .closed
        default: self = .unknown(rawValue)
        }
    }

    public var displayName: String {
        switch self {
        case .open: "Open"
        case .draft: "Draft"
        case .merged: "Merged"
        case .closed: "Closed"
        case .unknown(let raw): Self.humanize(raw)
        }
    }

    private static func humanize(_ raw: String?) -> String {
        let cleaned = raw?.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? "Unknown" : cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }

    /// Merged or closed PRs no longer change; open/draft ones are worth re-polling more eagerly.
    public var isResolved: Bool {
        switch self {
        case .merged, .closed: true
        case .open, .draft, .unknown: false
        }
    }
}

public extension PullRequest {
    var stateKind: PullRequestState { PullRequestState(rawValue: state) }

    /// `owner/repo#123` for GitHub/GitLab-style URLs (GitLab's `/-/` separator is ignored),
    /// otherwise the host + path.
    var shortLabel: String {
        let parts = url.pathComponents.filter { $0 != "/" && $0 != "-" }
        if parts.count >= 4, ["pull", "pulls", "merge_requests"].contains(parts[2]) {
            return "\(parts[0])/\(parts[1])#\(parts[3])"
        }
        return (url.host ?? "") + url.path
    }
}
