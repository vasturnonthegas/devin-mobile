import Foundation
import UIKit
import UniformTypeIdentifiers
import DevinKit

/// Raw share-sheet content before it is mapped onto a `SharedDraft`.
struct LoadedShare: Sendable {
    struct Image: Sendable {
        let data: Data
        let filename: String
        let mime: String
    }

    var text: String?
    var urls: [URL] = []
    var images: [Image] = []
    /// Human-readable reasons for items that were left out (too many, too large, unreadable).
    var skipped: [String] = []
}

/// Pulls text, web URLs and images out of `NSExtensionItem` providers. Every provider is tried
/// as an image first (Photos offers `public.image` *and* a file URL for the same picture), then
/// as text, then as a URL; file URLs are never treated as links.
///
/// Main-actor bound because `NSExtensionItem`/`NSItemProvider` are not `Sendable`; the providers do
/// their own work off-thread and only the continuations hop back.
@MainActor
enum ShareItemLoader {
    static func load(_ items: [NSExtensionItem]) async -> LoadedShare {
        var share = LoadedShare()
        var imageIndex = 0
        let stamp = Self.stamp()

        for item in items {
            for provider in item.attachments ?? [] {
                if let imageType = imageType(of: provider) {
                    guard share.images.count < SharedDraft.maxAttachments else {
                        share.skipped.append("Only the first \(SharedDraft.maxAttachments) images are attached.")
                        continue
                    }
                    imageIndex += 1
                    let baseName = imageIndex == 1 ? "shared-\(stamp)" : "shared-\(stamp)-\(imageIndex)"
                    do {
                        if let image = try await loadImage(from: provider, type: imageType, baseName: baseName) {
                            share.images.append(image)
                        }
                    } catch {
                        share.skipped.append(error.localizedDescription)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try? await loadText(from: provider), !text.isEmpty {
                        share.text = [share.text, text].compactMap { $0 }.joined(separator: "\n\n")
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                          !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    if let url = try? await loadURL(from: provider), !share.urls.contains(url) {
                        share.urls.append(url)
                    }
                }
            }
            // Apps like Notes put the shared text here instead of in a provider.
            if share.text == nil, let attributed = item.attributedContentText?.string,
               !attributed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                share.text = attributed
            }
        }
        return share
    }

    // MARK: Providers

    private static func imageType(of provider: NSItemProvider) -> UTType? {
        provider.registeredTypeIdentifiers
            .compactMap(UTType.init)
            .first { $0.conforms(to: .image) }
    }

    /// PNG/JPEG/GIF go up as-is; anything else (HEIC from Photos, TIFF, …) is re-encoded as JPEG,
    /// like the app's own picker, so Devin's browser can render it.
    private static func loadImage(from provider: NSItemProvider, type: UTType, baseName: String) async throws -> LoadedShare.Image? {
        let data = try await loadImageData(from: provider, type: type)
        let passthrough: [UTType] = [.png, .jpeg, .gif]
        let encoded: Data
        let ext: String
        let mime: String
        if passthrough.contains(where: { type.conforms(to: $0) }) {
            encoded = data
            ext = type.preferredFilenameExtension ?? "png"
            mime = type.preferredMIMEType ?? "image/\(ext)"
        } else if let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.85) {
            encoded = jpeg
            ext = "jpg"
            mime = "image/jpeg"
        } else {
            throw ShareLoadError.unsupportedImage
        }
        guard encoded.count <= SharedDraft.maxAttachmentBytes else {
            throw ShareLoadError.tooLarge(baseName + "." + ext)
        }
        return LoadedShare.Image(data: encoded, filename: "\(baseName).\(ext)", mime: mime)
    }

    private static func loadImageData(from provider: NSItemProvider, type: UTType) async throws -> Data {
        if let data = try? await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<Data, Error>) in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let data { continuation.resume(returning: data) } else { continuation.resume(throwing: error ?? ShareLoadError.unreadable) }
            }
        }) {
            return data
        }
        // Some providers only vend a UIImage (already PNG-encoded by `loadItem`) or a file URL.
        let item = try await loadItem(from: provider, type: type)
        switch item {
        case let data as Data:
            return data
        case let url as URL:
            return try Data(contentsOf: url)
        default:
            throw ShareLoadError.unreadable
        }
    }

    private static func loadText(from provider: NSItemProvider) async throws -> String? {
        let item = try await loadItem(from: provider, type: .plainText)
        switch item {
        case let text as String: return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case let data as Data: return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        case let url as URL: return url.absoluteString
        default: return nil
        }
    }

    private static func loadURL(from provider: NSItemProvider) async throws -> URL? {
        let item = try await loadItem(from: provider, type: .url)
        switch item {
        case let url as URL: return url
        case let text as String: return URL(string: text)
        case let data as Data: return String(data: data, encoding: .utf8).flatMap(URL.init(string:))
        default: return nil
        }
    }

    /// `loadItem` hands back whatever the provider has (URL, String, Data, UIImage); callers switch on it.
    private static func loadItem(from provider: NSItemProvider, type: UTType) async throws -> (any Sendable)? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(any Sendable)?, Error>) in
            provider.loadItem(forTypeIdentifier: type.identifier) { item, error in
                if let error { continuation.resume(throwing: error); return }
                switch item {
                case let url as URL: continuation.resume(returning: url)
                case let text as String: continuation.resume(returning: text)
                case let attributed as NSAttributedString: continuation.resume(returning: attributed.string)
                case let data as Data: continuation.resume(returning: data)
                case let image as UIImage: continuation.resume(returning: image.pngData())
                default: continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: .now)
    }
}

enum ShareLoadError: LocalizedError {
    case unreadable
    case unsupportedImage
    case tooLarge(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: return "One item couldn't be read."
        case .unsupportedImage: return "One image is in a format Devin can't display."
        case .tooLarge(let name): return "\(name) is larger than \(SharedDraft.maxAttachmentBytes / 1024 / 1024) MB and was left out."
        }
    }
}
