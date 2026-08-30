import AppKit
import SwiftUI

@MainActor
final class ScreenshotHistoryPreviewController {
    private let previewController = FullscreenMediaPreviewController()

    func show(data: Data) {
        guard let image = NSImage(data: data),
              image.size.width > 0,
              image.size.height > 0
        else {
            return
        }

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
                }
            ) {
                Image(nsImage: image)
                    .interpolation(.high)
                    .resizable()
                    .scaledToFit()
            }
        )
        hostingView.sizingOptions = []
        previewController.show(
            contentView: hostingView,
            model: model
        )
    }

    func dismiss() {
        previewController.dismiss()
    }
}
