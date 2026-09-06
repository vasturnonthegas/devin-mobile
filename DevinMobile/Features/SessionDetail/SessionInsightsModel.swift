import Foundation
import Observation
import DevinKit

/// Loads one session's insights and drives on-demand generation. Generation is asynchronous on the
/// server, so after `POST …/insights/generate` the model polls `GET …/insights` until `analysis`
/// arrives or `generationTimeout` elapses. A 403 is sticky (`isForbidden`) and hides the feature.
@Observable
@MainActor
final class SessionInsightsModel {
    static let pollInterval: Duration = .seconds(4)
    static let generationTimeout: Duration = .seconds(150)

    let store: SessionStore
    let sessionID: String

    private(set) var insights: SessionInsights?
    private(set) var isLoading = false
    private(set) var isGenerating = false
    private(set) var isForbidden = false
    private(set) var hasLoaded = false
    var error: String?

    @ObservationIgnored private var generationTask: Task<Void, Never>?

    init(store: SessionStore, sessionID: String) {
        self.store = store
        self.sessionID = sessionID
    }

    var analysis: SessionInsightsAnalysis? { insights?.analysis }
    var canGenerate: Bool { hasLoaded && !isForbidden && !isGenerating && analysis == nil }

    func load() async {
        guard !isForbidden else { return }
        isLoading = insights == nil
        defer { isLoading = false }
        do {
            insights = try await store.client.sessionInsights(org: store.orgID, id: sessionID)
            error = nil
        } catch DevinError.forbidden {
            isForbidden = true
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
        hasLoaded = true
    }

    func generate() {
        guard canGenerate else { return }
        isGenerating = true
        error = nil
        generationTask?.cancel()
        generationTask = Task { [weak self] in
            await self?.runGeneration()
            self?.isGenerating = false
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }

    private func runGeneration() async {
        do {
            _ = try await store.client.generateInsights(org: store.orgID, id: sessionID)
        } catch DevinError.forbidden {
            isForbidden = true
            return
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            return
        }

        let deadline = ContinuousClock.now + Self.generationTimeout
        while !Task.isCancelled {
            await load()
            if analysis != nil || isForbidden || error != nil { return }
            if ContinuousClock.now >= deadline {
                error = "Insights are still being generated. Pull to refresh in a minute."
                return
            }
            try? await Task.sleep(for: Self.pollInterval)
        }
    }
}
