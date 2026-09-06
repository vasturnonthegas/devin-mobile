import Foundation

extension Session.Bucket: Codable {}

/// Last-known state of the inbox, written by the app after each unfiltered refresh and read by
/// extensions (widget, background refresh) that must not hit the API themselves. Holds only what
/// a glanceable surface needs; never the token or the transcript.
public struct SessionSnapshot: Codable, Hashable, Sendable {
    public struct Entry: Codable, Hashable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let bucket: Session.Bucket
        public let statusSummary: String
        public let updatedAt: Date

        public init(_ session: Session) {
            id = session.id
            title = session.displayTitle
            bucket = session.bucket
            statusSummary = session.statusSummary
            updatedAt = session.updatedAt
        }

        public var deepLink: DeepLink { .session(id: id) }
    }

    public let capturedAt: Date
    /// Ordered like the inbox: by bucket (`needsYou` first), then most recently updated.
    public let entries: [Entry]

    public init(sessions: [Session], capturedAt: Date = .now) {
        self.capturedAt = capturedAt
        self.entries = sessions
            .filter { !$0.isArchived }
            .map(Entry.init)
            .sorted { ($0.bucket, $1.updatedAt) < ($1.bucket, $0.updatedAt) }
    }

    public func entries(in bucket: Session.Bucket) -> [Entry] {
        entries.filter { $0.bucket == bucket }
    }

    public func count(_ bucket: Session.Bucket) -> Int {
        entries.reduce(0) { $0 + ($1.bucket == bucket ? 1 : 0) }
    }

    public var needsYouCount: Int { count(.needsYou) }

    // MARK: Persistence

    static let defaultsKey = "lastSessionSnapshot"

    public static func load(from defaults: UserDefaults = AppGroup.defaults) -> SessionSnapshot? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? Self.decoder.decode(SessionSnapshot.self, from: data)
    }

    public func save(to defaults: UserDefaults = AppGroup.defaults) throws {
        defaults.set(try Self.encoder.encode(self), forKey: Self.defaultsKey)
    }

    public static func clear(in defaults: UserDefaults = AppGroup.defaults) {
        defaults.removeObject(forKey: defaultsKey)
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
