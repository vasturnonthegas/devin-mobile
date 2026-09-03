import Foundation

/// Cursor-paginated response envelope used by all v3 list endpoints.
public struct Page<Item: Codable & Sendable>: Codable, Sendable {
    public let items: [Item]
    public let endCursor: String?
    public let hasNextPage: Bool
    public let total: Int?

    enum CodingKeys: String, CodingKey {
        case items
        case endCursor = "end_cursor"
        case hasNextPage = "has_next_page"
        case total
    }

    public init(items: [Item], endCursor: String? = nil, hasNextPage: Bool = false, total: Int? = nil) {
        self.items = items
        self.endCursor = endCursor
        self.hasNextPage = hasNextPage
        self.total = total
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([Item].self, forKey: .items)
        endCursor = try c.decodeIfPresent(String.self, forKey: .endCursor)
        hasNextPage = try c.decodeIfPresent(Bool.self, forKey: .hasNextPage) ?? false
        total = try c.decodeIfPresent(Int.self, forKey: .total)
    }
}
