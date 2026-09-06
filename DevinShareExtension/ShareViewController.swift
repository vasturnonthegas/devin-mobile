import SwiftUI
import UIKit
import DevinKit

/// Principal class of the share extension (`NSExtensionPrincipalClass`). Hosts `ShareDraftView`;
/// the model calls back here to finish or cancel the extension request and to open the app.
///
/// The draft itself is handed over through the App Group (`SharedDraft.save`), never through the
/// URL, so the app picks it up on its next activation even when opening it from here is refused.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let model = ShareModel(items: items) { [weak self] outcome in
            self?.finish(outcome)
        }
        let host = UIHostingController(rootView: ShareDraftView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }

    private func finish(_ outcome: ShareModel.Outcome) {
        switch outcome {
        case .cancelled:
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        case .handedOff:
            extensionContext?.completeRequest(returningItems: nil)
        case .openApp(let url, let completion):
            openContainingApp(url, completion: completion)
        }
    }

    /// Share extensions may not use `UIApplication.shared`, and `NSExtensionContext.open` is honoured
    /// only for Today widgets on iOS, so fall back to asking the hosting application object in the
    /// responder chain. Reports `false` when neither route worked; the draft is already saved by then.
    private func openContainingApp(_ url: URL, completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard let context = extensionContext else {
            completion(openViaResponderChain(url))
            return
        }
        context.open(url) { [weak self] opened in
            Task { @MainActor in
                if opened {
                    completion(true)
                } else {
                    completion(self?.openViaResponderChain(url) ?? false)
                }
            }
        }
    }

    private func openViaResponderChain(_ url: URL) -> Bool {
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication, current.responds(to: selector) {
                _ = current.perform(selector, with: url)
                return true
            }
            responder = current.next
        }
        return false
    }
}
