import AppKit

@MainActor
final class JarvisMenuBarController: NSObject, NSMenuDelegate {
    static let shared = JarvisMenuBarController()
    static let menuBarTitle = "JARVIS"
    static let menuBarIconResourceName = "JarvisMenuBarIcon"
    static let menuBarIconFileExtension = "png"
    static let menuBarIconPointSize = NSSize(width: 18, height: 18)
    static let menuBarAutosaveName = NSStatusItem.AutosaveName(
        "\(JarvisAppIdentity.bundleIdentifier).primary-status-item"
    )

    private var app: AppModel?
    private var openMainWindowAction: (() -> Void)?
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

    func bind(openMainWindowAction: @escaping () -> Void) {
        self.openMainWindowAction = openMainWindowAction
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
        // Leave the tint to the status bar. With a template image, AppKit
        // derives the foreground from the status item's current menu-bar
        // material, including wallpaper-driven contrast changes.
        button.contentTintColor = nil
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

        return makeTemplateIcon(from: image, pointSize: menuBarIconPointSize.width)
    }

    private static func makeTemplateIcon(from base: NSImage, pointSize: CGFloat) -> NSImage {
        guard let representation = rasterize(base, pointSize: pointSize) else {
            let fallback = base.copy() as? NSImage ?? base
            fallback.size = NSSize(width: pointSize, height: pointSize)
            fallback.isTemplate = true
            return fallback
        }

        // Preserve the source alpha as the shape and discard its fixed RGB
        // color. AppKit then applies the correct light/dark menu-bar tint.
        monochromeMask(representation)
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        image.addRepresentation(representation)
        image.isTemplate = true
        return image
    }

    private static func rasterize(_ base: NSImage, pointSize: CGFloat) -> NSBitmapImageRep? {
        let scale = max(NSScreen.main?.backingScaleFactor ?? 2, 2)
        let pixelSize = Int((pointSize * scale).rounded())
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        representation.size = NSSize(width: pointSize, height: pointSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: pointSize, height: pointSize).fill()
        base.draw(
            in: NSRect(x: 0, y: 0, width: pointSize, height: pointSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        return representation
    }

    private static func monochromeMask(_ representation: NSBitmapImageRep) {
        guard let data = representation.bitmapData else { return }
        let bytesPerPixel = max(representation.bitsPerPixel / 8, 4)
        for y in 0 ..< representation.pixelsHigh {
            let row = data.advanced(by: y * representation.bytesPerRow)
            for x in 0 ..< representation.pixelsWide {
                let pixel = row.advanced(by: x * bytesPerPixel)
                let alpha = pixel[3]
                pixel[0] = 0
                pixel[1] = 0
                pixel[2] = 0
                pixel[3] = alpha
            }
        }
    }

    @objc private func captureScreenshot() {
        app?.captureScreenshot()
    }

    @objc private func openMainWindow() {
        app?.selectedSection = .overview
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { window in
            window.canBecomeKey && window.isVisible && !window.isMiniaturized
        }) {
            window.makeKeyAndOrderFront(nil)
            return
        }

        if let window = NSApp.windows.first(where: { window in
            window.canBecomeKey && window.isMiniaturized
        }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            return
        }

        // WindowGroup removes its NSWindow after the user closes the last
        // window. Recreate the scene through SwiftUI instead of trying to
        // front a stale AppKit window reference.
        openMainWindowAction?()
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
