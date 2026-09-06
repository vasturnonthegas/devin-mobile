import Foundation

public enum SessionStatus: String, Codable, Sendable, CaseIterable {
    case new, claimed, running, exit, error, suspended, resuming
}

public enum SessionStatusDetail: String, Codable, Sendable {
    case working
    case waitingForUser = "waiting_for_user"
    case waitingForApproval = "waiting_for_approval"
    case finished
    case inactivity
    case userRequest = "user_request"
    case usageLimitExceeded = "usage_limit_exceeded"
    case outOfCredits = "out_of_credits"
    case outOfQuota = "out_of_quota"
    case noQuotaAllocation = "no_quota_allocation"
    case paymentDeclined = "payment_declined"
    case orgUsageLimitExceeded = "org_usage_limit_exceeded"
    case userUsageLimitExceeded = "user_usage_limit_exceeded"
    case totalSessionLimitExceeded = "total_session_limit_exceeded"
    case error
}

public enum DevinMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case normal, fast, lite, ultra, fusion

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .normal: "Agent"
        case .fast: "Fast"
        case .lite: "Lite"
        case .ultra: "Ultra"
        case .fusion: "Fusion"
        }
    }
}

public enum SessionOrigin: String, Codable, Sendable, CaseIterable, Identifiable {
    case webapp, slack, teams, api, linear, jira, automation, cli, desktop, other
    case codeScan = "code_scan"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .webapp: "Web app"
        case .slack: "Slack"
        case .teams: "Teams"
        case .api: "API"
        case .linear: "Linear"
        case .jira: "Jira"
        case .automation: "Automation"
        case .cli: "CLI"
        case .desktop: "Desktop"
        case .codeScan: "Code scan"
        case .other: "Other"
        }
    }
}

public struct PullRequest: Codable, Hashable, Sendable {
    public let url: URL
    public let state: String?

    enum CodingKeys: String, CodingKey {
        case url = "pr_url"
        case state = "pr_state"
    }

    public init(url: URL, state: String?) {
        self.url = url
        self.state = state
    }
}

/// Mirrors `SessionResponse` in the Devin v3 OpenAPI schema.
public struct Session: Codable, Identifiable, Hashable, Sendable {
    public let sessionID: String
    public let orgID: String
    public let status: SessionStatus
    public let statusDetail: SessionStatusDetail?
    public let title: String?
    public let url: URL
    public var tags: [String]
    public let pullRequests: [PullRequest]
    public let acusConsumed: Double
    public let createdAt: Date
    public let updatedAt: Date
    public let isArchived: Bool
    public let devinMode: DevinMode?
    public let origin: SessionOrigin?
    public let playbookID: String?
    public let parentSessionID: String?
    public let childSessionIDs: [String]?
    public let userID: String?
    public let category: SessionCategory?
    public let subcategory: String?
    public let automationID: String?
    public let structuredOutput: JSONValue?

