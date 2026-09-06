import SwiftUI
import UIKit
import DevinKit

/// Full-screen, pinch-to-zoom viewer for one image attachment.
struct AttachmentImageViewer: View {
    let attachment: SessionAttachment
    let model: SessionAttachmentsModel

    @Environment(\.dismiss) private var dismiss
    @State private var chromeHidden = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.content(for: attachment) {
            case .image(let full, _):
                ZoomableImage(image: full) {
                    withAnimation(.easeInOut(duration: 0.2)) { chromeHidden.toggle() }
                }
                .ignoresSafeArea()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load image", systemImage: "photo.badge.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { Task { await model.fetch(attachment) } }
                        .buttonStyle(.borderedProminent)
                }
                .foregroundStyle(.white)
            case .loading, .file, nil:
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .top) {
            if !chromeHidden { topBar }
        }
        .task { await model.fetch(attachment) }
        .statusBarHidden(chromeHidden)
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close")

            Spacer()

            Text(attachment.name)
                .font(.footnote)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 12)

            Spacer()

            if case .image(let full, _)? = model.content(for: attachment) {
                ShareLink(item: Image(uiImage: full), preview: SharePreview(attachment.name, image: Image(uiImage: full))) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Share image")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal)
        .padding(.top, 8)
        .transition(.opacity)
    }
}

/// UIScrollView-backed zoom (pinch, double-tap to toggle 1x/2.5x) because SwiftUI has no built-in
/// zoomable container. Single tap is reported so the host can hide chrome.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let onSingleTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSingleTap: onSingleTap) }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap))
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
        context.coordinator.layout(in: scrollView)
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        let onSingleTap: () -> Void
        weak var imageView: UIImageView?
        private var lastBounds: CGSize = .zero

        init(onSingleTap: @escaping () -> Void) {
            self.onSingleTap = onSingleTap
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { center(in: scrollView) }

        func layout(in scrollView: UIScrollView) {
            guard let imageView, scrollView.bounds.size != .zero, scrollView.bounds.size != lastBounds else { return }
            lastBounds = scrollView.bounds.size
            scrollView.zoomScale = 1
            imageView.frame = CGRect(origin: .zero, size: scrollView.bounds.size)
            scrollView.contentSize = scrollView.bounds.size
            center(in: scrollView)
        }

        /// Keeps a zoomed-out image centred instead of pinned to the top-left.
        private func center(in scrollView: UIScrollView) {
            guard let imageView else { return }
            let bounds = scrollView.bounds.size
            let content = imageView.frame.size
            scrollView.contentInset = UIEdgeInsets(
                top: max(0, (bounds.height - content.height) / 2), left: max(0, (bounds.width - content.width) / 2),
                bottom: 0, right: 0
            )
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView, let imageView else { return }
            if scrollView.zoomScale > 1 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let scale: CGFloat = 2.5
                let point = recognizer.location(in: imageView)
                let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
                scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                           width: size.width, height: size.height), animated: true)
            }
        }

        @objc func handleSingleTap() { onSingleTap() }
    }
}
