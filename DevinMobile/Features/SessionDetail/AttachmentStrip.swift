import SwiftUI
import QuickLook
import DevinKit

/// Header block for attachments that no message quotes.
struct AttachmentsSection: View {
    let attachments: [SessionAttachment]
    let model: SessionAttachmentsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("^[\(attachments.count) attachment](inflect: true)", systemImage: "paperclip")
                .font(.caption)
                .foregroundStyle(.secondary)
            AttachmentStrip(attachments: attachments, model: model)
        }
    }
}

/// Thumbnails for image attachments and chips for everything else. Tapping an image opens the
/// full-screen viewer; tapping a file downloads it (once) and hands it to QuickLook.
struct AttachmentStrip: View {
    let attachments: [SessionAttachment]
    let model: SessionAttachmentsModel

    @State private var fullScreenImage: SessionAttachment?
    @State private var previewURL: URL?
    @State private var openingFileID: String?

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(attachments) { attachment in
                if attachment.isImage {
                    Button {
                        fullScreenImage = attachment
                    } label: {
                        AttachmentThumbnail(attachment: attachment, content: model.content(for: attachment))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Image attachment \(attachment.name)")
                    .accessibilityHint("Opens full screen")
                } else {
                    Button {
                        open(attachment)
                    } label: {
                        AttachmentFileChip(attachment: attachment, isBusy: openingFileID == attachment.id,
                                           failure: failureMessage(for: attachment))
                    }
                    .buttonStyle(.plain)
                    .disabled(openingFileID != nil)
                    .accessibilityLabel("File attachment \(attachment.name)")
                    .accessibilityHint("Opens a preview")
                }
            }
        }
        .fullScreenCover(item: $fullScreenImage) { attachment in
            AttachmentImageViewer(attachment: attachment, model: model)
        }
        .quickLookPreview($previewURL)
    }

    private func open(_ attachment: SessionAttachment) {
        if case .file(let url)? = model.content(for: attachment) {
            previewURL = url
            return
        }
        openingFileID = attachment.id
        Task {
            let content = await model.fetch(attachment)
            openingFileID = nil
            if case .file(let url) = content { previewURL = url }
        }
    }

    private func failureMessage(for attachment: SessionAttachment) -> String? {
        if case .failed(let message)? = model.content(for: attachment) { return message }
        return nil
    }
}

struct AttachmentThumbnail: View {
    let attachment: SessionAttachment
    let content: SessionAttachmentsModel.Content?

    private let side: CGFloat = 96

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary.opacity(0.6))
            switch content {
            case .image(_, let thumbnail):
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            case .failed:
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.exclamationmark")
                    Text("Tap to retry").font(.caption2)
                }
                .foregroundStyle(.secondary)
            case .loading, .file, nil:
                ProgressView()
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 0.5))
    }
}

struct AttachmentFileChip: View {
    let attachment: SessionAttachment
    let isBusy: Bool
    let failure: String?

    var body: some View {
        HStack(spacing: 8) {
            if isBusy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: failure == nil ? symbolName : "exclamationmark.triangle")
                    .foregroundStyle(failure == nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.red))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name.isEmpty ? "Attachment" : attachment.name)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(failure ?? subtitle)
                    .font(.caption2)
                    .foregroundStyle(failure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 240, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 0.5))
    }

    private var subtitle: String {
        let ext = attachment.fileExtension.uppercased()
        return ext.isEmpty ? "File" : ext
    }

    private var symbolName: String {
        switch attachment.fileExtension {
        case "pdf": "doc.richtext"
        case "zip", "gz", "tar", "tgz": "doc.zipper"
        case "log", "txt", "md": "doc.plaintext"
        case "csv", "json", "yaml", "yml", "xml": "tablecells"
        case "mov", "mp4", "m4v": "film"
        case "mp3", "m4a", "wav": "waveform"
        default: "doc"
        }
    }
}
