import AppKit

@MainActor
final class JarvisMenuBarController: NSObject, NSMenuDelegate {
    static let shared = JarvisMenuBarController()
    static let menuBarTitle = "JARVIS"
    static let menuBarAutosaveName = NSStatusItem.AutosaveName(
        "com.jarvis.mac.primary-status-item"
    )

    private weak var app: AppModel?
    private var statusItem: NSStatusItem?
    private var appearanceObservation: NSKeyValueObservation?
    private let menu = NSMenu()
    private let screenshotMenuItem = NSMenuItem(
        title: "框选截图",
        action: #selector(captureScreenshot),
        keyEquivalent: ""
    )
    private let clipboardMenuItem = NSMenuItem(
        title: "打开剪贴板",
        action: #selector(openClipboardPanel),
        keyEquivalent: ""
    )

    deinit {
        appearanceObservation?.invalidate()
    }

    func bind(app: AppModel) {
        self.app = app
    }

    func install() {
        guard statusItem == nil else { return }

        guard NSApp.isRunning else {
            DispatchQueue.main.async { [weak self] in
                self?.install()
            }
            return
        }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = Self.menuBarAutosaveName
        if let button = statusItem.button {
            styleStatusItemButton(button)
        }
        statusItem.menu = menu
        statusItem.isVisible = true
        self.statusItem = statusItem

        appearanceObservation = NSApp.observe(
            \.effectiveAppearance,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, let button = self.statusItem?.button else { return }
                self.styleStatusItemButton(button)
            }
        }

        menu.delegate = self
        menu.autoenablesItems = false
        menu.addItem(
            NSMenuItem(
                title: "打开贾维斯",
                action: #selector(openMainWindow),
                keyEquivalent: ""
            )
        )
        menu.items.last?.target = self
        screenshotMenuItem.target = self
        menu.addItem(screenshotMenuItem)
        clipboardMenuItem.target = self
        menu.addItem(clipboardMenuItem)
        menu.addItem(.separator())
        for layout in WindowLayout.allCases {
            let item = NSMenuItem(
                title: layout.title,
                action: #selector(applyWindowLayout(_:)),
                keyEquivalent: layout.menuKeyEquivalent
            )
            item.target = self
            item.keyEquivalentModifierMask = WindowLayout.shortcutModifierFlags
            item.representedObject = layout.rawValue
            item.image = layout.menuIcon
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "退出贾维斯",
                action: #selector(terminate),
                keyEquivalent: "q"
            )
        )
        menu.items.last?.target = self
    }

    func menuWillOpen(_: NSMenu) {
        if let button = statusItem?.button {
            styleStatusItemButton(button)
        }
        guard let app else { return }
        screenshotMenuItem.title = "框选截图"
        configureMenuShortcut(screenshotMenuItem, with: app.screenshotShortcut)
        clipboardMenuItem.title = "打开剪贴板"
        configureMenuShortcut(clipboardMenuItem, with: app.clipboardShortcut)
    }

    private func configureMenuShortcut(_ item: NSMenuItem, with shortcut: ScreenshotShortcut) {
        item.keyEquivalent = shortcut.menuKeyEquivalent
        item.keyEquivalentModifierMask = shortcut.modifierFlags
    }

    private func styleStatusItemButton(_ button: NSStatusBarButton) {
        let menuBarFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let title = NSAttributedString(
            string: Self.menuBarTitle,
            attributes: [
                .font: menuBarFont,
                .foregroundColor: NSColor.white
            ]
        )

        // Set both the button and its cell. The status-bar cell can redraw
        // from its own attributed title after an appearance change.
        button.appearance = NSAppearance(named: .darkAqua)
        button.title = Self.menuBarTitle
        button.attributedTitle = title
        button.font = menuBarFont
        button.contentTintColor = .white
        button.cell?.font = menuBarFont
        button.cell?.backgroundStyle = .emphasized
        button.setAccessibilityLabel(Self.menuBarTitle)
        button.toolTip = Self.menuBarTitle
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

    @objc private func applyWindowLayout(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let layout = WindowLayout(rawValue: rawValue)
        else {
            return
        }
        app?.applyWindowLayout(layout)
    }

    @objc private func terminate() {
        NSApp.terminate(nil)
    }
}
