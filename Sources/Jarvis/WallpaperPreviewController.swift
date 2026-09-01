import AppKit
import SwiftUI

@MainActor
final class WallpaperPreviewController: ObservableObject {
    private let previewController = FullscreenMediaPreviewController()
    private var loadTask: Task<Void, Never>?
    @Published private(set) var loadingItemID: String?

    func show(imageURL: URL, itemID: String, onFailure: @escaping () -> Void) {
        dismiss()
        loadingItemID = itemID

        loadTask = Task { [weak self] in
            guard let image = await WallpaperImageLoader.loadOriginal(url: imageURL) else {
                guard !Task.isCancelled else { return }
                self?.finishLoading(itemID: itemID)
                onFailure()
                return
            }
            guard !Task.isCancelled,
                  image.size.width > 0,
                  image.size.height > 0
            else {
                return
            }
            self?.finishLoading(itemID: itemID)
            self?.present(image: image)
        }
    }

    func isLoading(itemID: String) -> Bool {
        loadingItemID == itemID
    }

    func dismiss() {
        loadTask?.cancel()
        loadTask = nil
        loadingItemID = nil
        previewController.dismiss()
    }

    private func finishLoading(itemID: String) {
        guard loadingItemID == itemID else { return }
        loadingItemID = nil
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
