import Foundation
import Observation
import UIKit
import DevinKit

/// A file the user picked for the next message. Uploads start immediately; the message is sent
/// with the resulting `url`s, so a send is only possible once every item is `.uploaded`.
struct PendingAttachment: Identifiable, Sendable {
    enum Phase: Sendable {
        case uploading
        case uploaded(URL)
        case failed(String)
    }

    let id: UUID
    let filename: String
    let mime: String
    let data: Data
    let thumbnail: UIImage?
    var phase: Phase = .uploading

    var isImage: Bool { mime.hasPrefix("image/") }
}

@Observable
@MainActor
final class ComposerAttachments {
    /// Client-side guardrails; the API's own limits win and surface as a per-item error.
    static let maxCount = 5
    static let maxBytes = 25 * 1024 * 1024

    let client: DevinClient
    let orgID: String

    private(set) var items: [PendingAttachment] = []
    var error: String?

    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    init(client: DevinClient, orgID: String) {
        self.client = client
        self.orgID = orgID
    }

    var canAddMore: Bool { items.count < Self.maxCount }
    var remainingSlots: Int { max(0, Self.maxCount - items.count) }

    var isUploading: Bool {
        items.contains { if case .uploading = $0.phase { return true } else { return false } }
    }

    var hasFailures: Bool {
        items.contains { if case .failed = $0.phase { return true } else { return false } }
    }

    var uploadedURLs: [URL] {
        items.compactMap { if case .uploaded(let url) = $0.phase { return url } else { return nil } }
    }

    /// True when there is at least one attachment and all of them are on the server.
    var isReadyToSend: Bool { !items.isEmpty && uploadedURLs.count == items.count }

    /// Message text used when the user sends attachments without typing anything.
    var fallbackMessage: String {
        "Attached: " + items.map(\.filename).joined(separator: ", ")
    }

    func add(data: Data, filename: String, mime: String, thumbnail: UIImage?) {
        error = nil
        guard canAddMore else {
            error = "You can attach up to \(Self.maxCount) files per message."
            return
        }
        guard data.count <= Self.maxBytes else {
            error = "\(filename) is too large (limit \(Self.maxBytes / 1024 / 1024) MB)."
            return
        }
        let item = PendingAttachment(id: UUID(), filename: filename, mime: mime, data: data, thumbnail: thumbnail)
        items.append(item)
        upload(item)
    }

    func retry(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].phase = .uploading
        upload(items[index])
    }

    func remove(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        items.removeAll { $0.id == id }
    }

    func clear() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        items = []
        error = nil
    }

    private func upload(_ item: PendingAttachment) {
        tasks[item.id]?.cancel()
        tasks[item.id] = Task { [client, orgID] in
            let phase: PendingAttachment.Phase
            do {
                let uploaded = try await client.upload(data: item.data, filename: item.filename, mime: item.mime, org: orgID)
                phase = .uploaded(uploaded.url)
            } catch {
                phase = .failed(error.localizedDescription)
            }
            guard !Task.isCancelled else { return }
            self.finish(item.id, phase: phase)
        }
    }

    private func finish(_ id: UUID, phase: PendingAttachment.Phase) {
        tasks[id] = nil
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].phase = phase
    }
}
