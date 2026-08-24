import AppKit

@MainActor
final class JarvisMenuBarController: NSObject, NSMenuDelegate {
    static let shared = JarvisMenuBarController()
    static let menuBarTitle = "JIAVIS"

    private weak var app: AppModel?
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let clipboardMenuItem = NSMenuItem(
        title: "打开剪贴板",
        action: #selector(openClipboardPanel),
        keyEquivalent: ""
    )
    private let statusMessageMenuItem = NSMenuItem(
        title: "系统就绪",
        action: nil,
        keyEquivalent: ""
    )

    func bind(app: AppModel) {
        self.app = app
    }

    func install() {
        guard statusItem == nil else { return }

        let statusItem = NSStatusBar.system.statusItem(withLength: 96)
        if let button = statusItem.button {
            button.title = Self.menuBarTitle
            button.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            button.contentTintColor = .labelColor
            button.setAccessibilityLabel(Self.menuBarTitle)
            button.toolTip = Self.menuBarTitle
        }
        statusItem.menu = menu
        statusItem.isVisible = true
        self.statusItem = statusItem

        menu.delegate = self
        menu.autoenablesItems = false
        menu.addItem(
            NSMenuItem(
                title: "框选截图",
                action: #selector(captureScreenshot),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "打开贾维斯",
                action: #selector(openMainWindow),
                keyEquivalent: ""
            )
        )
        menu.addItem(clipboardMenuItem)
        menu.addItem(.separator())
        statusMessageMenuItem.isEnabled = false
        menu.addItem(statusMessageMenuItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "退出贾维斯",
                action: #selector(terminate),
                keyEquivalent: "q"
            )
        )
    }

    func menuWillOpen(_: NSMenu) {
        guard let app else { return }
        clipboardMenuItem.title = "打开剪贴板（\(app.clipboardShortcut.displayString)）"
        statusMessageMenuItem.title = app.statusMessage
    }

    @objc private func captureScreenshot() {
        app?.captureScreenshot()
    }

    @objc private func openMainWindow() {
        guard let app else { return }
        app.selectedSection = .overview
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { !$0.isMiniaturized })?.makeKeyAndOrderFront(nil)
    }

    @objc private func openClipboardPanel() {
        app?.showClipboardPanel()
    }

    @objc private func terminate() {
        NSApp.terminate(nil)
    }
}
