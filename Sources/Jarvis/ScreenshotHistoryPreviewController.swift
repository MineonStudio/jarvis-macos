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

        let maximumImageSize = PreviewWindowSupport.maximumContentSize(
            for: PreviewWindowSupport.screenFrames().screen,
            topChromeHeight: 0
        )
        previewController.show(
            displaySize: FullscreenMediaPreviewSizing.displaySize(
                for: image.size,
                maximumSize: maximumImageSize
            ),
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        ) {
            Image(nsImage: image)
                .interpolation(.high)
                .resizable()
                .scaledToFit()
        }
    }

    func dismiss() {
        previewController.dismiss()
    }
}
