import AppKit

@MainActor
final class JarvisMenuBarController: NSObject, NSMenuDelegate {
    static let shared = JarvisMenuBarController()
    static let menuBarTitle = "JARVIS"
    static let menuBarIconResourceName = "JarvisMenuBarIcon"
    static let menuBarIconFileExtension = "png"
    static let menuBarIconTintColor = NSColor.white
    static let menuBarIconPointSize = NSSize(width: 18, height: 18)
    static let menuBarAutosaveName = NSStatusItem.AutosaveName(
        "com.jarvis.mac.primary-status-item"
    )

    private var app: AppModel?
    private var statusItem: NSStatusItem?
    private var appearanceObservation: NSKeyValueObservation?
    private var menuConfigured = false
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

        configureMenuIfNeeded()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = Self.menuBarAutosaveName
        self.statusItem = statusItem
        statusItem.menu = menu
        statusItem.isVisible = true

        if let button = statusItem.button {
            styleStatusItemButton(button)
            appearanceObservation = button.observe(
                \.effectiveAppearance,
                options: [.initial, .new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, let button = self.statusItem?.button else { return }
                    self.styleStatusItemButton(button)
                }
            }
        }
    }

    func configuredMenuForTesting() -> NSMenu {
        configureMenuIfNeeded()
        return menu
    }

    func menuWillOpen(_: NSMenu) {
        guard let app else { return }
        screenshotMenuItem.title = "框选截图"
        configureMenuShortcut(screenshotMenuItem, with: app.screenshotShortcut)
        clipboardMenuItem.title = "打开剪贴板"
        configureMenuShortcut(clipboardMenuItem, with: app.clipboardShortcut)
    }

    private func configureMenuIfNeeded() {
        guard !menuConfigured else { return }
        menuConfigured = true
        menu.delegate = self
        menu.autoenablesItems = false

        addMenuItem(
            title: "打开贾维斯",
            action: #selector(openMainWindow)
        )
        addMenuItem(screenshotMenuItem)
        addMenuItem(clipboardMenuItem)
        menu.addItem(.separator())

        for layout in WindowLayout.allCases {
            let item = NSMenuItem(
                title: layout.title,
                action: #selector(applyWindowLayout(_:)),
                keyEquivalent: layout.menuKeyEquivalent
            )
            item.keyEquivalentModifierMask = layout.shortcut.modifierFlags
            item.representedObject = layout.rawValue
            item.image = layout.menuIcon
            addMenuItem(item)
        }

        menu.addItem(.separator())
        addMenuItem(
            title: "退出贾维斯",
            action: #selector(terminate),
            keyEquivalent: "q"
        )
    }

    private func addMenuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) {
        addMenuItem(NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent))
    }

    private func addMenuItem(_ item: NSMenuItem) {
        item.target = self
        item.isEnabled = true
        menu.addItem(item)
    }

    private func configureMenuShortcut(_ item: NSMenuItem, with shortcut: ScreenshotShortcut) {
        item.keyEquivalent = shortcut.menuKeyEquivalent
        item.keyEquivalentModifierMask = shortcut.modifierFlags
    }

    private func styleStatusItemButton(_ button: NSStatusBarButton) {
        button.contentTintColor = Self.menuBarIconTintColor
        button.isBordered = false

        if let icon = Self.makeMenuBarIcon() {
            button.image = icon
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
        } else {
            // Keep the menu discoverable if a damaged bundle is missing the icon.
            button.title = Self.menuBarTitle
        }

        button.setAccessibilityLabel(Self.menuBarTitle)
        button.toolTip = Self.menuBarTitle
    }

    private static func makeMenuBarIcon() -> NSImage? {
        guard let url = Bundle.main.url(
            forResource: menuBarIconResourceName,
            withExtension: menuBarIconFileExtension
        ),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        image.isTemplate = false
        image.size = Self.menuBarIconPointSize
        return image
    }

    @objc private func captureScreenshot() {
        app?.captureScreenshot()
    }

    @objc private func openMainWindow() {
        app?.selectedSection = .overview
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { window in
            window.canBecomeKey && !window.isMiniaturized
        }) ?? NSApp.windows.first {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        }
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
