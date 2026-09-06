import Foundation

public enum KnowledgeAccessType: String, Codable, Sendable, CaseIterable {
    case org, enterprise
}

/// Mirrors `KnowledgeNoteResponse`: one knowledge note Devin can be given at session start
/// (`NewSessionRequest.knowledgeIDs`). `folderPath` is `""` for notes at the root.
public struct KnowledgeNote: Codable, Identifiable, Hashable, Sendable {
    public let noteID: String
    public let folderID: String?
    public let folderPath: String
    public let name: String
    public let body: String
    public let trigger: String
    public let isEnabled: Bool
    /// nil when the server reports an access type this build doesn't know.
    public let accessType: KnowledgeAccessType?
    public let pinnedRepo: String?
    public let createdAt: Date?
    public let updatedAt: Date?

    public var id: String { noteID }

    enum CodingKeys: String, CodingKey {
        case noteID = "note_id"
        case folderID = "folder_id"
        case folderPath = "folder_path"
        case name, body, trigger
        case isEnabled = "is_enabled"
        case accessType = "access_type"
        case pinnedRepo = "pinned_repo"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        noteID: String,
        folderID: String? = nil,
        folderPath: String = "",
        name: String,
        body: String = "",
        trigger: String = "",
        isEnabled: Bool = true,
        accessType: KnowledgeAccessType? = .org,
        pinnedRepo: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.noteID = noteID
        self.folderID = folderID
        self.folderPath = folderPath
        self.name = name
        self.body = body
        self.trigger = trigger
        self.isEnabled = isEnabled
        self.accessType = accessType
        self.pinnedRepo = pinnedRepo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        noteID = try c.decode(String.self, forKey: .noteID)
        folderID = try c.decodeIfPresent(String.self, forKey: .folderID)
        folderPath = try c.decodeIfPresent(String.self, forKey: .folderPath) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        trigger = try c.decodeIfPresent(String.self, forKey: .trigger) ?? ""
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        accessType = try? c.decodeIfPresent(KnowledgeAccessType.self, forKey: .accessType)
        pinnedRepo = try c.decodeIfPresent(String.self, forKey: .pinnedRepo)
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? noteID : trimmed
    }

    /// Folder shown as a group header in pickers; root notes share `KnowledgeNote.rootFolderName`.
    public var folderDisplayName: String {
        folderPath.isEmpty ? Self.rootFolderName : folderPath
    }

    public static let rootFolderName = "General"

    /// Case- and diacritic-insensitive match against name, trigger, folder path and pinned repo.
    public func matches(_ searchText: String) -> Bool {
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return [name, trigger, folderPath, pinnedRepo ?? ""].contains {
            $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

/// Mirrors `FolderSummary` in `GET …/knowledge/folders`.
public struct KnowledgeFolder: Codable, Identifiable, Hashable, Sendable {
    public let folderID: String
    public let name: String
    public let parentFolderID: String?
    public let path: String
    public let noteCount: Int

    public var id: String { folderID }

    enum CodingKeys: String, CodingKey {
        case folderID = "folder_id"
        case name
        case parentFolderID = "parent_folder_id"
        case path
        case noteCount = "note_count"
    }

    public init(folderID: String, name: String, parentFolderID: String? = nil, path: String, noteCount: Int = 0) {
        self.folderID = folderID
        self.name = name
        self.parentFolderID = parentFolderID
        self.path = path
        self.noteCount = noteCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        folderID = try c.decode(String.self, forKey: .folderID)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        parentFolderID = try c.decodeIfPresent(String.self, forKey: .parentFolderID)
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? name
        noteCount = try c.decodeIfPresent(Int.self, forKey: .noteCount) ?? 0
    }
}

/// Mirrors `FolderTreeResponse`. Folders are flat with `parentFolderID` links; `path` is already joined.
public struct KnowledgeFolderTree: Codable, Hashable, Sendable {
    public let folders: [KnowledgeFolder]
    public let rootNoteCount: Int

    enum CodingKeys: String, CodingKey {
        case folders
        case rootNoteCount = "root_note_count"
    }

    public init(folders: [KnowledgeFolder], rootNoteCount: Int = 0) {
        self.folders = folders
        self.rootNoteCount = rootNoteCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        folders = try c.decodeIfPresent([KnowledgeFolder].self, forKey: .folders) ?? []
        rootNoteCount = try c.decodeIfPresent(Int.self, forKey: .rootNoteCount) ?? 0
    }

    public var totalNoteCount: Int { rootNoteCount + folders.reduce(0) { $0 + $1.noteCount } }
}
