import Foundation
import Observation
import DevinKit

/// Devin Review state for one pull request. Loads the latest review on appearance, keeps
/// polling while it is in progress, and lets the user queue a new one. A 403 hides the
/// feature for the rest of the model's life instead of surfacing an error.
@Observable
@MainActor
final class PRReviewModel {
    let store: SessionStore
    let prURL: URL

    private(set) var review: PRReview?
    private(set) var hasLoaded = false
    private(set) var isTriggering = false
    private(set) var isForbidden = false
    private(set) var isPolling = false
    var error: String?

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(store: SessionStore, prURL: URL) {
        self.store = store
        self.prURL = prURL
    }

    var canTrigger: Bool { hasLoaded && !isForbidden && !isTriggering && !isPolling }

    func load() async {
        do {
            review = try await store.client.latestPRReview(org: store.orgID, prURL: prURL)
            error = nil
            hasLoaded = true
            if let review, !review.isFinished { startPolling(commitSHA: review.commitSHA) }
        } catch {
            hasLoaded = true
            handle(error)
        }
    }

    func trigger() async {
        guard canTrigger else { return }
        isTriggering = true
        defer { isTriggering = false }
        do {
            let queued = try await store.client.requestPRReview(org: store.orgID, prURL: prURL)
            review = queued
            error = nil
            startPolling(commitSHA: queued.commitSHA)
        } catch {
            handle(error)
        }
    }

    /// Follows one review (pinned to its commit) until it reaches a terminal status.
    private func startPolling(commitSHA: String) {
        stopPolling()
        isPolling = true
        pollTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await snapshot in store.client.pollPRReview(org: store.orgID, prURL: prURL, commitSHA: commitSHA) {
                    review = snapshot
                }
            } catch is CancellationError {
            } catch {
                handle(error)
            }
            if !Task.isCancelled {
                pollTask = nil
                isPolling = false
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
    }

    private func handle(_ error: Error) {
        if case DevinError.forbidden = error {
            isForbidden = true
            self.error = nil
        } else {
            self.error = error.localizedDescription
        }
    }
}
