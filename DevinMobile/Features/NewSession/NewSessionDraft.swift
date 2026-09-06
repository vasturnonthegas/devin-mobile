import Foundation
import UIKit

/// A file handed to the New Session form before it appears (share extension). It takes the same
/// path as a picked file — `ComposerAttachments.add` starts the upload — so `attachment_urls` on
/// `POST /sessions` never sees raw bytes.
struct DraftAttachment: Hashable, Sendable {
    let data: Data
    let filename: String
    let mime: String
}

extension ComposerAttachments {
    /// Queues every draft for upload. Thumbnails are decoded here, off the caller's critical path.
    func seed(_ drafts: [DraftAttachment]) async {
        for draft in drafts {
            var thumbnail: UIImage?
            if draft.mime.hasPrefix("image/"), let image = UIImage(data: draft.data) {
                thumbnail = await image.byPreparingThumbnail(ofSize: ComposerThumbnail.pixelSize)
            }
            add(data: draft.data, filename: draft.filename, mime: draft.mime, thumbnail: thumbnail)
        }
    }
}
