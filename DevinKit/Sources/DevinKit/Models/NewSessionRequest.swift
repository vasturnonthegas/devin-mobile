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

    enum CodingKeys: String, CodingKey {
        case prompt, repos, tags, title, resumable
        case playbookID = "playbook_id"
        case devinMode = "devin_mode"
        case maxACULimit = "max_acu_limit"
        case attachmentURLs = "attachment_urls"
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
        resumable: Bool? = nil
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
    }
}

/// Filters for `GET /v3/organizations/{org_id}/sessions`.
public struct SessionQuery: Hashable, Sendable {
    public var first: Int
    public var after: String?
    public var tags: [String]?
    public var isArchived: Bool?
    public var updatedAfter: Date?
    public var parentSessionID: String?

    public init(first: Int = 50, after: String? = nil, tags: [String]? = nil, isArchived: Bool? = false, updatedAfter: Date? = nil, parentSessionID: String? = nil) {
        self.first = first
        self.after = after
        self.tags = tags
        self.isArchived = isArchived
        self.updatedAfter = updatedAfter
        self.parentSessionID = parentSessionID
    }

    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "first", value: String(first))]
        if let after { items.append(URLQueryItem(name: "after", value: after)) }
        if let tags { items += tags.map { URLQueryItem(name: "tags", value: $0) } }
        if let isArchived { items.append(URLQueryItem(name: "is_archived", value: isArchived ? "true" : "false")) }
        if let updatedAfter { items.append(URLQueryItem(name: "updated_after", value: String(Int(updatedAfter.timeIntervalSince1970)))) }
        if let parentSessionID { items.append(URLQueryItem(name: "parent_session_id", value: parentSessionID)) }
        return items
    }
}
