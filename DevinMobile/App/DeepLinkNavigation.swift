import SwiftUI
import DevinKit

extension View {
    /// Follows pending deep links by replacing `path` with the target session. Attach inside the
    /// inbox's `NavigationStack`, which owns `path`.
    func followsDeepLinks(store: SessionStore, path: Binding<NavigationPath>) -> some View {
        modifier(DeepLinkNavigation(store: store, path: path))
    }
}

private struct DeepLinkNavigation: ViewModifier {
    let store: SessionStore
    @Binding var path: NavigationPath
    // Optional so previews and tests that don't inject a router still render.
    @Environment(DeepLinkRouter.self) private var router: DeepLinkRouter?

    func body(content: Content) -> some View {
        content.onChange(of: router?.pending, initial: true) { _, pending in
            guard pending != nil, let link = router?.take() else { return }
            Task { await follow(link) }
        }
    }

    /// The list may not be loaded yet (cold start), so fall back to fetching the session by ID;
    /// `reload` also upserts it into the store, which `SessionDetailModel` reads from.
    private func follow(_ link: DeepLink) async {
        switch link {
        case .session(let id):
            do {
                let session: Session
                if let loaded = store.session(id: id) {
                    session = loaded
                } else {
                    session = try await store.reload(id: id)
                }
                path = NavigationPath([session])
            } catch let error as DevinError {
                store.error = error
            } catch {
                store.error = .transport(error.localizedDescription)
            }
        }
    }
}
