import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import DevinKit

/// "+" button in the composer. Every source ends in `ComposerAttachments.add`, which starts the upload.
struct AttachmentPickerButton: View {
    let attachments: ComposerAttachments

    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var showCamera = false
    @State private var photoItems: [PhotosPickerItem] = []

    var body: some View {
        Menu {
            Button("Photo Library", systemImage: "photo.on.rectangle") { showPhotos = true }
            if CameraPicker.isAvailable {
                Button("Take Photo", systemImage: "camera") { showCamera = true }
            }
            Button("Choose File", systemImage: "folder") { showFiles = true }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 28))
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel("Add attachment")
        .disabled(!attachments.canAddMore)
        .photosPicker(
            isPresented: $showPhotos,
            selection: $photoItems,
            maxSelectionCount: max(1, attachments.remainingSlots),
            matching: .images
        )
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            Task { await importPhotos(items) }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task { await importFiles(urls) }
            case .failure(let error):
                attachments.error = error.localizedDescription
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                Task { await importCameraImage(image) }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Importers

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        for (index, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let type = item.supportedContentTypes.first { $0.conforms(to: .image) }
                let stamp = Self.stamp()
                let name = index == 0 ? "photo-\(stamp)" : "photo-\(stamp)-\(index + 1)"
                await addImage(data, type: type, baseName: name)
            } catch {
                attachments.error = error.localizedDescription
            }
        }
    }

    private func importFiles(_ urls: [URL]) async {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try await Task.detached { try Data(contentsOf: url) }.value
                let type = UTType(filenameExtension: url.pathExtension)
                if let type, type.conforms(to: .image) {
                    await addImage(data, type: type, baseName: url.deletingPathExtension().lastPathComponent)
                } else {
                    attachments.add(data: data, filename: url.lastPathComponent,
                                    mime: type?.preferredMIMEType ?? "application/octet-stream", thumbnail: nil)
                }
            } catch {
                attachments.error = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    private func importCameraImage(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            attachments.error = "Couldn't encode the photo."
            return
        }
        let thumbnail = await image.byPreparingThumbnail(ofSize: ComposerThumbnail.pixelSize)
        attachments.add(data: data, filename: "camera-\(Self.stamp()).jpg", mime: "image/jpeg", thumbnail: thumbnail)
    }

    /// PNG/JPEG/GIF go up as-is; anything else (HEIC from Photos, TIFF, …) is re-encoded as JPEG so
    /// Devin's browser can render it.
    private func addImage(_ data: Data, type: UTType?, baseName: String) async {
        let passthrough: [UTType] = [.png, .jpeg, .gif]
        let image = UIImage(data: data)
        let thumbnail = await image?.byPreparingThumbnail(ofSize: ComposerThumbnail.pixelSize)

        if let type, passthrough.contains(where: { type.conforms(to: $0) }) {
            let ext = type.preferredFilenameExtension ?? "png"
            attachments.add(data: data, filename: "\(baseName).\(ext)", mime: type.preferredMIMEType ?? "image/\(ext)", thumbnail: thumbnail)
        } else if let jpeg = image?.jpegData(compressionQuality: 0.85) {
            attachments.add(data: jpeg, filename: "\(baseName).jpg", mime: "image/jpeg", thumbnail: thumbnail)
        } else {
            attachments.error = "Unsupported image format."
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: .now)
    }
}

enum ComposerThumbnail {
    static let pointSize: CGFloat = 56
    /// Thumbnails are decoded once at 3x so the bar never keeps full-resolution bitmaps alive.
    static let pixelSize = CGSize(width: pointSize * 3, height: pointSize * 3)
}

/// UIImagePickerController is the only camera UI that needs no AVFoundation session code.
/// Unavailable in the Simulator, so callers hide the option via `isAvailable`.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
