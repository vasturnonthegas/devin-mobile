import Foundation

public struct Playbook: Codable, Identifiable, Hashable, Sendable {
    public let playbookID: String
    public let title: String
    public let body: String
    public let macro: String?

    public var id: String { playbookID }

    enum CodingKeys: String, CodingKey {
        case playbookID = "playbook_id"
        case title, body, macro
    }

    public init(playbookID: String, title: String, body: String = "", macro: String? = nil) {
        self.playbookID = playbookID
        self.title = title
        self.body = body
        self.macro = macro
    }
}
