import Foundation

// MARK: Devin Review (pr-reviews)

public extension DevinClient {
    /// Latest review for `prURL`. Without `commitSHA` the server resolves the PR's current head;
    /// throws `DevinError.notFound` when that commit has never been reviewed.
    func prReview(org: String, prURL: URL, commitSHA: String? = nil) async throws -> PRReview {
        var items = [URLQueryItem(name: "pr_url", value: prURL.absoluteString)]
        if let commitSHA { items.append(URLQueryItem(name: "commit_sha", value: commitSHA)) }
        return try await request(.get, "/v3/organizations/\(org)/pr-reviews", query: items)
    }

    /// `prReview` with "no review yet" folded into nil; every other error still throws.
    func latestPRReview(org: String, prURL: URL, commitSHA: String? = nil) async throws -> PRReview? {
        do {
            return try await prReview(org: org, prURL: prURL, commitSHA: commitSHA)
        } catch DevinError.notFound {
            return nil
        }
    }

    /// Queues a Devin Review of the PR's current head commit. The response starts as `pending`.
    func requestPRReview(org: String, prURL: URL) async throws -> PRReview {
        try await request(.post, "/v3/organizations/\(org)/pr-reviews", body: PRReviewCreateRequest(prURL: prURL))
    }

    /// Re-fetches the review every `interval`, yielding each snapshot, until it reaches a terminal
    /// status or `maxPolls` fetches have been made. Pass the `commitSHA` from `requestPRReview` so
    /// the stream follows that review even if the PR head moves. Cancelling the consumer stops polling.
    func pollPRReview(
        org: String,
        prURL: URL,
        commitSHA: String? = nil,
        every interval: Duration = .seconds(5),
        maxPolls: Int = 120
    ) -> AsyncThrowingStream<PRReview, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var polls = 0
                    while !Task.isCancelled {
                        let review = try await prReview(org: org, prURL: prURL, commitSHA: commitSHA)
                        continuation.yield(review)
                        polls += 1
                        if review.isFinished || polls >= maxPolls { break }
                        try await Task.sleep(for: interval)
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
