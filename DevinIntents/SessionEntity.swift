import AppIntents
import DevinKit
import Foundation

/// A Devin session as Siri and Shortcuts see it. Built from `SessionSnapshot.Entry` so the picker
/// works offline and instantly; `Session` values from the API go through the same entry.
struct SessionEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Devin Session")
    static let defaultQuery = SessionEntityQuery()

    let id: String
    let title: String
    let status: String
    let needsYou: Bool

    init(_ entry: SessionSnapshot.Entry) {
        id = entry.id
        title = entry.title
        status = entry.statusSummary
        needsYou = entry.bucket == .needsYou
    }

    init(_ session: Session) {
        self.init(SessionSnapshot.Entry(session))
    }

    /// `devinmobile://session/<id>`; "Open URL" in Shortcuts lands on the session in the app.
    var link: URL { DeepLink.session(id: id).url }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(status)",
                              image: .init(systemName: needsYou ? "exclamationmark.bubble" : "bubble.left"))
    }
}

/// Resolves sessions from the last `SessionSnapshot` (fast, works offline) and falls back to the
/// API when the snapshot is missing, stale, or doesn't know an id a saved shortcut still refers to.
struct SessionEntityQuery: EntityQuery, EntityStringQuery {
    /// A snapshot older than this is refreshed from the API before Siri offers choices.
    static let staleAfter: TimeInterval = 10 * 60

    func entities(for identifiers: [String]) async throws -> [SessionEntity] {
        let snapshot = SessionSnapshot.load()
        var found: [SessionEntity] = []
        for id in identifiers {
            if let entry = snapshot?.entry(id: id) {
                found.append(SessionEntity(entry))
            } else if let session = try? await SignedInDevin.current().session(id: id) {
                found.append(SessionEntity(session))
            }
        }
        return found
    }

    func suggestedEntities() async throws -> [SessionEntity] {
        try await freshSnapshot().entries.map(SessionEntity.init)
    }

    func entities(matching string: String) async throws -> [SessionEntity] {
        try await freshSnapshot().entries(matching: string).map(SessionEntity.init)
    }

    /// The saved snapshot when recent; otherwise page 1 from the API, keeping the saved one if the
    /// network fails. Throws only when there is nothing at all to offer (signed out, first run offline).
    private func freshSnapshot() async throws -> SessionSnapshot {
        let saved = SessionSnapshot.load()
        if let saved, Date.now.timeIntervalSince(saved.capturedAt) < Self.staleAfter {
            return saved
        }
        do {
            return try await SignedInDevin.current().refreshSnapshot()
        } catch {
            if let saved { return saved }
            throw error
        }
    }
}
