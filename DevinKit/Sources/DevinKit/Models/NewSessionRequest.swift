import Foundation

/// Body of `POST /v3/organizations/{org_id}/sessions`.
public struct NewSessionRequest: Encodable, Hashable, Sendable {
    public var prompt: String
    public var repos: [String]?
    public var playbookID: String?
    public var devinMode: DevinMode?
    public var maxACULimit: Int?
    public var tags: [String]?
    public var title: String?
    public var attachmentURLs: [URL]?
    public var resumable: Bool?
    public var bypassApproval: Bool?
    public var platform: String?
    /// Draft-7 JSON Schema object; validate with `StructuredOutputSchema.parse` before setting.
    public var structuredOutputSchema: JSONValue?
    public var knowledgeIDs: [String]?
    public var secretIDs: [String]?
    /// Web URLs of related sessions Devin should read for context; build with `links(to:)`.
    public var sessionLinks: [String]?

    enum CodingKeys: String, CodingKey {
        case prompt, repos, tags, title, resumable, platform
        case playbookID = "playbook_id"
        case devinMode = "devin_mode"
        case maxACULimit = "max_acu_limit"
        case attachmentURLs = "attachment_urls"
        case bypassApproval = "bypass_approval"
        case structuredOutputSchema = "structured_output_schema"
        case knowledgeIDs = "knowledge_ids"
        case secretIDs = "secret_ids"
        case sessionLinks = "session_links"
    }

    public init(
        prompt: String,
        repos: [String]? = nil,
        playbookID: String? = nil,
        devinMode: DevinMode? = nil,
        maxACULimit: Int? = nil,
        tags: [String]? = nil,
        title: String? = nil,
        attachmentURLs: [URL]? = nil,
        resumable: Bool? = nil,
        bypassApproval: Bool? = nil,
        platform: String? = nil,
        structuredOutputSchema: JSONValue? = nil,
        knowledgeIDs: [String]? = nil,
        secretIDs: [String]? = nil,
        sessionLinks: [String]? = nil
    ) {
        self.prompt = prompt
        self.repos = repos
        self.playbookID = playbookID
        self.devinMode = devinMode
        self.maxACULimit = maxACULimit
        self.tags = tags
        self.title = title
        self.attachmentURLs = attachmentURLs
        self.resumable = resumable
        self.bypassApproval = bypassApproval
        self.platform = platform
        self.structuredOutputSchema = structuredOutputSchema
        self.knowledgeIDs = knowledgeIDs
        self.secretIDs = secretIDs
        self.sessionLinks = sessionLinks
    }
}

public extension NewSessionRequest {
    /// The spec types `session_links` as bare strings; the web app references a session by its
    /// `app.devin.ai/sessions/…` URL, so that is what gets sent. An empty list omits the key.
    static func links(to sessions: [Session]) -> [String]? {
        sessions.isEmpty ? nil : sessions.map(\.url.absoluteString)
    }
}

/// Filters for `GET /v3/organizations/{org_id}/sessions`.
/// Dates are sent as integer epoch seconds; list params repeat the key (`tags=a&tags=b`).
public struct SessionQuery: Hashable, Sendable {
    public var first: Int
    public var after: String?
    public var tags: [String]?
    public var isArchived: Bool?
    public var updatedAfter: Date?
    public var updatedBefore: Date?
    public var createdAfter: Date?
    public var createdBefore: Date?
    public var repoNames: [String]?
    public var userIDs: [String]?
    public var origins: [SessionOrigin]?
    public var playbookID: String?
    public var parentSessionID: String?

    public init(
        first: Int = 50,
        after: String? = nil,
        tags: [String]? = nil,
        isArchived: Bool? = false,
        updatedAfter: Date? = nil,
        updatedBefore: Date? = nil,
        createdAfter: Date? = nil,
        createdBefore: Date? = nil,
        repoNames: [String]? = nil,
        userIDs: [String]? = nil,
        origins: [SessionOrigin]? = nil,
        playbookID: String? = nil,
        parentSessionID: String? = nil
    ) {
        self.first = first
        self.after = after
        self.tags = tags
        self.isArchived = isArchived
        self.updatedAfter = updatedAfter
        self.updatedBefore = updatedBefore
        self.createdAfter = createdAfter
        self.createdBefore = createdBefore
        self.repoNames = repoNames
        self.userIDs = userIDs
        self.origins = origins
        self.playbookID = playbookID
        self.parentSessionID = parentSessionID
    }

    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "first", value: String(first))]
        if let after { items.append(URLQueryItem(name: "after", value: after)) }
        if let tags { items += tags.map { URLQueryItem(name: "tags", value: $0) } }
        if let repoNames { items += repoNames.map { URLQueryItem(name: "repo_names", value: $0) } }
        if let userIDs { items += userIDs.map { URLQueryItem(name: "user_ids", value: $0) } }
        if let origins { items += origins.map { URLQueryItem(name: "origins", value: $0.rawValue) } }
        if let playbookID { items.append(URLQueryItem(name: "playbook_id", value: playbookID)) }
        if let parentSessionID { items.append(URLQueryItem(name: "parent_session_id", value: parentSessionID)) }
        if let isArchived { items.append(URLQueryItem(name: "is_archived", value: isArchived ? "true" : "false")) }
        if let createdAfter { items.append(.epoch("created_after", createdAfter)) }
        if let createdBefore { items.append(.epoch("created_before", createdBefore)) }
        if let updatedAfter { items.append(.epoch("updated_after", updatedAfter)) }
        if let updatedBefore { items.append(.epoch("updated_before", updatedBefore)) }
        return items
    }
}

extension URLQueryItem {
    static func epoch(_ name: String, _ date: Date) -> URLQueryItem {
        URLQueryItem(name: name, value: String(Int(date.timeIntervalSince1970)))
    }
}
