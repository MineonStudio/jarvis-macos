import AppKit
import SwiftUI

@MainActor
final class ClipboardPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?

    func show(app: AppModel) {
        if panel == nil {
            makePanel(app: app)
        }

        guard let panel else { return }
        if !panel.isVisible {
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel(app: AppModel) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "剪贴板"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        panel.minSize = NSSize(width: 640, height: 420)
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: ClipboardPanelView()
                .environmentObject(app)
        )
        self.panel = panel
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
