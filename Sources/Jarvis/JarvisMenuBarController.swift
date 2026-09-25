import AppKit

@MainActor
final class JarvisMenuBarController: NSObject, NSMenuDelegate {
    static let shared = JarvisMenuBarController()
    static let menuBarTitle = "JARVIS"
    static let menuBarIconPointSize = NSSize(width: 18, height: 18)
    static let menuBarAutosaveName = NSStatusItem.AutosaveName(
        "\(JarvisAppIdentity.bundleIdentifier).primary-status-item"
    )

    private var app: AppModel?
    private var openMainWindowAction: (() -> Void)?
    private var statusItem: NSStatusItem?
    private var appearanceObservation: NSKeyValueObservation?
    /// The appearance the status item was last styled for. Assigning a status
    /// item button's image, title, and cell makes AppKit re-notify
    /// `effectiveAppearance`, so an observer that always restyles feeds itself
    /// — measured at roughly 2,600 notifications a second, which pinned the
    /// main thread at a full core and starved everything else, typing included.
    private var lastStyledAppearanceName: NSAppearance.Name?
    private var menuConfigured = false
    private var isMeetingRecording = false
    private var meetingElapsed: TimeInterval = 0
    private var meetingModelsReady = true
    private var lastRenderedMeetingElapsedSeconds = -1
    private var lastRenderedRecording = false
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
    private let meetingMenuItem = NSMenuItem(
        title: "开始录制会议",
        action: #selector(toggleMeetingRecording),
        keyEquivalent: ""
    )

    deinit {
        appearanceObservation?.invalidate()
    }

    func bind(app: AppModel) {
        self.app = app
        updateMeetingRecordingState(
            isRecording: app.meetingCurrentRecordingID != nil,
            elapsed: app.meetingElapsed,
            modelsReady: app.meetingModelsReady
        )
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
            refreshStatusItemPresentation(button)
            appearanceObservation = button.observe(
                \.effectiveAppearance,
                options: [.initial, .new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.refreshStatusItemPresentationForAppearanceChange()
                }
            }
        }
    }

    func updateMeetingRecordingState(
        isRecording: Bool,
        elapsed: TimeInterval,
        modelsReady: Bool = true
    ) {
        isMeetingRecording = isRecording
        meetingElapsed = max(0, elapsed)
        meetingModelsReady = modelsReady
        let seconds = Int(meetingElapsed.rounded(.down))
        let shouldRefreshImage = isRecording != lastRenderedRecording
            || (isRecording && seconds != lastRenderedMeetingElapsedSeconds)
        if shouldRefreshImage {
            lastRenderedRecording = isRecording
            lastRenderedMeetingElapsedSeconds = seconds
            refreshStatusItemPresentation()
        }
        updateMeetingMenuItem()
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
        updateMeetingMenuItem()
        configureMenuShortcut(meetingMenuItem, with: app.meetingShortcut)
        for item in menu.items {
            guard let rawValue = item.representedObject as? String,
                  let layout = WindowLayout(rawValue: rawValue)
            else {
                continue
            }
            configureMenuShortcut(item, with: app.windowLayoutShortcut(for: layout))
        }
        for item in menu.items where !item.isSeparatorItem {
            item.isEnabled = true
        }
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
        addMenuItem(meetingMenuItem)
        menu.addItem(.separator())

        for layout in WindowLayout.allCases {
            let shortcut = app?.windowLayoutShortcut(for: layout) ?? layout.defaultShortcut
            let item = NSMenuItem(
                title: layout.title,
                action: #selector(applyWindowLayout(_:)),
                keyEquivalent: shortcut.menuKeyEquivalent
            )
            item.keyEquivalentModifierMask = shortcut.modifierFlags
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
        button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        button.cell?.font = button.font
        button.wantsLayer = true
        button.layer?.backgroundColor = nil
        button.layer?.cornerRadius = 0
        button.layer?.masksToBounds = false

        button.image = Self.makeMenuBarIcon()
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        (button.cell as? NSButtonCell)?.attributedTitle = button.attributedTitle

        button.setAccessibilityLabel(Self.menuBarTitle)
    }

    /// Restyles only when the menu bar appearance really changed. The
    /// notifications themselves arrive in a loop, so comparing against the
    /// appearance the button was last drawn for is what breaks it.
    private func refreshStatusItemPresentationForAppearanceChange() {
        guard let button = statusItem?.button else { return }
        let appearanceName = button.effectiveAppearance.name
        guard appearanceName != lastStyledAppearanceName else { return }
        lastStyledAppearanceName = appearanceName
        refreshStatusItemPresentation(button)
    }

    private func refreshStatusItemPresentation(_ button: NSStatusBarButton? = nil) {
        guard let button = button ?? statusItem?.button else { return }
        if isMeetingRecording {
            button.image = MeetingRecordingStyle.makeStatusBarImage(for: meetingElapsed)
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.contentTintColor = nil
            button.isBordered = false
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            button.wantsLayer = true
            button.layer?.backgroundColor = nil
            button.layer?.cornerRadius = 0
            button.layer?.masksToBounds = false
            button.setAccessibilityLabel(
                "停止录制，已录制 \(MeetingRecordingStyle.formatDuration(meetingElapsed))"
            )
        } else {
            styleStatusItemButton(button)
        }
    }

    private func updateMeetingMenuItem() {
        meetingMenuItem.title = isMeetingRecording
            ? MeetingRecordingStyle.stopActionTitle(for: meetingElapsed)
            : "开始录制会议"
        meetingMenuItem.isEnabled = isMeetingRecording || meetingModelsReady
    }

    static func makeMenuBarIcon() -> NSImage {
        makeTemplateIcon(
            from: JarvisMascotVector.makeMenuBarImage(),
            pointSize: menuBarIconPointSize.width
        )
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

    func reopenMainWindow() {
        openMainWindow()
    }

    @objc private func openMainWindow() {
        app?.selectedSection = .home
        NSApp.activate(ignoringOtherApps: true)

        let mainWindow = NSApp.windows.first { window in
            window.identifier?.rawValue == JarvisAppIdentity.mainWindowSceneID
                || window.frameAutosaveName == JarvisMainWindowController.frameAutosaveName
        }
        if let mainWindow, mainWindow.isMiniaturized {
            mainWindow.deminiaturize(nil)
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }
        if let mainWindow, mainWindow.isVisible {
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }

        if let window = NSApp.windows.first(where: { window in
            window.canBecomeKey && window.isVisible && !window.isMiniaturized
                && !(window is NSPanel)
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

    @objc private func toggleMeetingRecording() {
        app?.toggleMeetingRecording()
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
