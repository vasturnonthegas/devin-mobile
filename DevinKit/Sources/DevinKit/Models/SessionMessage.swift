import Foundation

public enum MessageSource: String, Codable, Sendable {
    case devin, user
}

public struct SessionMessage: Codable, Identifiable, Hashable, Sendable {
    public let eventID: String
    public let source: MessageSource
    public let message: String
    public let createdAt: Date

    public var id: String { eventID }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case source, message
        case createdAt = "created_at"
    }

    public init(eventID: String, source: MessageSource, message: String, createdAt: Date) {
        self.eventID = eventID
        self.source = source
        self.message = message
        self.createdAt = createdAt
    }
}

public struct SessionAttachment: Codable, Identifiable, Hashable, Sendable {
    public let attachmentID: String
    public let name: String
    public let source: MessageSource
    public let url: URL
    public let contentType: String?

    public var id: String { attachmentID }

    enum CodingKeys: String, CodingKey {
        case attachmentID = "attachment_id"
        case name, source, url
        case contentType = "content_type"
    }
}
