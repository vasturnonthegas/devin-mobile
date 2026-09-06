import Foundation

/// Response of `POST /v3/organizations/{org_id}/attachments`. The `url` is what
/// `attachment_urls` expects on message and session creation.
public struct UploadedAttachment: Codable, Identifiable, Hashable, Sendable {
    public let attachmentID: String
    public let name: String
    public let url: URL

    public var id: String { attachmentID }

    enum CodingKeys: String, CodingKey {
        case attachmentID = "attachment_id"
        case name, url
    }

    public init(attachmentID: String, name: String, url: URL) {
        self.attachmentID = attachmentID
        self.name = name
        self.url = url
    }
}
