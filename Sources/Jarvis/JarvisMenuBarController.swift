import AppKit

/// Renders the menu bar title as a template image so AppKit can invert it
/// against the wallpaper, independent of the app's light/dark setting.
enum JarvisMenuBarTitleImage {
    static let title = "JARVIS"
    static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let horizontalPadding: CGFloat = 6

    static func make(
        title: String = title,
        font: NSFont = font,
        thickness: CGFloat = NSStatusBar.system.thickness
    ) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let textSize = (title as NSString).size(withAttributes: attributes)
        let size = NSSize(
            width: ceil(textSize.width) + horizontalPadding * 2,
            height: ceil(max(textSize.height, thickness))
        )
        let image = NSImage(size: size)
        for scale in [1.0, 2.0] as [CGFloat] {
            guard let representation = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int((size.width * scale).rounded()),
                pixelsHigh: Int((size.height * scale).rounded()),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ), let context = NSGraphicsContext(bitmapImageRep: representation) else {
                continue
            }
            representation.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            // Center the cap-height so all-caps "JARVIS" sits on the extra midline.
            let textRect = NSRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - font.capHeight) / 2 - font.descender,
                width: textSize.width,
                height: textSize.height
            )
            (title as NSString).draw(in: textRect, withAttributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(representation)
        }
        image.isTemplate = true
        return image
    }

    /// Status-item views are not flipped: (0, 0) is the bottom-left, which is
    /// where system extras attach their menus.
    static func menuOrigin(in view: NSView) -> NSPoint {
        view.isFlipped ? NSPoint(x: 0, y: view.bounds.maxY) : .zero
    }

    static func tintColor(for view: NSView) -> NSColor {
        let appearance = view.window?.effectiveAppearance ?? view.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
    }
}

@MainActor
final class JarvisMenuBarController: NSObject, NSMenuDelegate {
    static let shared = JarvisMenuBarController()
    static let menuBarTitle = JarvisMenuBarTitleImage.title
    static let menuBarAutosaveName = NSStatusItem.AutosaveName(
        "com.jarvis.mac.primary-status-item"
    )
    /// Relative extras ordering. System items sit around 170-360; third-party
    /// extras around 600+. Too-small values park Jarvis under the clock.
    static let menuBarPreferredPosition: Double = 720

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

    func bind(app: AppModel) {
        self.app = app
    }

    @MainActor
    func configuredMenuForTesting() -> NSMenu {
        configureMenuIfNeeded()
        return menu
    }

    func install() {
        NSLog("Jarvis menu bar install entered isRunning=\(NSApp.isRunning) hasStatusItem=\(statusItem != nil)")
        guard statusItem == nil else { return }

        guard NSApp.isRunning else {
            DispatchQueue.main.async { [weak self] in
                self?.install()
            }
            return
        }

        configureMenuIfNeeded()
        persistPreferredPosition()
        let repair = JarvisControlCenterMenuBarRepair.repairSystemPreferencesIfNeeded()
        let delay: TimeInterval = repair.didChange ? 0.8 : 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.createStatusItemIfNeeded()
        }
    }

    private func persistPreferredPosition() {
        let defaults = UserDefaults.standard
        defaults.set(Self.menuBarPreferredPosition, forKey: "NSStatusItem Preferred Position Item-0")
        defaults.set(
            Self.menuBarPreferredPosition,
            forKey: "NSStatusItem Preferred Position \(Self.menuBarAutosaveName)"
        )
        defaults.set(true, forKey: "NSStatusItem VisibleCC Item-0")
        defaults.set(true, forKey: "NSStatusItem Visible \(Self.menuBarAutosaveName)")
    }

    private func createStatusItemIfNeeded() {
        guard statusItem == nil else { return }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = Self.menuBarAutosaveName
        // Publish the item before styling it. `styleStatusItemButton` updates
        // the item's length and must not run while the property is still nil.
        self.statusItem = statusItem
        if let button = statusItem.button {
            styleStatusItemButton(button)
            // Pop the menu ourselves. Assigning `statusItem.menu` lets
            // Control Center host it, and Tahoe then drops item actions.
            button.target = self
            button.action = #selector(showMenu(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            observeButtonAppearance(button)
        }
        statusItem.isVisible = true
        NSLog("Jarvis menu bar status item created button=\(statusItem.button != nil)")
    }

    private func observeButtonAppearance(_ button: NSStatusBarButton) {
        appearanceObservation?.invalidate()
        appearanceObservation = button.observe(
            \.effectiveAppearance,
            options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, let button = self.statusItem?.button else { return }
                self.styleStatusItemButton(button)
            }
        }
    }

    @objc private func showMenu(_: Any?) {
        guard let button = statusItem?.button else { return }
        // Do not activate the app: that would order the main window front.
        styleStatusItemButton(button)
        refreshDynamicMenuItems()
        button.highlight(true)
        menu.popUp(
            positioning: nil,
            at: JarvisMenuBarTitleImage.menuOrigin(in: button),
            in: button
        )
        button.highlight(false)
    }

    private func styleStatusItemButton(_ button: NSStatusBarButton) {
        let image = JarvisMenuBarTitleImage.make()
        button.image = image
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        // Tint from the extra's appearance (wallpaper), not the app theme.
        button.contentTintColor = JarvisMenuBarTitleImage.tintColor(for: button)
        button.setAccessibilityLabel(Self.menuBarTitle)
        button.toolTip = Self.menuBarTitle
        statusItem?.length = image.size.width
    }

    private func configureMenuIfNeeded() {
        guard !menuConfigured else { return }
        menuConfigured = true
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
        enableMenuItems()
    }

    func menuWillOpen(_: NSMenu) {
        refreshDynamicMenuItems()
    }

    private func refreshDynamicMenuItems() {
        enableMenuItems()
        guard let app else { return }
        screenshotMenuItem.title = "框选截图"
        configureMenuShortcut(screenshotMenuItem, with: app.screenshotShortcut)
        clipboardMenuItem.title = "打开剪贴板"
        configureMenuShortcut(clipboardMenuItem, with: app.clipboardShortcut)
    }

    private func enableMenuItems() {
        for item in menu.items where !item.isSeparatorItem {
            item.isEnabled = true
            // Keep every action on the controller. Do not let AppKit resolve
            // a nil/stale target through the responder chain of the detached
            // pop-up menu.
            item.target = self
        }
    }

    private func configureMenuShortcut(_ item: NSMenuItem, with shortcut: ScreenshotShortcut) {
        item.keyEquivalent = shortcut.menuKeyEquivalent
        item.keyEquivalentModifierMask = shortcut.modifierFlags
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
