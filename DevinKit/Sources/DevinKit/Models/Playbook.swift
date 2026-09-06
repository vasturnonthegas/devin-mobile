import Foundation

public enum PlaybookAccessType: String, Codable, Sendable {
    case enterprise, org

    public var displayName: String {
        switch self {
        case .enterprise: "Enterprise"
        case .org: "Organization"
        }
    }
}

public struct Playbook: Codable, Identifiable, Hashable, Sendable {
    public let playbookID: String
    public let title: String
    public let body: String
    public let macro: String?
    /// nil when the server reports an access type this build doesn't know.
    public let accessType: PlaybookAccessType?
    public let updatedAt: Date?

    public var id: String { playbookID }

    enum CodingKeys: String, CodingKey {
        case playbookID = "playbook_id"
        case title, body, macro
        case accessType = "access_type"
        case updatedAt = "updated_at"
    }

    public init(playbookID: String, title: String, body: String = "", macro: String? = nil,
                accessType: PlaybookAccessType? = nil, updatedAt: Date? = nil) {
        self.playbookID = playbookID
        self.title = title
        self.body = body
        self.macro = macro
        self.accessType = accessType
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playbookID = try c.decode(String.self, forKey: .playbookID)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        macro = try c.decodeIfPresent(String.self, forKey: .macro)
        accessType = try? c.decodeIfPresent(PlaybookAccessType.self, forKey: .accessType)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}
