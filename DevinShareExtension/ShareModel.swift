import Foundation
import Observation
import UIKit
import DevinKit

/// State of the share sheet: load the items, let the user trim the draft, then park it in the App
/// Group and open the app. Image bytes are written to the draft directory as soon as they are
/// loaded (they may not fit in the extension's memory budget as `Data` for long); a cancelled share
/// deletes them again.
@Observable
@MainActor
final class ShareModel {
    enum Phase: Equatable {
        case loading
        case ready
        /// The draft is saved. `opened` is false when the app could not be launched from here.
        case handedOff(opened: Bool)
    }

    enum Outcome {
        case cancelled
        case handedOff
        case openApp(URL, completion: @MainActor @Sendable (Bool) -> Void)
    }

    /// `devinmobile://share` carries nothing; it exists so opening it brings the app forward, where
    /// `SharedDraft.load` finds the payload.
    static let openURL = URL(string: "devinmobile://share")!

    private(set) var phase: Phase = .loading
    var draft = SharedDraft()
    private(set) var thumbnails: [SharedDraft.Attachment.ID: UIImage] = [:]
    private(set) var skipped: [String] = []
    private(set) var saveError: String?
    let isSignedIn: Bool

    private let items: [NSExtensionItem]
    private let finish: @MainActor (Outcome) -> Void

    init(items: [NSExtensionItem], finish: @escaping @MainActor (Outcome) -> Void) {
        self.items = items
        self.finish = finish
        isSignedIn = WidgetContent.resolve(credentials: AppGroup.credentialStore) != .signedOut
    }

    var canContinue: Bool { phase == .ready && !draft.isEmpty }

    func load() async {
        guard phase == .loading else { return }
        let share = await ShareItemLoader.load(items)
        var attachments: [SharedDraft.Attachment] = []
        var skipped = share.skipped
        for image in share.images {
            do {
                let attachment = try SharedDraft.Attachment.write(image.data, filename: image.filename, mime: image.mime, to: SharedDraft.directory())
                attachments.append(attachment)
                thumbnails[attachment.id] = await UIImage(data: image.data)?.byPreparingThumbnail(ofSize: CGSize(width: 168, height: 168))
            } catch {
                skipped.append("\(image.filename) couldn't be saved: \(error.localizedDescription)")
            }
        }
        draft = SharedDraft.compose(text: share.text, urls: share.urls, attachments: attachments)
        self.skipped = skipped
        phase = .ready
    }

    func removeRepo(_ repo: String) {
        draft.repos.removeAll { $0 == repo }
    }

    func removeAttachment(_ id: SharedDraft.Attachment.ID) {
        guard let index = draft.attachments.firstIndex(where: { $0.id == id }) else { return }
        let removed = draft.attachments.remove(at: index)
        thumbnails[id] = nil
        try? FileManager.default.removeItem(at: removed.fileURL(in: SharedDraft.directory()))
    }

    func cancel() {
        draft.removeAttachmentFiles()
        finish(.cancelled)
    }

    func continueInApp() {
        guard canContinue else { return }
        draft.prompt = draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try draft.save()
        } catch {
            saveError = "Couldn't hand the draft to Devin: \(error.localizedDescription)"
            return
        }
        finish(.openApp(Self.openURL) { [weak self] opened in
            guard let self else { return }
            self.phase = .handedOff(opened: opened)
            if opened { self.finish(.handedOff) }
        })
    }

    func done() {
        finish(.handedOff)
    }
}
