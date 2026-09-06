import Foundation

// MARK: Session insights

public extension DevinClient {
    /// Insights for one session. `analysis` is nil until generation has completed; 403 means the
    /// principal may not read insights and the UI should hide the feature.
    func sessionInsights(org: String, id: String) async throws -> SessionInsights {
        try await request(.get, "/v3/organizations/\(org)/sessions/\(id)/insights")
    }

    /// Kicks off analysis in the background. Poll `sessionInsights` until `analysis` is non-nil.
    func generateInsights(org: String, id: String) async throws -> SessionInsightsGeneration {
        try await request(.post, "/v3/organizations/\(org)/sessions/\(id)/insights/generate")
    }
}
