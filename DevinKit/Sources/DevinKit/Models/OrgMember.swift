import Foundation

/// A user with membership in the organization (`User` in the v3 OpenAPI schema).
/// Role assignments are not decoded; the app only needs to put a name on a `user_id`.
public struct OrgMember: Codable, Identifiable, Hashable, Sendable {
    public let userID: String
    public let email: String?
    public let name: String?

    public var id: String { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case email, name
    }

    public init(userID: String, email: String? = nil, name: String? = nil) {
        self.userID = userID
        self.email = email
        self.name = name
    }

    public var displayName: String {
        if let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
        if let email, !email.isEmpty { return email }
        return userID
    }

    /// One or two uppercase letters for an avatar placeholder: "Taj Vasudeva" → "TV", "taj@x.dev" → "T".
    public var initials: String {
        let source = displayName
        let words = source
            .split(whereSeparator: { $0.isWhitespace || $0 == "@" })
            .prefix(source == email ? 1 : 2)
        let letters = words.compactMap { $0.first(where: \.isLetter) }
        guard !letters.isEmpty else { return "?" }
        return String(letters).uppercased()
    }
}
