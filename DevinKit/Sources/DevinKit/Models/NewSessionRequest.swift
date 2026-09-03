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
        playbookID: String? = nil
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
    }

    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "first", value: String(first))]
        if let after { items.append(URLQueryItem(name: "after", value: after)) }
        if let tags { items += tags.map { URLQueryItem(name: "tags", value: $0) } }
        if let repoNames { items += repoNames.map { URLQueryItem(name: "repo_names", value: $0) } }
        if let userIDs { items += userIDs.map { URLQueryItem(name: "user_ids", value: $0) } }
        if let origins { items += origins.map { URLQueryItem(name: "origins", value: $0.rawValue) } }
        if let playbookID { items.append(URLQueryItem(name: "playbook_id", value: playbookID)) }
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
