import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class ClipboardPanelController: NSObject, NSWindowDelegate {
    private weak var app: AppModel?
    private var panel: NSPanel?
    private var previousApplication: NSRunningApplication?
    private var keyMonitor: Any?

    func prepare(app: AppModel) {
        self.app = app
    }

    func show(app: AppModel) {
        self.app = app
        if panel == nil {
            makePanel(app: app)
        }

        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost != NSRunningApplication.current {
            previousApplication = frontmost
        }

        guard let panel else { return }
        if !panel.isVisible {
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func close() {
        panel?.orderOut(nil)
        removeKeyMonitor()
    }

    func closeAndPaste() {
        let target = previousApplication

        // Writing to the pasteboard itself does not require Accessibility, but
        // the synthetic Command-V that makes this a one-click workflow does.
        // Keep the panel open when access is not available yet, so the user can
        // try again after granting it in System Settings.
        guard Self.requestPostEventAccess() else {
            app?.statusMessage = "请允许贾维斯控制其他 App 后再使用一键导入"
            return
        }

        panel?.orderOut(nil)
        previousApplication = nil
        removeKeyMonitor()

        guard let target else { return }
        target.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Self.sendPasteShortcut()
        }
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

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isKeyWindow == true else { return event }

            if event.keyCode == 36 || event.keyCode == 76 {
                guard let app = self.app,
                      let selectedID = app.clipboardPanelSelectionID,
                      let item = app.clipboardItems.first(where: { $0.id == selectedID }) else {
                    return event
                }
                app.quickPasteClipboard(item)
                return nil
            }

            if event.keyCode == 53 {
                self.close()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private static func sendPasteShortcut() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyCode: CGKeyCode = 9 // V
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }

    private static func requestPostEventAccess() -> Bool {
        guard !CGPreflightPostEventAccess() else { return true }
        _ = CGRequestPostEventAccess()
        return CGPreflightPostEventAccess()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        previousApplication = nil
        removeKeyMonitor()
        return false
    }
}
