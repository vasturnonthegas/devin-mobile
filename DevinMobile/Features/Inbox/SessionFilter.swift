import Foundation
import DevinKit

/// The inbox's server-side filters. Lives on `SessionStore`, so it survives navigation
/// and sheet dismissal but resets with the app (nothing is persisted to disk).
struct SessionFilter: Equatable, Sendable {
    var repoNames: [String] = []
    var userIDs: [String] = []
    var tags: [String] = []
    var origins: Set<SessionOrigin> = []
    var playbookID: String?
    /// Display-only companion to `playbookID`; the API filters by ID.
    var playbookTitle: String?
    var createdAfter: Date?
    var createdBefore: Date?
    var updatedAfter: Date?
    var updatedBefore: Date?

    var isEmpty: Bool { chips.isEmpty }

    func query(first: Int) -> SessionQuery {
        SessionQuery(
            first: first,
            tags: tags.isEmpty ? nil : tags,
            isArchived: false,
            updatedAfter: updatedAfter,
            updatedBefore: updatedBefore,
            createdAfter: createdAfter,
            createdBefore: createdBefore,
            repoNames: repoNames.isEmpty ? nil : repoNames,
            userIDs: userIDs.isEmpty ? nil : userIDs,
            origins: origins.isEmpty ? nil : origins.sorted { $0.rawValue < $1.rawValue },
            playbookID: playbookID
        )
    }

    // MARK: Chips

    /// One removable chip per active value, in the order the bar shows them.
    enum Chip: Hashable, Identifiable {
        case repo(String)
        case user(String)
        case tag(String)
        case origin(SessionOrigin)
        case playbook
        case createdAfter
        case createdBefore
        case updatedAfter
        case updatedBefore

        var id: Self { self }
    }

    var chips: [Chip] {
        var chips: [Chip] = []
        chips += repoNames.map(Chip.repo)
        chips += tags.map(Chip.tag)
        chips += origins.sorted { $0.rawValue < $1.rawValue }.map(Chip.origin)
        if playbookID != nil { chips.append(.playbook) }
        chips += userIDs.map(Chip.user)
        if createdAfter != nil { chips.append(.createdAfter) }
        if createdBefore != nil { chips.append(.createdBefore) }
        if updatedAfter != nil { chips.append(.updatedAfter) }
        if updatedBefore != nil { chips.append(.updatedBefore) }
        return chips
    }

    func label(for chip: Chip) -> String {
        switch chip {
        case .repo(let name): name
        case .user(let id): "By \(id)"
        case .tag(let tag): "#\(tag)"
        case .origin(let origin): origin.displayName
        case .playbook: playbookTitle ?? playbookID ?? ""
        case .createdAfter: "Created after \(Self.short(createdAfter))"
        case .createdBefore: "Created before \(Self.short(createdBefore))"
        case .updatedAfter: "Updated after \(Self.short(updatedAfter))"
        case .updatedBefore: "Updated before \(Self.short(updatedBefore))"
        }
    }

    mutating func remove(_ chip: Chip) {
        switch chip {
        case .repo(let name): repoNames.removeAll { $0 == name }
        case .user(let id): userIDs.removeAll { $0 == id }
        case .tag(let tag): tags.removeAll { $0 == tag }
        case .origin(let origin): origins.remove(origin)
        case .playbook:
            playbookID = nil
            playbookTitle = nil
        case .createdAfter: createdAfter = nil
        case .createdBefore: createdBefore = nil
        case .updatedAfter: updatedAfter = nil
        case .updatedBefore: updatedBefore = nil
        }
    }

    private static func short(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? ""
    }

    // MARK: Input normalisation

    /// The API expects `owner/repo`; users paste URLs and `github.com/owner/repo`.
    static func normalizeRepoName(_ raw: String) -> String {
        let path = RecentRepos.normalize(raw)
        let parts = path.split(separator: "/")
        if parts.count >= 3, parts[0].contains(".") {
            return parts.dropFirst().joined(separator: "/")
        }
        return path
    }

    /// Splits comma/whitespace separated input into unique, non-empty tokens.
    static func tokens(_ raw: String) -> [String] {
        var seen: Set<String> = []
        return raw
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
            .filter { seen.insert($0).inserted }
    }
}
