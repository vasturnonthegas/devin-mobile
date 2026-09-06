import Foundation

public enum PRReviewStatus: String, Codable, Sendable, CaseIterable {
    case pending, running, completed, errored, cancelled, skipped

    /// The review worker will not change this status again.
    public var isTerminal: Bool {
        switch self {
        case .pending, .running: false
        case .completed, .errored, .cancelled, .skipped: true
        }
    }

    public var displayName: String {
        switch self {
        case .pending: "Review queued"
        case .running: "Reviewing"
        case .completed: "Reviewed"
        case .errored: "Review failed"
        case .cancelled: "Review cancelled"
        case .skipped: "Review skipped"
        }
    }
}

/// Mirrors `PrReviewResponse` in the Devin v3 OpenAPI schema: the latest Devin Review of one PR head commit.
public struct PRReview: Codable, Hashable, Sendable {
    /// nil when the API returns a status this build doesn't know; `rawStatus` still carries it.
    public let status: PRReviewStatus?
    public let rawStatus: String
    public let repoPath: String
    public let prNumber: Int
    public let commitSHA: String
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case repoPath = "repo_path"
        case prNumber = "pr_number"
        case commitSHA = "commit_sha"
        case createdAt = "created_at"
    }

    public init(status: PRReviewStatus?, rawStatus: String? = nil, repoPath: String, prNumber: Int, commitSHA: String, createdAt: Date) {
        self.status = status
        self.rawStatus = rawStatus ?? status?.rawValue ?? ""
        self.repoPath = repoPath
        self.prNumber = prNumber
        self.commitSHA = commitSHA
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rawStatus = try c.decode(String.self, forKey: .status)
        status = PRReviewStatus(rawValue: rawStatus)
        repoPath = try c.decode(String.self, forKey: .repoPath)
        prNumber = try c.decode(Int.self, forKey: .prNumber)
        commitSHA = try c.decode(String.self, forKey: .commitSHA)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rawStatus, forKey: .status)
        try c.encode(repoPath, forKey: .repoPath)
        try c.encode(prNumber, forKey: .prNumber)
        try c.encode(commitSHA, forKey: .commitSHA)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

public extension PRReview {
    /// Unknown statuses count as finished so a poller never spins on a value it can't interpret.
    var isFinished: Bool { status?.isTerminal ?? true }

    var isInProgress: Bool { !isFinished }

    var statusSummary: String {
        status?.displayName ?? rawStatus.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var shortCommitSHA: String { String(commitSHA.prefix(7)) }
}

/// Mirrors `PrReviewCreateRequest`.
public struct PRReviewRequest: Codable, Hashable, Sendable {
    public let prURL: URL

    enum CodingKeys: String, CodingKey {
        case prURL = "pr_url"
    }

    public init(prURL: URL) {
        self.prURL = prURL
    }
}
