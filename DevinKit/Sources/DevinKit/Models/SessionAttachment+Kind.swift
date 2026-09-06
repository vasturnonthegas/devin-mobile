import Foundation

public extension SessionAttachment {
    /// Lower-cased file extension of `name` (falls back to the URL path), without the dot.
    var fileExtension: String {
        let fromName = (name as NSString).pathExtension
        let ext = fromName.isEmpty ? url.pathExtension : fromName
        return ext.lowercased()
    }

    /// Images render inline; everything else is handed to a document previewer.
    /// `content_type` is optional in the API, so the extension is the fallback signal.
    var isImage: Bool {
        if let type = contentType?.lowercased().split(separator: ";").first.map(String.init) {
            if type.hasPrefix("image/") { return !Self.nonInlineImageTypes.contains(type) }
            if type != "application/octet-stream" && type != "binary/octet-stream" { return false }
        }
        return Self.imageExtensions.contains(fileExtension)
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "bmp", "tiff", "tif"]
    /// Vector/PSD formats decode poorly (or not at all) as bitmaps; QuickLook handles them better.
    private static let nonInlineImageTypes: Set<String> = ["image/svg+xml", "image/vnd.adobe.photoshop", "image/x-photoshop"]
}
