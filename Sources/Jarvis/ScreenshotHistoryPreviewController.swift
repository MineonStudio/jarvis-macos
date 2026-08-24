import AppKit
import SwiftUI

@MainActor
final class ScreenshotHistoryPreviewModel: ObservableObject {
    @Published var zoom: CGFloat = 1
    @Published var offset: CGSize = .zero

    func setZoom(_ value: CGFloat) {
        zoom = min(max(value, 0.25), 4)
        if zoom <= 1 {
            offset = .zero
        }
    }

    func adjustZoom(by delta: CGFloat) {
        setZoom(zoom + delta)
    }
}

private struct ScreenshotHistoryPreviewPresentation {
    let item: ScreenshotHistoryItem
    let data: Data
    let image: NSImage
    let imageDisplaySize: CGSize
    let imageViewportSize: CGSize
    let model: ScreenshotHistoryPreviewModel
    let previewPanel: ScreenshotHistoryPreviewPanel
}

@MainActor
final class ScreenshotHistoryPreviewController {
    private var dimmingPanel: ScreenshotHistoryDimmingPanel?
    private var panel: ScreenshotHistoryPreviewPanel?

    func show(item: ScreenshotHistoryItem, data: Data, app: AppModel) {
        guard let image = NSImage(data: data),
              image.size.width > 0,
              image.size.height > 0
        else {
            return
        }

        dismiss()

        let frames = PreviewWindowSupport.screenFrames()
        let screenFrame = frames.screen
        let visibleFrame = frames.visible
        let maximumImageSize = PreviewWindowSupport.maximumContentSize(for: screenFrame)
        let imageDisplaySize = displaySize(for: image.size, maximumSize: maximumImageSize)
        let imageViewportSize = CGSize(
            width: min(imageDisplaySize.width, maximumImageSize.width),
            height: min(imageDisplaySize.height, maximumImageSize.height)
        )
        let contentWidth = max(imageViewportSize.width, ScreenshotHistoryPreviewToolbar.preferredWidth + 22)
        let contentHeight = imageViewportSize.height
        let contentFrame = PreviewWindowSupport.centeredFrame(
            contentSize: CGSize(width: contentWidth, height: contentHeight),
            visibleFrame: visibleFrame
        )

        let previewPanel = ScreenshotHistoryPreviewPanel(
            contentRect: contentFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        PreviewWindowSupport.configurePreviewPanel(
            previewPanel,
            title: item.updatedAt.formatted(date: .abbreviated, time: .shortened)
        )
        previewPanel.isMovableByWindowBackground = false
        let model = ScreenshotHistoryPreviewModel()
        previewPanel.onWindowClose = { [weak self] in
            self?.dismiss()
        }
        previewPanel.onEscape = { [weak self] in
            self?.dismiss()
        }
        previewPanel.onScrollZoom = { [weak model] delta in
            model?.adjustZoom(by: delta)
        }

        let imageHostingView = makeHostingView(
            ScreenshotHistoryPreviewPresentation(
                item: item,
                data: data,
                image: image,
                imageDisplaySize: imageDisplaySize,
                imageViewportSize: imageViewportSize,
                model: model,
                previewPanel: previewPanel
            ),
            app: app
        )
        imageHostingView.frame = NSRect(origin: .zero, size: contentFrame.size)
        imageHostingView.autoresizingMask = [.width, .height]
        previewPanel.contentView = imageHostingView

        let dimmingPanel = ScreenshotHistoryDimmingPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        PreviewWindowSupport.configureDimmingPanel(dimmingPanel, screenFrame: screenFrame)

        self.dimmingPanel = dimmingPanel
        panel = previewPanel
        dimmingPanel.orderFrontRegardless()
        previewPanel.orderFrontRegardless()
        previewPanel.makeKey()
    }

    private func makeHostingView(
        _ presentation: ScreenshotHistoryPreviewPresentation,
        app: AppModel
    ) -> NSHostingView<ScreenshotHistoryPreview> {
        NSHostingView(
            rootView: ScreenshotHistoryPreview(
                data: presentation.data,
                image: presentation.image,
                imageDisplaySize: presentation.imageDisplaySize,
                imageViewportSize: presentation.imageViewportSize,
                app: app,
                model: presentation.model,
                onClose: { [weak self] in
                    self?.dismiss()
                },
                onEdit: { [weak self, weak app] in
                    self?.dismiss()
                    DispatchQueue.main.async {
                        app?.editScreenshotHistory(presentation.item)
                    }
                },
                onCopy: { [weak app] in
                    app?.copyScreenshotHistory(presentation.item)
                },
                onSave: { [weak app, weak previewPanel = presentation.previewPanel] in
                    app?.saveScreenshotHistory(
                        presentation.item,
                        presentingWindow: previewPanel
                    )
                },
                onDelete: { [weak self, weak app] in
                    self?.dismiss()
                    app?.deleteScreenshotHistory(presentation.item)
                }
            )
        )
    }

    func dismiss() {
        let previewPanel = panel
        let dimmingPanel = dimmingPanel
        previewPanel?.onWindowClose = nil
        previewPanel?.onEscape = nil
        self.dimmingPanel = nil
        panel = nil
        previewPanel?.orderOut(nil)
        previewPanel?.close()
        dimmingPanel?.orderOut(nil)
        dimmingPanel?.close()
    }

    private func displaySize(for imageSize: CGSize, maximumSize: CGSize) -> CGSize {
        let maximumScale = min(
            maximumSize.width / imageSize.width,
            maximumSize.height / imageSize.height
        )
        let minimumDisplayWidth: CGFloat = 560
        let minimumDisplayHeight: CGFloat = 420
        let requestedScale = max(
            1,
            max(
                minimumDisplayWidth / imageSize.width,
                minimumDisplayHeight / imageSize.height
            )
        )
        let fitsAtOriginalSize = imageSize.width <= maximumSize.width
            && imageSize.height <= maximumSize.height
        let scale = fitsAtOriginalSize ? min(maximumScale, requestedScale) : 1
        return CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
    }
}

private final class ScreenshotHistoryDimmingPanel: NSPanel {}

private final class ScreenshotHistoryPreviewPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onScrollZoom: ((CGFloat) -> Void)?
    var onWindowClose: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func performClose(_: Any?) {
        onWindowClose?()
    }

    override func close() {
        let closeHandler = onWindowClose
        onWindowClose = nil
        closeHandler?()
        super.close()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            onEscape?()
            return
        }
        if event.type == .scrollWheel, abs(event.scrollingDeltaY) > 0.01 {
            onScrollZoom?(event.scrollingDeltaY > 0 ? 0.1 : -0.1)
            return
        }
        super.sendEvent(event)
    }
}
