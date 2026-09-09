import AppKit
import SwiftUI

@MainActor
final class ClipboardPanelController: NSObject, NSWindowDelegate {
    private static var minimumPanelSize: NSSize {
        NSSize(
            width: JarvisWindowLayoutMetrics.clipboardPanelMinimumWidth,
            height: JarvisWindowLayoutMetrics.clipboardPanelMinimumHeight
        )
    }

    private static var defaultPanelSize: NSSize {
        NSSize(
            width: max(1040, minimumPanelSize.width),
            height: 600
        )
    }

    private var panel: NSPanel?

    func show(app: AppModel) {
        if panel == nil {
            makePanel(app: app)
        }

        guard let panel else { return }
        if !panel.isVisible {
            panel.center()
        }
        // F2 is a transient utility surface. Keep the current app in the
        // foreground while allowing this panel to receive keyboard input.
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel(app: AppModel) {
        let panel = NSPanel(
            contentRect: NSRect(
                origin: .zero,
                size: Self.defaultPanelSize
            ),
            styleMask: [
                .titled,
                .closable,
                .resizable,
                .fullSizeContentView,
                .nonactivatingPanel
            ],
            backing: .buffered,
            defer: false
        )
        panel.title = "剪贴板"
        JarvisWindowAppearance.configureTransparentTitlebar(for: panel)
        // Keep the native titlebar as the only window drag surface. Content
        // owns all body gestures, including clipboard card export drags.
        panel.isMovableByWindowBackground = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        panel.minSize = Self.minimumPanelSize
        panel.delegate = self
        let hostingView = NSHostingView(
            rootView: ClipboardPanelView()
                .environment(app)
                .tint(.accentColor)
        )
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        self.panel = panel
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
