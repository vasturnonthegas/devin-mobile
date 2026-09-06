import Foundation

public enum SecretType: String, Codable, Sendable, CaseIterable {
    case cookie
    case keyValue = "key-value"
    case totp

    public var displayName: String {
        switch self {
        case .cookie: "Cookie"
        case .keyValue: "Key / value"
        case .totp: "TOTP"
        }
    }
}

public enum SecretAccessType: String, Codable, Sendable, CaseIterable {
    case org, personal
}

/// Mirrors `SecretResponse`: metadata about a stored secret Devin can be given at session start
/// (`NewSessionRequest.secretIDs`). The API never returns secret values and this type has no
/// field for one — anything shown to the user comes from `key`/`note`, never from the secret itself.
public struct OrgSecret: Codable, Identifiable, Hashable, Sendable {
    public let secretID: String
    /// Environment-variable style name for `key-value` secrets; may be nil for cookies/TOTP.
    public let key: String?
    public let note: String?
    public let isSensitive: Bool
    public let createdBy: String?
    public let createdAt: Date?
    /// nil when the server reports a type this build doesn't know; see `rawSecretType`.
    public let secretType: SecretType?
    public let rawSecretType: String?
    public let accessType: SecretAccessType?
    public let updatedAt: Date?
    public let updatedBy: String?

    public var id: String { secretID }

    enum CodingKeys: String, CodingKey {
        case secretID = "secret_id"
        case key, note
        case isSensitive = "is_sensitive"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case secretType = "secret_type"
        case accessType = "access_type"
        case updatedAt = "updated_at"
        case updatedBy = "updated_by"
    }

    public init(
        secretID: String,
        key: String? = nil,
        note: String? = nil,
        isSensitive: Bool = true,
        createdBy: String? = nil,
        createdAt: Date? = nil,
        secretType: SecretType? = .keyValue,
        accessType: SecretAccessType? = .org,
        updatedAt: Date? = nil,
        updatedBy: String? = nil
    ) {
        self.secretID = secretID
        self.key = key
        self.note = note
        self.isSensitive = isSensitive
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.secretType = secretType
        self.rawSecretType = secretType?.rawValue
        self.accessType = accessType
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        secretID = try c.decode(String.self, forKey: .secretID)
        key = try c.decodeIfPresent(String.self, forKey: .key)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        isSensitive = try c.decodeIfPresent(Bool.self, forKey: .isSensitive) ?? true
        createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy)
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        rawSecretType = try c.decodeIfPresent(String.self, forKey: .secretType)
        secretType = rawSecretType.flatMap(SecretType.init(rawValue:))
        accessType = try? c.decodeIfPresent(SecretAccessType.self, forKey: .accessType)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        updatedBy = try c.decodeIfPresent(String.self, forKey: .updatedBy)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(secretID, forKey: .secretID)
        try c.encode(key, forKey: .key)
        try c.encode(note, forKey: .note)
        try c.encode(isSensitive, forKey: .isSensitive)
        try c.encodeIfPresent(createdBy, forKey: .createdBy)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(rawSecretType, forKey: .secretType)
        try c.encodeIfPresent(accessType, forKey: .accessType)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(updatedBy, forKey: .updatedBy)
    }

    /// `key`, else `note`, else the ID — never a value.
    public var displayName: String {
        if let key = key?.trimmingCharacters(in: .whitespaces), !key.isEmpty { return key }
        if let note = note?.trimmingCharacters(in: .whitespaces), !note.isEmpty { return note }
        return secretID
    }

    /// Secondary line for pickers: the note when the key is the title, plus the type.
    public var detailSummary: String? {
        var parts: [String] = []
        if displayName == key, let note = note?.trimmingCharacters(in: .whitespaces), !note.isEmpty { parts.append(note) }
        if let type = typeSummary { parts.append(type) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public var typeSummary: String? {
        secretType?.displayName ?? rawSecretType?.replacingOccurrences(of: "-", with: " ").capitalized
    }

    /// Case- and diacritic-insensitive match against key, note and type.
    public func matches(_ searchText: String) -> Bool {
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return [key ?? "", note ?? "", typeSummary ?? ""].contains {
            $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
