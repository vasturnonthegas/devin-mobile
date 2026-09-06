import SwiftUI
import DevinKit

extension View {
    /// Opens the New Session sheet prefilled from the share extension's `SharedDraft` whenever the
    /// app becomes active with one pending. Attach to the signed-in root: a draft shared while
    /// signed out waits in the App Group until the inbox is on screen.
    func presentsSharedDrafts(store: SessionStore) -> some View {
        modifier(SharedDraftFlow(store: store))
    }
}

/// The share extension's payload, read into memory. Taking it removes the draft and its files from
/// the App Group, so a cancelled sheet does not come back on the next activation.
struct PendingShare: Identifiable {
    let id = UUID()
    let prompt: String
    let repos: [String]
    let attachments: [DraftAttachment]

    static func take() async -> PendingShare? {
        #if DEBUG
        if let seeded = await launchArgumentShare() { return seeded }
        #endif
        guard let draft = SharedDraft.load() else { return nil }
        let directory = SharedDraft.directory()
        let attachments = await Task.detached {
            draft.attachments.compactMap { attachment -> DraftAttachment? in
                guard let data = try? attachment.data(in: directory) else { return nil }
                return DraftAttachment(data: data, filename: attachment.filename, mime: attachment.mime)
            }
        }.value
        SharedDraft.clear()
        return PendingShare(prompt: draft.prompt, repos: draft.repos, attachments: attachments)
    }

    #if DEBUG
    /// `-SharedDraft "<text>"` (with `-MockAPI`) simulates a share the extension parked: the text goes
    /// through `SharedDraft.compose` (GitHub links → repos) and `-SharedDraftImage` adds a rendered PNG
    /// so the upload path runs. Consumed once per launch.
    @MainActor private static var consumedLaunchArgument = false

    @MainActor private static func launchArgumentShare() -> PendingShare? {
        guard !consumedLaunchArgument, let text = UserDefaults.standard.string(forKey: "SharedDraft") else { return nil }
        consumedLaunchArgument = true
        let draft = SharedDraft.compose(text: text)
        var attachments: [DraftAttachment] = []
        if ProcessInfo.processInfo.arguments.contains("-SharedDraftImage") {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 200))
            let png = renderer.pngData { context in
                UIColor.systemIndigo.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
                ("Shared screenshot" as NSString).draw(at: CGPoint(x: 24, y: 88), withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor.white,
                ])
            }
            attachments.append(DraftAttachment(data: png, filename: "shared-screenshot.png", mime: "image/png"))
        }
        return PendingShare(prompt: draft.prompt, repos: draft.repos, attachments: attachments)
    }
    #endif
}

private struct SharedDraftFlow: ViewModifier {
    let store: SessionStore
    @Environment(\.scenePhase) private var scenePhase
    // Optional so previews without a router still render; without one the created session is not pushed.
    @Environment(DeepLinkRouter.self) private var router: DeepLinkRouter?
    @State private var share: PendingShare?

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active, share == nil else { return }
                Task { share = await PendingShare.take() }
            }
            .sheet(item: $share) { share in
                NewSessionView(
                    store: store,
                    initialPrompt: share.prompt,
                    initialRepos: share.repos,
                    initialAttachments: share.attachments
                ) { created in
                    // The inbox's `.followsDeepLinks` pushes it, exactly like a notification tap would.
                    router?.pending = .session(id: created.id)
                }
            }
    }
}
