import AppKit

enum PreviewWindowSupport {
    static let titlebarHeight: CGFloat = 28
    static let screenInset: CGFloat = 80

    static func screenFrames() -> (screen: CGRect, visible: CGRect) {
        let screen = NSScreen.main?.frame ?? CGRect(
            origin: .zero,
            size: CGSize(width: 1200, height: 800)
        )
        return (screen, NSScreen.main?.visibleFrame ?? screen)
    }

    static func maximumContentSize(for screenFrame: CGRect) -> CGSize {
        CGSize(
            width: screenFrame.width - screenInset,
            height: screenFrame.height - screenInset - titlebarHeight
        )
    }

    static func centeredFrame(
        contentSize: CGSize,
        visibleFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: visibleFrame.midX - contentSize.width / 2,
            y: visibleFrame.midY - (contentSize.height + titlebarHeight) / 2,
            width: contentSize.width,
            height: contentSize.height
        )
    }

    static func configurePreviewPanel(_ panel: NSPanel, title: String) {
        panel.level = .screenSaver
        panel.animationBehavior = .none
        panel.alphaValue = 1
        panel.title = title
        panel.titleVisibility = .visible
        panel.titlebarAppearsTransparent = false
        panel.titlebarSeparatorStyle = .none
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.closeButton)?.isHidden = false
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = false
        panel.standardWindowButton(.zoomButton)?.isHidden = false
        panel.standardWindowButton(.zoomButton)?.isEnabled = true
    }

    static func configureDimmingPanel(_ panel: NSPanel, screenFrame: CGRect) {
        panel.level = .screenSaver
        panel.animationBehavior = .none
        panel.alphaValue = 1
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let overlayView = NSView(
            frame: NSRect(origin: .zero, size: screenFrame.size)
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
