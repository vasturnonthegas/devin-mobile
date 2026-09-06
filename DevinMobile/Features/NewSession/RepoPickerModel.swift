import Foundation
import Observation
import DevinKit

/// Drives `RepoPickerView`: the repositories API is the source of truth, searched server-side
/// (`filter_name`) after a short debounce and paged by cursor. `RecentRepos` only pins rows on top.
/// A 403 (or 404 on an org without git connections) is sticky for the picker's lifetime: the list
/// section is hidden and the user falls back to recents + typing a path.
@Observable
@MainActor
final class RepoPickerModel {
    static let pageSize = 50
    static let debounce: Duration = .milliseconds(300)
    /// Rows this close to the end of the loaded list trigger a prefetch of the next page.
    static let prefetchWindow = 10

    private let client: DevinClient
    private let orgID: String

    var search = "" {
        didSet { if search != oldValue { scheduleSearch() } }
    }

    private(set) var repos: [Repository] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isUnavailable = false
    private(set) var error: DevinError?
    /// Cursor for the page after the last one loaded; nil when exhausted or nothing loaded yet.
    private(set) var nextCursor: String?
    private(set) var hasLoaded = false

    private var searchTask: Task<Void, Never>?
    private var generation = 0

    init(client: DevinClient, orgID: String) {
        self.client = client
        self.orgID = orgID
    }

    var hasMore: Bool { nextCursor != nil }

    /// Repositories whose `fullPath` is one of `paths`, for enriching pinned recents with API metadata.
    func repository(for path: String) -> Repository? {
        repos.first { $0.fullPath == path || $0.repoPath == path }
    }

    func start() async {
        guard !hasLoaded, !isLoading else { return }
        await reload()
    }

    func loadMoreIfNeeded(current repo: Repository) {
        guard let index = repos.firstIndex(of: repo), index >= repos.count - Self.prefetchWindow else { return }
        Task { await loadMore() }
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let generation = self.generation
        do {
            let page = try await client.repositories(org: orgID, query: query(after: cursor))
            guard generation == self.generation, nextCursor == cursor else { return }
            var seen = Set(repos.map(\.id))
            repos += page.items.filter { seen.insert($0.id).inserted }
            nextCursor = page.hasNextPage ? page.endCursor : nil
            error = nil
        } catch {
            guard generation == self.generation else { return }
            self.error = Self.devinError(error)
        }
    }

    func retry() async {
        await reload()
    }

    // MARK: - Private

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    /// Latest request wins: a reload started for a newer search term discards earlier results.
    private func reload() async {
        guard !isUnavailable else { return }
        generation += 1
        let generation = self.generation
        isLoading = true
        do {
            let page = try await client.repositories(org: orgID, query: query(after: nil))
            guard generation == self.generation else { return }
            repos = page.items
            nextCursor = page.hasNextPage ? page.endCursor : nil
            error = nil
            hasLoaded = true
        } catch {
            guard generation == self.generation else { return }
            let devinError = Self.devinError(error)
            switch devinError {
            case .forbidden, .notFound:
                isUnavailable = true
                repos = []
                nextCursor = nil
            default:
                self.error = devinError
            }
            hasLoaded = true
        }
        isLoading = false
    }

    private func query(after cursor: String?) -> RepositoryQuery {
        RepositoryQuery(first: Self.pageSize, after: cursor, filterName: search)
    }

    private static func devinError(_ error: Error) -> DevinError {
        (error as? DevinError) ?? .transport(error.localizedDescription)
    }
}
