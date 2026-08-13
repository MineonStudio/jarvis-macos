import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI

@MainActor
final class ClipboardPanelController: NSObject, NSWindowDelegate {
    private weak var app: AppModel?
    private var panel: NSPanel?
    private var previousApplication: NSRunningApplication?
    private var lastExternalApplication: NSRunningApplication?
    private var keyMonitor: Any?
    private var applicationObserver: Any?
    private var postEventPermissionTask: Task<Void, Never>?

    func prepare(app: AppModel) {
        self.app = app
        guard applicationObserver == nil else { return }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != currentPID {
            lastExternalApplication = frontmost
        }
        applicationObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  activated.processIdentifier != currentPID,
                  !activated.isTerminated else { return }
            Task { @MainActor [weak self] in
                self?.lastExternalApplication = activated
            }
        }
    }

    func show(app: AppModel) {
        self.app = app
        if panel == nil {
            makePanel(app: app)
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApplication = [frontmost, lastExternalApplication]
            .compactMap { $0 }
            .first(where: { $0.processIdentifier != currentPID && !$0.isTerminated })

        guard let panel else { return }
        if !panel.isVisible {
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func close() {
        postEventPermissionTask?.cancel()
        postEventPermissionTask = nil
        panel?.orderOut(nil)
        previousApplication = nil
        removeKeyMonitor()
    }

    func closeAndPaste() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let target = [
            previousApplication,
            lastExternalApplication,
            NSWorkspace.shared.frontmostApplication
        ]
        .compactMap { $0 }
        .first(where: { $0.processIdentifier != currentPID && !$0.isTerminated })

        guard let target else {
            app?.statusMessage = "没有找到可导入的上一个应用"
            return
        }

        // Writing to the pasteboard itself does not require Accessibility, but
        // the synthetic Command-V that makes this a one-click workflow does.
        // The native request is asynchronous, so do not immediately treat its
        // initial false result as a denial.
        guard !Self.hasPostEventAccess else {
            finishPaste(to: target)
            return
        }

        app?.statusMessage = "请在 macOS 系统弹窗中允许贾维斯控制其他 App…"
        // Trigger the native Accessibility prompt. The result is still
        // asynchronous, so the task below continues polling until the user
        // finishes the macOS permission flow.
        _ = Self.requestPostEventAccess()
        postEventPermissionTask?.cancel()
        postEventPermissionTask = Task { @MainActor [weak self] in
            for _ in 0..<80 {
                guard !Task.isCancelled else { return }
                if Self.hasPostEventAccess {
                    self?.postEventPermissionTask = nil
                    self?.finishPaste(to: target)
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            self?.postEventPermissionTask = nil
            self?.app?.statusMessage = "未获得控制其他 App 的权限，请在系统设置中允许贾维斯后重试"
        }
    }

    private func finishPaste(to target: NSRunningApplication) {
        postEventPermissionTask?.cancel()
        postEventPermissionTask = nil
        panel?.orderOut(nil)
        previousApplication = nil
        removeKeyMonitor()

        target.activate(options: [.activateAllWindows])
        let targetPID = target.processIdentifier
        Task { @MainActor in
            // Activation is asynchronous. Sending Command-V immediately can
            // land in Jarvis or in the window that was active before the
            // target app finishes restoring its key window.
            for _ in 0..<20 {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID {
                    Self.sendPasteShortcut(to: targetPID)
                    return
                }
                target.activate(options: [.activateAllWindows])
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            Self.sendPasteShortcut(to: targetPID)
        }
        let appName = target.localizedName ?? "上一个应用"
        app?.statusMessage = "已向 \(appName) 发送导入指令"
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

    private static func sendPasteShortcut(to processID: pid_t) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyCode: CGKeyCode = 9 // V
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        if let keyDown {
            keyDown.postToPid(processID)
        }
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = .maskCommand
        if let keyUp {
            keyUp.postToPid(processID)
        }
    }

    private static var hasPostEventAccess: Bool {
        CGPreflightPostEventAccess() || AXIsProcessTrusted()
    }

    private static func requestPostEventAccess() -> Bool {
        if hasPostEventAccess { return true }

        // Ask through the Accessibility API as well. This is the native
        // macOS permission flow for controlling another app and is what makes
        // the request appear in System Settings > Privacy & Security.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        _ = CGRequestPostEventAccess()
        return hasPostEventAccess
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        postEventPermissionTask?.cancel()
        postEventPermissionTask = nil
        sender.orderOut(nil)
        previousApplication = nil
        removeKeyMonitor()
        return false
    }
}
