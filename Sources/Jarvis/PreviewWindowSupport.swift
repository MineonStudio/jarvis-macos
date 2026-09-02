import AppKit

enum PreviewWindowSupport {
    static let titlebarHeight: CGFloat = 28
    static let screenInset: CGFloat = 80

    static func fittedFrame(for imageSize: CGSize, in visibleFrame: CGRect) -> CGRect {
        let inset = visibleFrame.insetBy(dx: 32, dy: 32)
        let scale = min(
            1,
            inset.width / max(imageSize.width, 1),
            inset.height / max(imageSize.height, 1)
        )
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: inset.midX - size.width / 2,
            y: inset.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    static func screenFrames() -> (screen: CGRect, visible: CGRect) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let frame = screen?.frame ?? CGRect(
            origin: .zero,
            size: CGSize(width: 1200, height: 800)
        )
        return (frame, screen?.visibleFrame ?? frame)
    }

    static func maximumContentSize(
        for screenFrame: CGRect,
        topChromeHeight: CGFloat = PreviewWindowSupport.titlebarHeight
    ) -> CGSize {
        CGSize(
            width: screenFrame.width - screenInset,
            height: screenFrame.height - screenInset - topChromeHeight
        )
    }

    static func centeredFrame(
        contentSize: CGSize,
        visibleFrame: CGRect,
        topChromeHeight: CGFloat = PreviewWindowSupport.titlebarHeight
    ) -> CGRect {
        CGRect(
            x: visibleFrame.midX - contentSize.width / 2,
            y: visibleFrame.midY - (contentSize.height + topChromeHeight) / 2,
            width: contentSize.width,
            height: contentSize.height
        )
    }

    static func configurePreviewPanel(_ panel: NSPanel, title: String) {
        configurePreviewPanelBase(panel)
        panel.title = title
        panel.titleVisibility = .visible
        panel.titlebarAppearsTransparent = false
        panel.titlebarSeparatorStyle = .none
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isHidden = false
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = false
        panel.standardWindowButton(.zoomButton)?.isHidden = false
        panel.standardWindowButton(.zoomButton)?.isEnabled = true
    }

    static func configureBorderlessPreviewPanel(_ panel: NSPanel) {
        configurePreviewPanelBase(panel)
        panel.styleMask = panel.styleMask
            .subtracting([.titled, .closable, .miniaturizable, .resizable])
            .union(.borderless)
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
    }

    private static func configurePreviewPanelBase(_ panel: NSPanel) {
        panel.level = .screenSaver
        panel.animationBehavior = .none
        panel.alphaValue = 1
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    static func configureDimmingPanel(
        _ panel: NSPanel,
        screenFrame: CGRect,
        onClick: (() -> Void)? = nil
    ) {
        panel.level = .screenSaver
        panel.animationBehavior = .none
        panel.alphaValue = 1
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let overlayView = PreviewDimmingOverlayView(
            frame: NSRect(origin: .zero, size: screenFrame.size),
            onClick: onClick
        )
        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = NSColor.black
            .withAlphaComponent(0.58)
            .cgColor
        overlayView.autoresizingMask = [.width, .height]
        panel.contentView = overlayView
        panel.setFrame(screenFrame, display: false)
    }
}

private final class PreviewDimmingOverlayView: NSView {
    let onClick: (() -> Void)?
    private var isTrackingClick = false

    init(frame: NSRect, onClick: (() -> Void)?) {
        self.onClick = onClick
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_: NSPoint) -> NSView? {
        self
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with _: NSEvent) {
        isTrackingClick = true
    }

    override func mouseUp(with _: NSEvent) {
        defer { isTrackingClick = false }
        guard isTrackingClick else { return }
        onClick?()
    }

    override func otherMouseDown(with _: NSEvent) {}

    override func otherMouseUp(with _: NSEvent) {}
}
