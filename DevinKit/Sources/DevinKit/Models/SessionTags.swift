import Foundation

/// Mirrors `SessionTagsResponse` / `SessionTagsUpdateRequest` in the Devin v3 OpenAPI schema.
public struct SessionTags: Codable, Hashable, Sendable {
    /// Server-side cap on tags per session (`maxItems` in the spec).
    public static let maxCount = 50

    public var tags: [String]

    public init(tags: [String]) {
        self.tags = tags
    }
}

public extension SessionTags {
    /// Canonical form for user-entered tags: trimmed, leading `#` dropped. Returns nil when nothing is left.
    static func normalize(_ raw: String) -> String? {
        var tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while tag.hasPrefix("#") { tag.removeFirst() }
        tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        return tag.isEmpty ? nil : tag
    }
}
