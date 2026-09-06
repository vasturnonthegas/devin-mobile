import Foundation

/// A repository Devin can be pointed at (`RepositoryResponse` in the v3beta1 OpenAPI schema).
/// Identity is `repoPath`; the provider ID is only meaningful together with `gitConnectionID`.
public struct Repository: Codable, Identifiable, Hashable, Sendable {
    public let providerRepositoryID: String
    public let gitConnectionID: String
    /// Bare host, e.g. `github.com`.
    public let gitConnectionHost: String
    /// Short name, e.g. `api`.
    public let repoName: String
    /// `owner/repo`, or host-prefixed `github.com/owner/repo` depending on the provider.
    public let repoPath: String
    public let repoDescription: String?
    public let lastUpdatedAt: Date?
    public let repoLanguage: String?
    /// Absent when the list was fetched with `load_indexing_status=false`.
    public let indexingStatus: RepoIndexingStatus?

    public var id: String { repoPath }

    enum CodingKeys: String, CodingKey {
        case providerRepositoryID = "provider_repository_id"
        case gitConnectionID = "git_connection_id"
        case gitConnectionHost = "git_connection_host"
        case repoName = "repo_name"
        case repoPath = "repo_path"
        case repoDescription = "repo_description"
        case lastUpdatedAt = "last_updated_at"
        case repoLanguage = "repo_language"
        case indexingStatus = "indexing_status"
    }

    public init(
        providerRepositoryID: String,
        gitConnectionID: String,
        gitConnectionHost: String,
        repoName: String,
        repoPath: String,
        repoDescription: String? = nil,
        lastUpdatedAt: Date? = nil,
        repoLanguage: String? = nil,
        indexingStatus: RepoIndexingStatus? = nil
    ) {
        self.providerRepositoryID = providerRepositoryID
        self.gitConnectionID = gitConnectionID
        self.gitConnectionHost = gitConnectionHost
        self.repoName = repoName
        self.repoPath = repoPath
        self.repoDescription = repoDescription
        self.lastUpdatedAt = lastUpdatedAt
        self.repoLanguage = repoLanguage
        self.indexingStatus = indexingStatus
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        providerRepositoryID = try c.decode(String.self, forKey: .providerRepositoryID)
        gitConnectionID = try c.decode(String.self, forKey: .gitConnectionID)
        gitConnectionHost = try c.decode(String.self, forKey: .gitConnectionHost)
        repoName = try c.decode(String.self, forKey: .repoName)
        repoPath = try c.decode(String.self, forKey: .repoPath)
        repoDescription = try c.decodeIfPresent(String.self, forKey: .repoDescription)
        lastUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .lastUpdatedAt)
        repoLanguage = try c.decodeIfPresent(String.self, forKey: .repoLanguage)
        indexingStatus = try c.decodeIfPresent(RepoIndexingStatus.self, forKey: .indexingStatus)
    }

    /// The value `NewSessionRequest.repos` expects: host-prefixed, like `github.com/owner/repo`.
    /// The sessions API accepts this form for every provider, whereas `repoPath` may omit the host.
    public var fullPath: String {
        var host = gitConnectionHost
        for prefix in ["https://", "http://"] where host.hasPrefix(prefix) { host.removeFirst(prefix.count) }
        while host.hasSuffix("/") { host.removeLast() }
        let firstComponent = repoPath.split(separator: "/").first.map(String.init) ?? ""
        if host.isEmpty || firstComponent == host || firstComponent.contains(".") { return repoPath }
        return "\(host)/\(repoPath)"
    }

    /// `owner/repo` without the host, for matching against `Session` repo filters and typed input.
    public var shortPath: String {
        let parts = fullPath.split(separator: "/")
        guard parts.count >= 3, parts[0].contains(".") else { return fullPath }
        return parts.dropFirst().joined(separator: "/")
    }
}

/// Mirrors `RepoIndexingStatusResponse`; only the parts the app displays are decoded.
public struct RepoIndexingStatus: Codable, Hashable, Sendable {
    public let indexingEnabled: Bool
    public let latestIndexes: [RepoIndexJob]

    enum CodingKeys: String, CodingKey {
        case indexingEnabled = "indexing_enabled"
        case latestIndexes = "latest_indexes"
    }

    public init(indexingEnabled: Bool, latestIndexes: [RepoIndexJob] = []) {
        self.indexingEnabled = indexingEnabled
        self.latestIndexes = latestIndexes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        indexingEnabled = try c.decodeIfPresent(Bool.self, forKey: .indexingEnabled) ?? false
        latestIndexes = try c.decodeIfPresent([RepoIndexJob].self, forKey: .latestIndexes) ?? []
    }
}

public enum RepoIndexJobStatus: String, Codable, Sendable, CaseIterable {
    case failed, completed, inProgress = "in_progress"
}

/// Mirrors `RepoIndexJobResponse`.
public struct RepoIndexJob: Codable, Hashable, Sendable {
    public let jobID: String
    /// nil when the server reports a status this build doesn't know; see `rawStatus`.
    public let status: RepoIndexJobStatus?
    public let rawStatus: String
    public let commit: String
    public let branchName: String?
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case status, commit
        case branchName = "branch_name"
        case createdAt = "created_at"
    }

    public init(jobID: String, status: RepoIndexJobStatus, commit: String, branchName: String? = nil, createdAt: Date) {
        self.jobID = jobID
        self.status = status
        self.rawStatus = status.rawValue
        self.commit = commit
        self.branchName = branchName
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        jobID = try c.decode(String.self, forKey: .jobID)
        rawStatus = try c.decode(String.self, forKey: .status)
        status = RepoIndexJobStatus(rawValue: rawStatus)
        commit = try c.decode(String.self, forKey: .commit)
        branchName = try c.decodeIfPresent(String.self, forKey: .branchName)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(jobID, forKey: .jobID)
        try c.encode(rawStatus, forKey: .status)
        try c.encode(commit, forKey: .commit)
        try c.encode(branchName, forKey: .branchName)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

/// Query parameters for `GET /v3beta1/organizations/{org}/repositories`.
public struct RepositoryQuery: Hashable, Sendable {
    /// Page size; the API caps this at 100.
    public var first: Int
    public var after: String?
    /// Server-side substring match on the repository name.
    public var filterName: String?
    /// Indexing status is expensive server-side; the picker doesn't need it.
    public var loadIndexingStatus: Bool

    public init(first: Int = 50, after: String? = nil, filterName: String? = nil, loadIndexingStatus: Bool = false) {
        self.first = first
        self.after = after
        self.filterName = filterName
        self.loadIndexingStatus = loadIndexingStatus
    }

    public var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "first", value: String(min(max(first, 1), 100)))]
        if let after, !after.isEmpty { items.append(URLQueryItem(name: "after", value: after)) }
        let trimmed = filterName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "filter_name", value: trimmed)) }
        if !loadIndexingStatus { items.append(URLQueryItem(name: "load_indexing_status", value: "false")) }
        return items
    }
}
