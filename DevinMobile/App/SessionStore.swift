import Foundation
import Observation
import DevinKit

/// Source of truth for the session list. Polls while the inbox is on screen.
@Observable
@MainActor
final class SessionStore {
    let client: DevinClient
    let orgID: String

    static let pageSize = 50

    private(set) var sessions: [Session] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var lastRefreshed: Date?
    var error: DevinError?

    /// Cursor of the deepest page loaded so far; nil once the list is exhausted (or before first load).
    private(set) var nextCursor: String?
    private var pagesLoaded = 0

    var hasMorePages: Bool { nextCursor != nil }

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(client: DevinClient, orgID: String) {
        self.client = client
        self.orgID = orgID
    }

    // MARK: Derived

    var grouped: [(bucket: Session.Bucket, sessions: [Session])] {
        let byBucket = Dictionary(grouping: sessions, by: \.bucket)
        return Session.Bucket.allCases.compactMap { bucket in
            guard let items = byBucket[bucket], !items.isEmpty else { return nil }
            return (bucket, items.sorted { $0.updatedAt > $1.updatedAt })
        }
    }

    var needsAttentionCount: Int { sessions.filter(\.needsAttention).count }

    func session(id: String) -> Session? {
        sessions.first { $0.id == id }
    }

    func filtered(by query: String) -> [(bucket: Session.Bucket, sessions: [Session])] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return grouped }
        return grouped.compactMap { group in
            let matches = group.sessions.filter {
                $0.displayTitle.lowercased().contains(needle)
                    || $0.tags.contains { $0.lowercased().contains(needle) }
                    || $0.sessionID.lowercased().contains(needle)
            }
            return matches.isEmpty ? nil : (group.bucket, matches)
        }
    }

    // MARK: Loading

    private func query(after cursor: String? = nil) -> SessionQuery {
        SessionQuery(first: Self.pageSize, after: cursor, isArchived: false)
    }

    /// Re-fetches only the first page. Rows on deeper pages stay put and are upserted by ID when
    /// they resurface; the cursor for the next page is left alone once anything past page 1 is loaded.
    func refresh() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await client.sessions(org: orgID, query: query())
            sessions = sessions.merging(page.items, pruneMissing: pagesLoaded <= 1)
            if pagesLoaded <= 1 {
                pagesLoaded = 1
                nextCursor = page.hasNextPage ? page.endCursor : nil
            }
            lastRefreshed = .now
            error = nil
        } catch let e as DevinError {
            error = e
        } catch {
            self.error = .transport(error.localizedDescription)
        }
    }

    /// Appends the page after `nextCursor`. No-op while a load is in flight or the list is exhausted.
    func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await client.sessions(org: orgID, query: query(after: cursor))
            guard nextCursor == cursor else { return }
            sessions = sessions.merging(page.items)
            pagesLoaded += 1
            nextCursor = page.hasNextPage ? page.endCursor : nil
            error = nil
        } catch let e as DevinError {
            error = e
        } catch {
            self.error = .transport(error.localizedDescription)
        }
    }

    func startPolling(every interval: Duration = .seconds(10)) {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Mutations

    func apply(_ session: Session) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
    }

    func remove(id: String) {
        sessions.removeAll { $0.id == id }
    }

    func create(_ request: NewSessionRequest) async throws -> Session {
        let session = try await client.createSession(org: orgID, request)
        apply(session)
        return session
    }

    func archive(_ session: Session) async throws {
        _ = try await client.archive(org: orgID, id: session.id)
        remove(id: session.id)
    }

    func terminate(_ session: Session) async throws {
        _ = try await client.terminate(org: orgID, id: session.id, archive: false)
        remove(id: session.id)
    }

    func reload(id: String) async throws -> Session {
        let session = try await client.session(org: orgID, id: id)
        apply(session)
        return session
    }
}