    public var id: String { sessionID }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case orgID = "org_id"
        case status
        case statusDetail = "status_detail"
        case title
        case url
        case tags
        case pullRequests = "pull_requests"
        case acusConsumed = "acus_consumed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isArchived = "is_archived"
        case devinMode = "devin_mode"
        case origin
        case playbookID = "playbook_id"
        case parentSessionID = "parent_session_id"
        case childSessionIDs = "child_session_ids"
        case userID = "user_id"
        case category
        case subcategory
        case automationID = "automation_id"
        case structuredOutput = "structured_output"
    }

    public init(
        sessionID: String,
        orgID: String,
        status: SessionStatus,
        statusDetail: SessionStatusDetail? = nil,
        title: String? = nil,
        url: URL,
        tags: [String] = [],
        pullRequests: [PullRequest] = [],
        acusConsumed: Double = 0,
        createdAt: Date,
        updatedAt: Date,
        isArchived: Bool = false,
        devinMode: DevinMode? = nil,
        origin: SessionOrigin? = nil,
        playbookID: String? = nil,
        parentSessionID: String? = nil,
        childSessionIDs: [String]? = nil,
        userID: String? = nil,
        category: SessionCategory? = nil,
        subcategory: String? = nil,
        automationID: String? = nil,
        structuredOutput: JSONValue? = nil
    ) {
        self.sessionID = sessionID
        self.orgID = orgID
        self.status = status
        self.statusDetail = statusDetail
        self.title = title
        self.url = url
        self.tags = tags
        self.pullRequests = pullRequests
        self.acusConsumed = acusConsumed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.devinMode = devinMode
        self.origin = origin
        self.playbookID = playbookID
        self.parentSessionID = parentSessionID
        self.childSessionIDs = childSessionIDs
        self.userID = userID
        self.category = category
        self.subcategory = subcategory
        self.automationID = automationID
        self.structuredOutput = structuredOutput
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.decode(String.self, forKey: .sessionID)
        orgID = try c.decode(String.self, forKey: .orgID)
        status = try c.decode(SessionStatus.self, forKey: .status)
        statusDetail = try? c.decodeIfPresent(SessionStatusDetail.self, forKey: .statusDetail)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        url = try c.decode(URL.self, forKey: .url)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        pullRequests = try c.decodeIfPresent([PullRequest].self, forKey: .pullRequests) ?? []
        acusConsumed = try c.decodeIfPresent(Double.self, forKey: .acusConsumed) ?? 0
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        devinMode = try? c.decodeIfPresent(DevinMode.self, forKey: .devinMode)
        origin = try? c.decodeIfPresent(SessionOrigin.self, forKey: .origin)
        playbookID = try c.decodeIfPresent(String.self, forKey: .playbookID)
        parentSessionID = try c.decodeIfPresent(String.self, forKey: .parentSessionID)
        childSessionIDs = try c.decodeIfPresent([String].self, forKey: .childSessionIDs)
        userID = try c.decodeIfPresent(String.self, forKey: .userID)
        category = try? c.decodeIfPresent(SessionCategory.self, forKey: .category)
        subcategory = try c.decodeIfPresent(String.self, forKey: .subcategory)
        automationID = try c.decodeIfPresent(String.self, forKey: .automationID)
        structuredOutput = try? c.decodeIfPresent(JSONValue.self, forKey: .structuredOutput)
    }
}

// MARK: - Derived state for the UI

public extension Session {
    /// Coarse bucket used to group sessions in the inbox.
    enum Bucket: Int, CaseIterable, Sendable, Comparable {
        case needsYou, working, finished, sleeping, failed

        public static func < (lhs: Bucket, rhs: Bucket) -> Bool { lhs.rawValue < rhs.rawValue }

        public var title: String {
            switch self {
            case .needsYou: "Needs you"
            case .working: "Working"
            case .finished: "Finished"
            case .sleeping: "Sleeping"
            case .failed: "Failed"
            }
        }
    }

    var bucket: Bucket {
        switch status {
        case .running, .resuming, .claimed, .new:
            switch statusDetail {
            case .waitingForUser, .waitingForApproval: return .needsYou
            case .finished: return .finished
            default: return .working
            }
        case .suspended, .exit:
            return statusDetail == .finished ? .finished : .sleeping
        case .error:
            return .failed
        }
    }

    var needsAttention: Bool { bucket == .needsYou }

    var isActive: Bool {
        switch status {
        case .running, .resuming, .claimed, .new: true
        case .exit, .error, .suspended: false
        }
    }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return sessionID
    }

    /// Human-readable one-liner for the current state.
    var statusSummary: String {
        switch (status, statusDetail) {
        case (_, .waitingForUser): "Waiting for you"
        case (_, .waitingForApproval): "Needs approval"
        case (_, .working): "Working"
        case (_, .finished): "Finished"
        case (.suspended, .inactivity): "Asleep (inactive)"
        case (.suspended, .userRequest): "Asleep"
        case (.suspended, .some(let d)): "Stopped: \(d.rawValue.replacingOccurrences(of: "_", with: " "))"
        case (.suspended, nil): "Asleep"
        case (.resuming, _): "Resuming"
        case (.new, _), (.claimed, _): "Starting"
        case (.running, _): "Running"
        case (.exit, _): "Exited"
        case (.error, _): "Error"
        }
    }
}
