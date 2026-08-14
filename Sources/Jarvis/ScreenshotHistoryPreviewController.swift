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

@MainActor
final class ScreenshotHistoryPreviewController {
    private var dimmingPanel: ScreenshotHistoryDimmingPanel?
    private var panel: ScreenshotHistoryPreviewPanel?

    func show(item: ScreenshotHistoryItem, data: Data, app: AppModel) {
        guard let image = NSImage(data: data),
              image.size.width > 0,
              image.size.height > 0 else {
            return
        }

        dismiss()

        let screenFrame = NSScreen.main?.frame ?? CGRect(
            origin: .zero,
            size: CGSize(width: 1200, height: 800)
        )
        let visibleFrame = NSScreen.main?.visibleFrame ?? screenFrame
        let titlebarHeight: CGFloat = 28
        let maximumImageSize = CGSize(
            width: screenFrame.width - 80,
            height: screenFrame.height - 80 - titlebarHeight
        )
        let imageDisplaySize = displaySize(for: image.size, maximumSize: maximumImageSize)
        let imageViewportSize = CGSize(
            width: min(imageDisplaySize.width, maximumImageSize.width),
            height: min(imageDisplaySize.height, maximumImageSize.height)
        )
        let contentWidth = max(imageViewportSize.width, ScreenshotHistoryPreviewToolbar.preferredWidth + 22)
        let contentHeight = imageViewportSize.height
        let contentFrame = CGRect(
            x: visibleFrame.midX - contentWidth / 2,
            y: visibleFrame.midY - (contentHeight + titlebarHeight) / 2,
            width: contentWidth,
            height: contentHeight
        )

        let previewPanel = ScreenshotHistoryPreviewPanel(
            contentRect: contentFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        previewPanel.level = .screenSaver
        previewPanel.title = item.updatedAt.formatted(date: .abbreviated, time: .shortened)
        previewPanel.titleVisibility = .visible
        previewPanel.titlebarAppearsTransparent = false
        previewPanel.titlebarSeparatorStyle = .none
        previewPanel.backgroundColor = .black
        previewPanel.isOpaque = true
        previewPanel.hasShadow = true
        previewPanel.isMovableByWindowBackground = false
        previewPanel.hidesOnDeactivate = false
        previewPanel.isReleasedWhenClosed = false
        previewPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        previewPanel.standardWindowButton(.closeButton)?.isHidden = false
        previewPanel.standardWindowButton(.miniaturizeButton)?.isHidden = false
        previewPanel.standardWindowButton(.zoomButton)?.isHidden = false
        previewPanel.standardWindowButton(.zoomButton)?.isEnabled = true
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

        let imageHostingView = NSHostingView(
            rootView: ScreenshotHistoryPreview(
                image: image,
                imageDisplaySize: imageDisplaySize,
                imageViewportSize: imageViewportSize,
                model: model,
                onClose: { [weak self] in
                    self?.dismiss()
                },
                onEdit: { [weak self, weak app] in
                    self?.dismiss()
                    DispatchQueue.main.async {
                        app?.editScreenshotHistory(item)
                    }
                },
                onCopy: { [weak app] in
                    app?.copyScreenshotHistory(item)
                },
                onSave: { [weak app, weak previewPanel] in
                    app?.saveScreenshotHistory(item, presentingWindow: previewPanel)
                },
                onDelete: { [weak self, weak app] in
                    self?.dismiss()
                    app?.deleteScreenshotHistory(item)
                }
            )
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
        dimmingPanel.level = .screenSaver
        dimmingPanel.backgroundColor = NSColor.black.withAlphaComponent(0.58)
        dimmingPanel.isOpaque = false
        dimmingPanel.hasShadow = false
        dimmingPanel.ignoresMouseEvents = true
        dimmingPanel.hidesOnDeactivate = false
        dimmingPanel.isReleasedWhenClosed = false
        dimmingPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        self.dimmingPanel = dimmingPanel
        panel = previewPanel
        dimmingPanel.orderFrontRegardless()
        previewPanel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        let previewPanel = panel
        let dimmingPanel = self.dimmingPanel
        previewPanel?.onWindowClose = nil
        previewPanel?.onEscape = nil
        self.dimmingPanel = nil
        self.panel = nil
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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performClose(_ sender: Any?) {
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
