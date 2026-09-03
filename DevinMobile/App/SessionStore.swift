import Foundation
import Observation
import DevinKit

/// Source of truth for the session list. Polls while the inbox is on screen.
@Observable
@MainActor
final class SessionStore {
    let client: DevinClient
    let orgID: String

    private(set) var sessions: [Session] = []
    private(set) var isLoading = false
    private(set) var lastRefreshed: Date?
    var error: DevinError?

    /// Changing the filter drops the current list and reloads; a superseded in-flight refresh is ignored.
    var filter = SessionFilter() {
        didSet {
            guard filter != oldValue else { return }
            sessions = []
            Task { await refresh() }
        }
    }

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0

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

    /// Latest request wins: results from a refresh that was superseded (filter change, pull-to-refresh) are dropped.
    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        isLoading = true
        let result: Result<Page<Session>, DevinError>
        do {
            result = .success(try await client.sessions(org: orgID, query: filter.query(first: 100)))
        } catch let e as DevinError {
            result = .failure(e)
        } catch {
            result = .failure(.transport(error.localizedDescription))
        }
        guard generation == refreshGeneration else { return }
        isLoading = false
        switch result {
        case .success(let page):
            sessions = page.items
            lastRefreshed = .now
            error = nil
        case .failure(let e):
            error = e
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
