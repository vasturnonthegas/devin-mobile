import Foundation
import Observation
import UIKit
import DevinKit

/// Attachments of one session plus their downloaded bytes.
///
/// The API does not link attachments to messages, so `placement(in:)` pins an attachment under the
/// first message whose text quotes its URL and leaves the rest for the header section. Images are
/// downloaded eagerly (thumbnails); other files only when tapped. Downloaded files live under the
/// app's temporary directory so QuickLook can open them; nothing is persisted elsewhere.
@Observable
@MainActor
final class SessionAttachmentsModel {
    enum Content {
        case loading
        case image(full: UIImage, thumbnail: UIImage)
        case file(URL)
        case failed(String)
    }

    struct Placement {
        var byMessage: [String: [SessionAttachment]] = [:]
        var unplaced: [SessionAttachment] = []
    }

    let store: SessionStore
    let sessionID: String

    private(set) var attachments: [SessionAttachment] = []
    private(set) var contents: [String: Content] = [:]
    /// Set once the API refused the list (403); the UI then stays silent instead of retrying forever.
    private(set) var isForbidden = false

    @ObservationIgnored private var inFlight: [String: Task<Content, Never>] = [:]

    init(store: SessionStore, sessionID: String) {
        self.store = store
        self.sessionID = sessionID
    }

    var isEmpty: Bool { attachments.isEmpty }

    func content(for attachment: SessionAttachment) -> Content? {
        contents[attachment.id]
    }

    func load() async {
        guard !isForbidden else { return }
        do {
            attachments = try await store.client.attachments(org: store.orgID, id: sessionID)
            for attachment in attachments where attachment.isImage && contents[attachment.id] == nil {
                Task { _ = await fetch(attachment) }
            }
        } catch DevinError.forbidden {
            isForbidden = true
        } catch {
            // Keep whatever was listed before; the next poll retries.
        }
    }

    func placement(in messages: [SessionMessage]) -> Placement {
        var placement = Placement()
        for attachment in attachments {
            let needles = [attachment.url.absoluteString, store.client.downloadURL(for: attachment).absoluteString]
            if let host = messages.first(where: { message in needles.contains { message.message.contains($0) } }) {
                placement.byMessage[host.id, default: []].append(attachment)
            } else {
                placement.unplaced.append(attachment)
            }
        }
        return placement
    }

    /// Downloads (once) and decodes an attachment. Concurrent callers share the same task.
    @discardableResult
    func fetch(_ attachment: SessionAttachment) async -> Content {
        if let cached = contents[attachment.id], !cached.isRetryable { return cached }
        if let task = inFlight[attachment.id] { return await task.value }

        contents[attachment.id] = .loading
        let task = Task<Content, Never> { [store] in
            do {
                let data = try await store.client.attachmentData(attachment)
                return try await Self.decode(data, for: attachment)
            } catch {
                return .failed(error.localizedDescription)
            }
        }
        inFlight[attachment.id] = task
        let content = await task.value
        inFlight[attachment.id] = nil
        contents[attachment.id] = content
        return content
    }

    private static func decode(_ data: Data, for attachment: SessionAttachment) async throws -> Content {
        if attachment.isImage {
            guard let image = UIImage(data: data) else { throw DevinError.decoding("Not a displayable image") }
            let thumbnail = await image.byPreparingThumbnail(ofSize: CGSize(width: 400, height: 400)) ?? image
            let full = await image.byPreparingForDisplay() ?? image
            return .image(full: full, thumbnail: thumbnail)
        }
        return .file(try write(data, for: attachment))
    }

    private static func write(_ data: Data, for attachment: SessionAttachment) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent(attachment.id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = attachment.name.replacingOccurrences(of: "/", with: "_")
        let file = directory.appendingPathComponent(safeName.isEmpty ? "attachment" : safeName)
        try data.write(to: file, options: .atomic)
        return file
    }
}

extension SessionAttachmentsModel.Content {
    var isRetryable: Bool {
        if case .failed = self { return true }
        return false
    }
}
