import Foundation

/// What the share extension hands to the app: the share-sheet payload already mapped onto the New
/// Session form (prompt, `repos`, attachments). It is parked in the App Group — JSON in `defaults`,
/// attachment bytes as files in `directory` — until the app is foregrounded and signed in; the app
/// then uploads the files through the regular attachment path and removes the draft.
public struct SharedDraft: Codable, Hashable, Sendable {
    public struct Attachment: Codable, Hashable, Sendable, Identifiable {
        /// File name inside the draft directory; random so two drafts never collide.
        public let id: String
        /// Name the upload is given (`photo-20250101-101010.jpg`).
        public let filename: String
        public let mime: String
        public let byteCount: Int

        public var isImage: Bool { mime.hasPrefix("image/") }

        public init(id: String, filename: String, mime: String, byteCount: Int) {
            self.id = id
            self.filename = filename
            self.mime = mime
            self.byteCount = byteCount
        }

        public func fileURL(in directory: URL) -> URL {
            directory.appendingPathComponent(id, isDirectory: false)
        }

        /// Writes `data` into `directory` (created on demand) and describes it.
        public static func write(_ data: Data, filename: String, mime: String, to directory: URL) throws -> Attachment {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let ext = (filename as NSString).pathExtension
            let id = UUID().uuidString + (ext.isEmpty ? "" : "." + ext)
            let attachment = Attachment(id: id, filename: filename, mime: mime, byteCount: data.count)
            try data.write(to: attachment.fileURL(in: directory), options: .atomic)
            return attachment
        }

        public func data(in directory: URL) throws -> Data {
            try Data(contentsOf: fileURL(in: directory))
        }
    }

    public var prompt: String
    /// Host-prefixed repository paths (`github.com/owner/repo`), like `NewSessionRequest.repos`.
    public var repos: [String]
    public var attachments: [Attachment]
    public let createdAt: Date

    /// Mirrors the composer's client-side limits; the API's own limits still win.
    public static let maxAttachments = 5
    public static let maxAttachmentBytes = 25 * 1024 * 1024
    /// A draft nobody came back for is dropped rather than popping up days later.
    public static let maxAge: TimeInterval = 24 * 60 * 60

    public init(prompt: String = "", repos: [String] = [], attachments: [Attachment] = [], createdAt: Date = .now) {
        self.prompt = prompt
        self.repos = repos
        self.attachments = attachments
        self.createdAt = createdAt
    }

    public var isEmpty: Bool { prompt.isEmpty && repos.isEmpty && attachments.isEmpty }

    /// Maps the raw share-sheet items onto the form:
    /// - a GitHub repo / PR / issue URL fills `repos`; only the repo's own URL is left out of the
    ///   prompt (a PR or issue link is what the user wants Devin to look at, so it stays);
    /// - any other URL and the shared text go into the prompt, text first, each once;
    /// - GitHub links embedded in the text also fill `repos`.
    public static func compose(text: String? = nil, urls: [URL] = [], attachments: [Attachment] = [], createdAt: Date = .now) -> SharedDraft {
        let text = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var promptParts: [String] = text.isEmpty ? [] : [text]
        var repos: [String] = []

        func remember(_ link: GitHubLink) {
            if !repos.contains(link.repoPath) { repos.append(link.repoPath) }
        }

        for url in urls {
            let link = GitHubLink(url: url)
            if let link { remember(link) }
            let raw = url.absoluteString
            let alreadyInPrompt = promptParts.contains { $0.contains(raw) }
            if link?.kind != .repository, !alreadyInPrompt {
                promptParts.append(raw)
            }
        }
        GitHubLink.links(in: text).forEach(remember)

        return SharedDraft(
            prompt: promptParts.joined(separator: "\n\n"),
            repos: repos,
            attachments: attachments,
            createdAt: createdAt
        )
    }

    // MARK: Persistence

    static let defaultsKey = "pendingSharedDraft"
    static let directoryName = "SharedDraft"

    /// Where attachment bytes live: a folder in the App Group container, or (without the
    /// entitlement) in the caller's own caches, where only the same process can read them back.
    public static func directory(in container: URL? = AppGroup.containerURL) -> URL {
        let base = container ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// The pending draft, if one exists and is younger than `maxAge`. Stale drafts are removed.
    public static func load(from defaults: UserDefaults = AppGroup.defaults, directory: URL = directory(), now: Date = .now) -> SharedDraft? {
        guard let data = defaults.data(forKey: defaultsKey),
              let draft = try? decoder.decode(SharedDraft.self, from: data)
        else { return nil }
        guard now.timeIntervalSince(draft.createdAt) < maxAge else {
            clear(in: defaults, directory: directory)
            return nil
        }
        return draft
    }

    /// Replaces any pending draft. Attachment files must already be in `directory`
    /// (`Attachment.write`); files that belong to no attachment of this draft are deleted.
    public func save(to defaults: UserDefaults = AppGroup.defaults, directory: URL = directory()) throws {
        defaults.set(try Self.encoder.encode(self), forKey: Self.defaultsKey)
        Self.removeFiles(in: directory, except: Set(attachments.map(\.id)))
    }

    public static func clear(in defaults: UserDefaults = AppGroup.defaults, directory: URL = directory()) {
        defaults.removeObject(forKey: defaultsKey)
        removeFiles(in: directory, except: [])
    }

    /// Deletes this draft's files only — for a draft that was staged but never saved (share cancelled),
    /// so a still-pending earlier draft keeps its attachments.
    public func removeAttachmentFiles(in directory: URL = directory()) {
        for attachment in attachments {
            try? FileManager.default.removeItem(at: attachment.fileURL(in: directory))
        }
    }

    private static func removeFiles(in directory: URL, except keep: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where !keep.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}

public extension AppGroup {
    /// The group's shared file container; nil without the App Groups entitlement.
    static var containerURL: URL? {
        #if canImport(Darwin)
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        #else
        return nil
        #endif
    }
}
