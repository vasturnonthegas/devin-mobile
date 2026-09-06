import Foundation

// MARK: Devin Review (pr-reviews)

public extension DevinClient {
    /// Latest review of `prURL` at `commitSHA` (defaults to the PR's current head, resolved server-side).
    /// nil when no review exists for that commit — the API reports that as 404.
    func prReview(org: String, prURL: URL, commitSHA: String? = nil) async throws -> PRReview? {
        var items = [URLQueryItem(name: "pr_url", value: prURL.absoluteString)]
        if let commitSHA { items.append(URLQueryItem(name: "commit_sha", value: commitSHA)) }
        do {
            return try await request(.get, "/v3/organizations/\(org)/pr-reviews", query: items)
        } catch DevinError.notFound(_) {
            return nil
        }
    }

    /// Queues a Devin Review of the PR's current head commit. The result starts `pending`;
    /// follow it with `watchPRReview` using the returned `commitSHA`.
    func requestPRReview(org: String, prURL: URL) async throws -> PRReview {
        try await request(.post, "/v3/organizations/\(org)/pr-reviews", body: PRReviewRequest(prURL: prURL))
    }

    /// Polls `prReview` every `interval`, yielding each result, and finishes once the review is
    /// finished or `maxPolls` is exhausted. A 404 in between is treated as "not visible yet".
    /// Cancelling the consuming task stops the polling.
    func watchPRReview(
        org: String,
        prURL: URL,
        commitSHA: String?,
        interval: Duration = .seconds(5),
        maxPolls: Int = 120,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) -> AsyncThrowingStream<PRReview, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for _ in 0..<maxPolls {
                        try await sleep(interval)
                        guard let review = try await prReview(org: org, prURL: prURL, commitSHA: commitSHA) else { continue }
                        continuation.yield(review)
                        if review.isFinished { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
