import Foundation
import Observation
import DevinKit

/// Holds the most recent deep link until a signed-in inbox is on screen to follow it.
/// A link that arrives during `.loading` (cold start) or `.signedOut` stays pending, so it is
/// honoured right after `restore()` / sign-in instead of being dropped.
@Observable
@MainActor
final class DeepLinkRouter {
    var pending: DeepLink?

    init() {
        #if DEBUG
        pending = Self.launchArgumentLink
        #endif
    }

    /// Unknown URLs are ignored; the scheme is registered for `DeepLink` only.
    func open(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        pending = link
    }

    func take() -> DeepLink? {
        defer { pending = nil }
        return pending
    }

    #if DEBUG
    /// `-OpenURL devinmobile://session/<id>` simulates a cold start from a deep link, which
    /// `simctl openurl` can't do together with `-MockAPI`.
    private static var launchArgumentLink: DeepLink? {
        UserDefaults.standard.string(forKey: "OpenURL").flatMap(URL.init(string:)).flatMap(DeepLink.init(url:))
    }
    #endif
}
