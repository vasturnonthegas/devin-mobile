import UIKit

enum ExternalLink {
    /// Hands `url` to the app that claims it as a Universal Link (GitHub, GitLab, …) when one is
    /// installed, otherwise Safari. No `LSApplicationQueriesSchemes` needed, so no `project.yml` churn.
    @MainActor
    static func open(_ url: URL) {
        UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { openedInApp in
            guard !openedInApp else { return }
            Task { @MainActor in UIApplication.shared.open(url) }
        }
    }
}
