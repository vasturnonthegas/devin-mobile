import SwiftUI

/// "Attachments" section of the New Session form. Same picker, upload model and preview strip as the
/// session composer (B3); the uploaded URLs go out as `attachment_urls` on `POST /sessions`.
struct NewSessionAttachmentsSection: View {
    let attachments: ComposerAttachments

    var body: some View {
        Section {
            if !attachments.items.isEmpty || attachments.error != nil {
                ComposerAttachmentsBar(attachments: attachments)
                    .padding(.bottom, 8)
                    .listRowInsets(EdgeInsets())
            }
            AttachmentPickerButton(attachments: attachments, title: attachments.items.isEmpty ? "Add photo or file" : "Add another")
        } header: {
            Text("Attachments")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        if attachments.isUploading {
            return "Start is enabled once every upload finishes."
        }
        if attachments.hasFailures {
            return "Retry or remove the failed upload to start."
        }
        return "Optional. Up to \(ComposerAttachments.maxCount) files, \(ComposerAttachments.maxBytes / 1024 / 1024) MB each — screenshots, logs, specs."
    }
}
