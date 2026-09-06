import Foundation
import Observation
import DevinKit

/// Devin Review status for one pull request URL. Loads the latest review once, and after a
/// trigger (or when the loaded review is still in progress) follows it with `watchPRReview`
/// until it reaches a terminal status. A 403 hides the feature for this PR instead of surfacing an error.
@Observable
@MainActor
final class PRReviewModel {
    let store: SessionStore
    let prURL: URL

    private(set) var review: PRReview?
    private(set) var hasLoaded = false
    private(set) var isAvailable = true
    private(set) var isRequesting = false
    var error: String?

    @ObservationIgnored private var watchTask: Task<Void, Never>?

    init(store: SessionStore, prURL: URL) {
        self.store = store
        self.prURL = prURL
    }

    var canRequest: Bool {
        isAvailable && hasLoaded && !isRequesting && !(review?.isInProgress ?? false)
    }

    func load() async {
        guard !hasLoaded else { return }
        do {
            review = try await store.client.prReview(org: store.orgID, prURL: prURL)
            hasLoaded = true
            error = nil
            if let review, review.isInProgress { watch(commitSHA: review.commitSHA) }
        } catch DevinError.forbidden(_) {
            isAvailable = false
            hasLoaded = true
        } catch {
            hasLoaded = true
            self.error = error.localizedDescription
        }
    }

    func request() async {
        guard canRequest else { return }
        isRequesting = true
        defer { isRequesting = false }
        do {
            let accepted = try await store.client.requestPRReview(org: store.orgID, prURL: prURL)
            review = accepted
            error = nil
            if accepted.isInProgress { watch(commitSHA: accepted.commitSHA) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func watch(commitSHA: String) {
        stopWatching()
        watchTask = Task { [weak self, store, prURL] in
            do {
                for try await update in store.client.watchPRReview(org: store.orgID, prURL: prURL, commitSHA: commitSHA) {
                    guard let self, !Task.isCancelled else { return }
                    self.review = update
                }
            } catch is CancellationError {
            } catch {
                self?.error = error.localizedDescription
            }
        }
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }
}
