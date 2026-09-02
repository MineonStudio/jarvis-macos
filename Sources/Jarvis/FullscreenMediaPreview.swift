import AppKit
import SwiftUI

@MainActor
final class FullscreenMediaPreviewModel: ObservableObject {
    static let zoomStep: CGFloat = 0.1
    static let minimumZoom: CGFloat = 0.2
    static let maximumZoom: CGFloat = 4

    @Published var zoom: CGFloat = 1

    func setZoom(_ value: CGFloat) {
        let steppedValue = (value / Self.zoomStep).rounded() * Self.zoomStep
        zoom = min(max(steppedValue, Self.minimumZoom), Self.maximumZoom)
    }

    func adjustZoom(by delta: CGFloat) {
        guard delta != 0 else { return }
        setZoom(zoom + (delta > 0 ? Self.zoomStep : -Self.zoomStep))
    }

    func displaySize(for baseSize: CGSize) -> CGSize {
        CGSize(
            width: baseSize.width * zoom,
            height: baseSize.height * zoom
        )
    }
}

enum FullscreenMediaPreviewSizing {
    static func displaySize(for mediaSize: CGSize, maximumSize: CGSize) -> CGSize {
        guard mediaSize.width > 0, mediaSize.height > 0 else {
            return CGSize(width: 720, height: 520)
        }

        let maximumScale = min(
            maximumSize.width / mediaSize.width,
            maximumSize.height / mediaSize.height
        )
        let minimumDisplayWidth: CGFloat = 560
        let minimumDisplayHeight: CGFloat = 420
        let requestedScale = max(
            1,
            max(
                minimumDisplayWidth / mediaSize.width,
                minimumDisplayHeight / mediaSize.height
            )
        )
        let scale = min(maximumScale, requestedScale)
        return CGSize(
            width: mediaSize.width * scale,
            height: mediaSize.height * scale
        )
    }

    static func videoDisplaySize(maximumSize: CGSize) -> CGSize {
        let preferred = CGSize(width: 960, height: 620)
        let scale = min(
            1,
            min(
                maximumSize.width / preferred.width,
                maximumSize.height / preferred.height
            )
        )
        return CGSize(width: preferred.width * scale, height: preferred.height * scale)
    }
}

struct FullscreenMediaPreview<MediaContent: View>: View {
    let containerSize: CGSize
    let mediaDisplaySize: CGSize
    @ObservedObject var model: FullscreenMediaPreviewModel
    let allowsMediaHitTesting: Bool
    let onMaskClick: () -> Void
    let mediaContent: MediaContent

    init(
        containerSize: CGSize,
        mediaDisplaySize: CGSize,
        model: FullscreenMediaPreviewModel,
        allowsMediaHitTesting: Bool = false,
        onMaskClick: @escaping () -> Void,
        @ViewBuilder mediaContent: () -> MediaContent
    ) {
        self.containerSize = containerSize
        self.mediaDisplaySize = mediaDisplaySize
        self.model = model
        self.allowsMediaHitTesting = allowsMediaHitTesting
        self.onMaskClick = onMaskClick
        self.mediaContent = mediaContent()
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(0.58)
                .contentShape(Rectangle())
                .onTapGesture(perform: onMaskClick)

            mediaContent
                .frame(
                    width: model.displaySize(for: mediaDisplaySize).width,
                    height: model.displaySize(for: mediaDisplaySize).height
                )
                .allowsHitTesting(allowsMediaHitTesting)

            if !allowsMediaHitTesting {
                Rectangle()
                    .fill(Color.clear)
                    .frame(
                        width: model.displaySize(for: mediaDisplaySize).width,
                        height: model.displaySize(for: mediaDisplaySize).height
                    )
                    .contentShape(Rectangle())
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .clipped()
    }
}

@MainActor
final class FullscreenMediaPreviewController {
    private var panel: FullscreenMediaPreviewPanel?
    private var model: FullscreenMediaPreviewModel?

    func show(
        contentView: NSView,
        model: FullscreenMediaPreviewModel
    ) {
        dismiss()

        let screenFrame = PreviewWindowSupport.screenFrames().screen
        let previewPanel = FullscreenMediaPreviewPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        PreviewWindowSupport.configureBorderlessPreviewPanel(previewPanel)
        previewPanel.isMovableByWindowBackground = false
        previewPanel.onWindowClose = { [weak self] in
            self?.dismiss()
        }
        previewPanel.onEscape = { [weak self] in
            self?.dismiss()
        }
        previewPanel.onScrollZoom = { [weak model] delta in
            model?.adjustZoom(by: delta)
        }

        let containerView = NSView(
            frame: NSRect(origin: .zero, size: screenFrame.size)
        )
        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = true
        containerView.autoresizingMask = [.width, .height]

        // Keep the hosting view in an explicit frame-based AppKit container.
        // A hosting view directly attached to the borderless window can enter
        // a recursive AppKit/SwiftUI constraint invalidation loop while the
        // preview model changes during zoom or dismissal.
        contentView.translatesAutoresizingMaskIntoConstraints = true
        contentView.frame = containerView.bounds
        contentView.autoresizingMask = [.width, .height]
        containerView.addSubview(contentView)
        previewPanel.contentView = containerView

        panel = previewPanel
        self.model = model
        previewPanel.alphaValue = 0
        previewPanel.orderFrontRegardless()
        previewPanel.makeKey()
        fadeIn(previewPanel: previewPanel)
    }

    func dismiss() {
        let previewPanel = panel
        previewPanel?.onWindowClose = nil
        previewPanel?.onEscape = nil
        previewPanel?.onScrollZoom = nil
        panel = nil
        model = nil
        fadeOut(previewPanel: previewPanel)
    }

    private func fadeIn(previewPanel: FullscreenMediaPreviewPanel) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            previewPanel.animator().alphaValue = 1
        }
    }

    private func fadeOut(previewPanel: FullscreenMediaPreviewPanel?) {
        guard previewPanel != nil else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            previewPanel?.animator().alphaValue = 0
        } completionHandler: {
            previewPanel?.orderOut(nil)
            previewPanel?.close()
        }
    }
}

private final class FullscreenMediaPreviewPanel: NSPanel {
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
        if event.type == .scrollWheel,
           event.modifierFlags.contains(.command),
           abs(event.scrollingDeltaY) > 0.01
        {
            onScrollZoom?(event.scrollingDeltaY > 0 ? 0.1 : -0.1)
            return
        }
        super.sendEvent(event)
    }
}
