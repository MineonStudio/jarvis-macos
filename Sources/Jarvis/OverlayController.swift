import AppKit
import SwiftUI

@MainActor
final class OverlayController {
    private var panel: NSPanel?

    func show(text: String) {
        let view = FloatingTranslationView(text: text) { [weak self] in
            self?.panel?.close()
        }

        if panel == nil {
            let newPanel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 330),
                styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.level = .floating
            newPanel.isMovableByWindowBackground = true
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newPanel.titleVisibility = .hidden
            newPanel.titlebarAppearsTransparent = true
            newPanel.isReleasedWhenClosed = false
            panel = newPanel
        }

        panel?.contentView = NSHostingView(rootView: view)
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
