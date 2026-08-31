import AppKit
import SwiftUI

@MainActor
final class WallpaperPreviewController: ObservableObject {
    private let previewController = FullscreenMediaPreviewController()
    private var loadTask: Task<Void, Never>?

    func show(imageURL: URL, onFailure: @escaping () -> Void) {
        dismiss()

        loadTask = Task { [weak self] in
            guard let image = await WallpaperImageLoader.loadOriginal(url: imageURL) else {
                guard !Task.isCancelled else { return }
                onFailure()
                return
            }
            guard !Task.isCancelled,
                  image.size.width > 0,
                  image.size.height > 0
            else {
                return
            }
            self?.present(image: image)
        }
    }

    func dismiss() {
        loadTask?.cancel()
        loadTask = nil
        previewController.dismiss()
    }

    private func present(image: NSImage) {
        let screenFrame = PreviewWindowSupport.screenFrames().screen
        let maximumImageSize = PreviewWindowSupport.maximumContentSize(
            for: screenFrame,
            topChromeHeight: 0
        )
        let imageDisplaySize = FullscreenMediaPreviewSizing.displaySize(
            for: image.size,
            maximumSize: maximumImageSize
        )
        let model = FullscreenMediaPreviewModel()
        let hostingView = NSHostingView(
            rootView: FullscreenMediaPreview(
                containerSize: screenFrame.size,
                mediaDisplaySize: imageDisplaySize,
                model: model,
                onMaskClick: { [weak self] in
                    self?.dismiss()
                },
                mediaContent: {
                    Image(nsImage: image)
                        .interpolation(.high)
                        .resizable()
                        .scaledToFit()
                }
            )
        )
        hostingView.sizingOptions = []
        previewController.show(
            contentView: hostingView,
            model: model
        )
    }
}
