import SwiftUI

/// Strip of pending attachments above the composer text field: thumbnail, upload state, remove.
struct ComposerAttachmentsBar: View {
    let attachments: ComposerAttachments

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(attachments.items) { item in
                        PendingAttachmentCell(item: item) {
                            attachments.remove(item.id)
                        } retry: {
                            attachments.retry(item.id)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            if let error = attachments.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            } else if attachments.isUploading {
                Text("Uploading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else if attachments.hasFailures {
                Text("Tap a failed attachment to retry, or remove it to send.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        }
        .background(.bar)
    }
}

private struct PendingAttachmentCell: View {
    let item: PendingAttachment
    let remove: () -> Void
    let retry: () -> Void

    private let size = ComposerThumbnail.pointSize

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                preview
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                    .overlay(stateOverlay)

                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .gray)
                }
                .offset(x: 7, y: -7)
                .accessibilityLabel("Remove \(item.filename)")
            }
            .padding(.top, 7)
            .padding(.trailing, 7)

            Text(item.filename)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: size + 7)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnail = item.thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: item.isImage ? "photo" : "doc")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary.opacity(0.6))
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch item.phase {
        case .uploading:
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        case .failed(let message):
            Button(action: retry) {
                VStack(spacing: 2) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry").font(.caption2.bold())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.red.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityHint(message)
        case .uploaded:
            EmptyView()
        }
    }

    private var accessibilityDescription: String {
        switch item.phase {
        case .uploading: "\(item.filename), uploading"
        case .uploaded: "\(item.filename), uploaded"
        case .failed(let message): "\(item.filename), upload failed: \(message)"
        }
    }
}
