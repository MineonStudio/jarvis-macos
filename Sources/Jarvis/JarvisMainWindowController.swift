import AppKit
import ObjectiveC
import SwiftUI

@MainActor
enum JarvisWindowAppearance {
    static func configure(for window: NSWindow) {
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .textBackgroundColor
        window.sharingType = .readOnly
    }

    static func configureTransparentTitlebar(for window: NSWindow) {
        configure(for: window)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
    }
}

enum JarvisWindowLayoutMetrics {
    /// A little extra room absorbs the split-view divider and fractional
    /// layout rounding, so the last card and its hover controls never touch
    /// the window edge.
    static let contentSafetyMargin: CGFloat = 8
    static let splitViewDividerAllowance: CGFloat = 1
    static let clipboardPanelHorizontalPadding: CGFloat = 40
    static let clipboardPanelTopPadding: CGFloat = 32
    static let clipboardPanelBottomPadding: CGFloat = 20
    static let clipboardPanelFooterHeight: CGFloat = 12
    static let clipboardPanelDividerHeight: CGFloat = 5
    static let clipboardMainCompactFilterBarHeight: CGFloat =
        HistoryGridMetrics.topControlHeight * 3
            + HistoryGridMetrics.clipboardFilterToGridSpacing * 2
    static let clipboardPanelCompactFilterBarHeight: CGFloat =
        HistoryGridMetrics.topControlHeight * 2
            + HistoryGridMetrics.clipboardFilterToGridSpacing
    static let contentBodyTopSpacing: CGFloat = JarvisMetrics.shellContentSpacing
    static let emptyStateMinimumHeight: CGFloat = 190

    private static var clipboardMinimumRowHeight: CGFloat {
        HistoryGridMetrics.clipboardCardHeight
            + HistoryGridMetrics.clipboardContentSpacing
            + HistoryGridMetrics.clipboardMetadataHeight
    }

    private static var clipboardMinimumContentHeight: CGFloat {
        max(clipboardMinimumRowHeight, emptyStateMinimumHeight)
    }

    static var mainWindowMinimumWidth: CGFloat {
        let clipboardDetailWidth = max(
            HistoryGridMetrics.clipboardCardWidth,
            HistoryGridMetrics.clipboardSearchFieldWidth
        ) + (JarvisMetrics.pageInset * 2)
        let windowLayoutDetailWidth =
            WindowLayoutDisplayMetrics.minimumGridWidth + (JarvisMetrics.pageInset * 2)
        let detailWidth = max(
            clipboardDetailWidth,
            windowLayoutDetailWidth,
            JarvisWebPlatformLayoutMetrics.minimumTopBarWidth
        )
        return ceil(
            JarvisMetrics.sidebarMinimumWidth
                + splitViewDividerAllowance
                + (JarvisMetrics.shellHorizontalPadding * 2)
                + detailWidth
                + contentSafetyMargin
        )
    }

    static var mainWindowMinimumHeight: CGFloat {
        let clipboardPageHeight = clipboardMainCompactFilterBarHeight
            + HistoryGridMetrics.imageSpacing
            + clipboardMinimumContentHeight
            + (JarvisMetrics.pageInset * 2)
        return ceil(
            contentBodyTopSpacing
                + (JarvisMetrics.shellVerticalPadding * 2)
                + clipboardPageHeight
                + contentSafetyMargin
        )
    }

    static var clipboardPanelMinimumWidth: CGFloat {
        let contentWidth = max(
            HistoryGridMetrics.clipboardCardWidth,
            HistoryGridMetrics.clipboardSearchFieldWidth
        )
        return ceil(contentWidth + clipboardPanelHorizontalPadding + contentSafetyMargin)
    }

    static var clipboardPanelMinimumHeight: CGFloat {
        let bodyHeight = clipboardPanelCompactFilterBarHeight
            + HistoryGridMetrics.imageSpacing
            + clipboardPanelDividerHeight
            + HistoryGridMetrics.imageSpacing
            + clipboardMinimumContentHeight
            + HistoryGridMetrics.imageSpacing
            + clipboardPanelFooterHeight
        return ceil(
            clipboardPanelTopPadding
                + bodyHeight
                + clipboardPanelBottomPadding
                + contentSafetyMargin
        )
    }
}

/// Owns the main window's AppKit lifecycle independently from SwiftUI's view
/// redraws. The window frame is restored once when the NSWindow is attached and
/// persisted from window lifecycle notifications afterward.
@MainActor
final class JarvisMainWindowController: NSObject, ObservableObject {
    static let frameAutosaveName = "Jarvis.MainWindow"
    static var defaultWindowSize: CGSize {
        CGSize(
            width: max(1380, JarvisWindowLayoutMetrics.mainWindowMinimumWidth),
            height: max(760, JarvisWindowLayoutMetrics.mainWindowMinimumHeight)
        )
    }

    /// The minimum frame is derived from the intrinsic controls used by the
    /// navigation, clipboard, window-layout, and AI conversation surfaces.
    static var minimumWindowSize: CGSize {
        CGSize(
            width: JarvisWindowLayoutMetrics.mainWindowMinimumWidth,
            height: JarvisWindowLayoutMetrics.mainWindowMinimumHeight
        )
    }

    /// Initial content size for the SwiftUI scene. The saved origin is applied
    /// later, on the AppKit window, without animating from this size.
    static var launchWindowSize: CGSize {
        launchWindowSize(savedFrame: JarvisWindowFrameStore().load())
    }

    static func launchWindowSize(savedFrame: NSRect?) -> CGSize {
        resolvedLaunchFrame(
            savedFrame: savedFrame,
            fallbackOrigin: .zero,
            visibleFrames: []
        ).size
    }

    /// Full frame to show on launch. A saved frame that misses every visible
    /// screen keeps its size and takes `fallbackOrigin`. A missing or too-small
    /// frame uses the default size at that same origin.
    static func resolvedLaunchFrame(
        savedFrame: NSRect?,
        fallbackOrigin: CGPoint,
        visibleFrames: [NSRect]
    ) -> NSRect {
        guard let savedFrame, isUsable(savedFrame) else {
            return NSRect(origin: fallbackOrigin, size: defaultWindowSize)
        }
        let isOnScreen = visibleFrames.contains { $0.intersects(savedFrame) }
        let origin = isOnScreen ? savedFrame.origin : fallbackOrigin
        return NSRect(origin: origin, size: savedFrame.size)
    }

    static func applyLaunchFrame(_ frame: NSRect, to window: NSWindow) {
        window.animationBehavior = .none
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        window.setFrame(frame, display: false, animate: false)
        NSAnimationContext.endGrouping()
    }

    private static func framesMatch(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 0.5
            && abs(lhs.origin.y - rhs.origin.y) < 0.5
            && abs(lhs.width - rhs.width) < 0.5
            && abs(lhs.height - rhs.height) < 0.5
    }

    /// Title-bar drags are not `inLiveResize`, and AppKit starts them on
    /// `leftMouseDown` before any `leftMouseDragged` event. Let that origin
    /// change through. A size change is still replaced, including while the
    /// button is down, so the content-minimum shrink cannot land on a click.
    nonisolated static func pinnedFrame(
        insteadOf proposed: NSRect,
        pinned: NSRect,
        isLiveResizing: Bool,
        isUserMoving: Bool
    ) -> NSRect? {
        if isLiveResizing {
            return nil
        }
        let moved = abs(proposed.origin.x - pinned.origin.x) > 1
            || abs(proposed.origin.y - pinned.origin.y) > 1
        let resized = abs(proposed.width - pinned.width) > 1
            || abs(proposed.height - pinned.height) > 1
        guard moved || resized else { return nil }
        if isUserMoving, !resized {
            return nil
        }
        return pinned
    }

    /// Persist the pinned frame once launch has settled. The presentation
    /// monitor keeps running: opening settings later replays the same slide.
    private static let launchFrameSaveDelay: Duration = .seconds(2)

    private let frameStore = JarvisWindowFrameStore()
    private weak var window: NSWindow?
    private var frameObservers: [NSObjectProtocol] = []
    private var pendingFrameSave: Task<Void, Never>?
    private var launchFrameTask: Task<Void, Never>?
    private var launchFrameMonitor: Timer?
    private var windowMoveMonitor: Any?
    private var windowMoveRelease: Task<Void, Never>?
    private var pinnedLaunchFrame: NSRect?
    private var isApplyingLaunchFrame = false
    private var isCorrectingLaunchFrame = false
    private var isTrackingWindowMove = false
    private var didRestoreAnimation = false

    func attach(to window: NSWindow?) {
        guard let window, self.window !== window else { return }

        detach()
        self.window = window
        window.minSize = NSSize(
            width: Self.minimumWindowSize.width,
            height: Self.minimumWindowSize.height
        )
        pinLaunchFrame(on: window)
        configureAppearance(for: window)
        observeFrameChanges(of: window)
        if NSApp.isActive {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func detach() {
        launchFrameTask?.cancel()
        launchFrameTask = nil
        windowMoveRelease?.cancel()
        windowMoveRelease = nil
        removeWindowMoveMonitor()
        isTrackingWindowMove = false
        JarvisLaunchFrameBlock.isUserMoving = false
        if let window {
            finishLaunchFramePin(on: window)
        }
        pendingFrameSave?.cancel()
        pendingFrameSave = nil
        removeFrameObservers()
        window = nil
    }

    /// SwiftUI creates the window at its default size and only then restores the
    /// autosaved frame. Doing that restore after the window is on screen is what
    /// animates the default size into the remembered one. Later it collapses the
    /// frame to the content minimum and slides the window about a screen away.
    /// Pin the frame for the life of the window. A drag updates the pin.
    private func pinLaunchFrame(on window: NSWindow) {
        JarvisLaunchFrameBlock.install
        let target = Self.resolvedLaunchFrame(
            savedFrame: frameStore.load(),
            fallbackOrigin: window.frame.origin,
            visibleFrames: NSScreen.screens.map(\.visibleFrame)
        )
        pinnedLaunchFrame = target
        JarvisLaunchFrameBlock.window = window
        JarvisLaunchFrameBlock.frame = target
        didRestoreAnimation = false
        isApplyingLaunchFrame = true
        window.animationBehavior = .none
        let hidesWhileCorrecting = !window.isVisible || !Self.framesMatch(window.frame, target)
        if hidesWhileCorrecting {
            window.alphaValue = 0
        }
        Self.applyLaunchFrame(target, to: window)
        window.setFrameAutosaveName(Self.frameAutosaveName)
        Self.applyLaunchFrame(target, to: window)
        window.alphaValue = 1
        startLaunchFrameMonitor()

        launchFrameTask?.cancel()
        launchFrameTask = Task { @MainActor [weak self, weak window] in
            do {
                try await Task.sleep(for: Self.launchFrameSaveDelay)
            } catch {
                return
            }
            guard let self, let window, self.window === window, self.isApplyingLaunchFrame else { return }
            self.saveFrameImmediately()
        }
    }

    private func finishLaunchFramePin(on window: NSWindow) {
        guard isApplyingLaunchFrame else { return }
        launchFrameMonitor?.invalidate()
        launchFrameMonitor = nil
        correctLaunchFrameIfNeeded()
        restoreWindowAnimation(on: window)
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        isApplyingLaunchFrame = false
        isCorrectingLaunchFrame = false
        pinnedLaunchFrame = nil
        JarvisLaunchFrameBlock.window = nil
        JarvisLaunchFrameBlock.frame = nil
    }

    /// The model frame stays correct while the window server still slides the
    /// window across the screen. Hide that presentation for the life of the
    /// window: the slide is replayed when settings opens, long after launch.
    private func startLaunchFrameMonitor() {
        launchFrameMonitor?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(nudgePinnedFrame), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        launchFrameMonitor = timer
        installWindowMoveMonitor()
    }

    /// The window server moves the presented frame as soon as a title-bar drag
    /// starts. Hiding or pinning that frame mid-drag aborts the drag and leaves
    /// the window invisible, because the presented origin no longer matches.
    private func installWindowMoveMonitor() {
        guard windowMoveMonitor == nil else { return }
        windowMoveMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.trackWindowMove(event)
            }
            return event
        }
    }

    private func removeWindowMoveMonitor() {
        if let windowMoveMonitor {
            NSEvent.removeMonitor(windowMoveMonitor)
        }
        windowMoveMonitor = nil
    }

    private func trackWindowMove(_ event: NSEvent) {
        guard let window else { return }
        switch event.type {
        case .leftMouseDown:
            guard event.window === window else { return }
            beginWindowMove(on: window)
        case .leftMouseUp:
            guard isTrackingWindowMove else { return }
            scheduleWindowMoveRelease()
        default:
            break
        }
    }

    private func beginWindowMove(on window: NSWindow) {
        windowMoveRelease?.cancel()
        windowMoveRelease = nil
        isTrackingWindowMove = true
        JarvisLaunchFrameBlock.isUserMoving = true
        followWindowMove(on: window)
    }

    private func scheduleWindowMoveRelease() {
        windowMoveRelease?.cancel()
        windowMoveRelease = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self, let window = self.window else { return }
            guard (NSEvent.pressedMouseButtons & 1) == 0 else { return }
            self.endWindowMove(on: window)
        }
    }

    private func followWindowMove(on window: NSWindow) {
        pinnedLaunchFrame = window.frame
        JarvisLaunchFrameBlock.frame = window.frame
        if window.alphaValue < 1 || window.ignoresMouseEvents {
            window.alphaValue = 1
            window.ignoresMouseEvents = false
        }
    }

    private func endWindowMove(on window: NSWindow) {
        guard isTrackingWindowMove else { return }
        followWindowMove(on: window)
        isTrackingWindowMove = false
        JarvisLaunchFrameBlock.isUserMoving = false
        windowMoveRelease = nil
        scheduleFrameSave()
    }

    @objc private func nudgePinnedFrame() {
        guard isApplyingLaunchFrame, let window, pinnedLaunchFrame != nil else { return }
        if isTrackingWindowMove {
            if (NSEvent.pressedMouseButtons & 1) == 0, windowMoveRelease == nil {
                scheduleWindowMoveRelease()
            }
            followWindowMove(on: window)
            return
        }
        guard !isUserAdjustingFrame(window) else { return }
        if let pinnedLaunchFrame, !Self.framesMatch(window.frame, pinnedLaunchFrame) {
            correctLaunchFrameIfNeeded()
        }
        hideIfPresentationSlid(window)
    }

    private func hideIfPresentationSlid(_ window: NSWindow) {
        if isTrackingWindowMove || window.inLiveResize || (NSEvent.pressedMouseButtons & 1) != 0 {
            return
        }
        guard window.windowNumber > 0 else { return }
        let info = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            CGWindowID(window.windowNumber)
        ) as? [[String: Any]]
        guard let bounds = info?.first?[kCGWindowBounds as String] as? [String: CGFloat],
              let presentedX = bounds["X"],
              let width = bounds["Width"],
              let height = bounds["Height"],
              width > 200,
              height > 200
        else { return }
        let model = window.frame
        let slid = abs(presentedX - model.origin.x) > 40
            || abs(width - model.width) > 40
            || abs(height - model.height) > 40
        guard slid == (window.alphaValue > 0.5) else { return }
        window.alphaValue = slid ? 0 : 1
        window.ignoresMouseEvents = slid
    }

    private func restoreWindowAnimation(on window: NSWindow) {
        guard !didRestoreAnimation else { return }
        didRestoreAnimation = true
        window.animationBehavior = .default
    }

    /// A title-bar drag is not `inLiveResize`, and its first events are
    /// `leftMouseDown`. Keep following the frame until the button has been up
    /// long enough for AppKit to commit the released origin.
    private func isUserAdjustingFrame(_ window: NSWindow) -> Bool {
        if window.inLiveResize || isTrackingWindowMove {
            return true
        }
        return NSApp.currentEvent?.type == .leftMouseDragged
    }

    private func handleFrameDidChange() {
        guard isApplyingLaunchFrame, let window else {
            scheduleFrameSave()
            return
        }
        // Follow a drag for the rest of the pin. Ending the pin here lets the
        // later minimum-size pass shrink the window the user just placed.
        if isUserAdjustingFrame(window) {
            pinnedLaunchFrame = window.frame
            JarvisLaunchFrameBlock.frame = window.frame
            scheduleFrameSave()
            return
        }
        correctLaunchFrameIfNeeded()
    }

    private func correctLaunchFrameIfNeeded() {
        guard isApplyingLaunchFrame, !isCorrectingLaunchFrame, let window, let pinnedLaunchFrame else {
            return
        }
        guard !isUserAdjustingFrame(window) else { return }
        guard !Self.framesMatch(window.frame, pinnedLaunchFrame) else { return }
        isCorrectingLaunchFrame = true
        Self.applyLaunchFrame(pinnedLaunchFrame, to: window)
        isCorrectingLaunchFrame = false
    }

    private static func isUsable(_ frame: NSRect) -> Bool {
        frame.width >= minimumWindowSize.width && frame.height >= minimumWindowSize.height
    }

    private static func observe(
        _ name: Notification.Name,
        of window: NSWindow,
        perform: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: name, object: window, queue: nil) { _ in
            MainActor.assumeIsolated(perform)
        }
    }

    private func observeFrameChanges(of window: NSWindow) {
        let notificationCenter = NotificationCenter.default
        frameObservers = [
            // Synchronous. A queued observer runs after SwiftUI has already
            // animated the window a screen-width away.
            Self.observe(NSWindow.didMoveNotification, of: window) { [weak self] in
                self?.handleFrameDidChange()
            },
            Self.observe(NSWindow.didResizeNotification, of: window) { [weak self] in
                self?.handleFrameDidChange()
            },
            notificationCenter.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.correctLaunchFrameIfNeeded()
                    self?.saveFrameImmediately()
                }
            }
        ]
    }

    private func scheduleFrameSave() {
        pendingFrameSave?.cancel()
        pendingFrameSave = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.saveFrameImmediately()
        }
    }

    private func saveFrameImmediately() {
        pendingFrameSave?.cancel()
        pendingFrameSave = nil
        guard let window else { return }
        frameStore.save(window.frame)
    }

    private func removeFrameObservers() {
        let notificationCenter = NotificationCenter.default
        frameObservers.forEach(notificationCenter.removeObserver)
        frameObservers.removeAll()
    }

    private func configureAppearance(for window: NSWindow) {
        JarvisWindowAppearance.configure(for: window)
    }
}

private struct JarvisWindowFrameStore {
    private static let defaultsKey = "Jarvis.MainWindow.frame"

    func load() -> NSRect? {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let frame = try? JSONDecoder().decode(JarvisStoredWindowFrame.self, from: data)
        {
            return frame.rect
        }

        // Migrate the string format used by the earlier window autosave fix.
        if let legacyFrame = UserDefaults.standard.string(forKey: Self.defaultsKey) {
            let rect = NSRectFromString(legacyFrame)
            guard rect.width > 0, rect.height > 0 else { return nil }
            save(rect)
            return rect
        }

        return nil
    }

    func save(_ rect: NSRect) {
        let frame = JarvisStoredWindowFrame(rect: rect)
        guard let data = try? JSONEncoder().encode(frame) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

private struct JarvisStoredWindowFrame: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(rect: NSRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }

    var rect: NSRect {
        NSRect(x: x, y: y, width: width, height: height)
    }
}

/// SwiftUI animates `setFrame` to the content minimum a few seconds after
/// launch, and that animation also slides the window about a screen away.
/// Replacing the frame before AppKit starts the animation keeps it put.
/// `setContentSize` is included because the shrink keeps the top-left corner.
private enum JarvisLaunchFrameBlock {
    nonisolated(unsafe) weak static var window: NSWindow?
    nonisolated(unsafe) static var frame: NSRect?
    nonisolated(unsafe) static var isApplyingPinnedFrame = false
    nonisolated(unsafe) static var isUserMoving = false

    static let install: Void = {
        exchange(
            #selector(NSWindow.setFrame(_:display:animate:)),
            #selector(NSWindow.jarvis_setFrame(_:display:animate:))
        )
        exchange(
            #selector(NSWindow.setFrameOrigin(_:)),
            #selector(NSWindow.jarvis_setFrameOrigin(_:))
        )
        exchange(
            #selector(NSWindow.setContentSize(_:)),
            #selector(NSWindow.jarvis_setContentSize(_:))
        )
        exchange(
            NSSelectorFromString("_reallySetFrame:"),
            #selector(NSWindow.jarvis_reallySetFrame(_:))
        )
        exchange(
            NSSelectorFromString("_setFrame:"),
            #selector(NSWindow.jarvis_setFrameIgnoringPublicAPI(_:))
        )
        exchange(
            NSSelectorFromString("_setFrame:display:allowImplicitAnimation:stashSize:"),
            #selector(NSWindow.jarvis_setFrameAllowingImplicitAnimation(_:display:allowImplicitAnimation:stashSize:))
        )
        exchange(
            NSSelectorFromString("_setFrame:fromAdjustmentToScreen:animate:"),
            #selector(NSWindow.jarvis_setFrameForScreenAdjustment(_:screen:animate:))
        )
        exchange(
            #selector(NSWindow.setFrameTopLeftPoint(_:)),
            #selector(NSWindow.jarvis_setFrameTopLeftPoint(_:))
        )
        exchange(
            NSSelectorFromString("_setFrameCommon:display:stashSize:"),
            #selector(NSWindow.jarvis_setFrameCommon(_:display:stashSize:))
        )
        exchange(
            NSSelectorFromString("_setFrameCommon:display:fromServer:"),
            #selector(NSWindow.jarvis_setFrameCommonFromServer(_:display:fromServer:))
        )
    }()

    static func performPinned(_ body: () -> Void) {
        let previous = isApplyingPinnedFrame
        isApplyingPinnedFrame = true
        defer { isApplyingPinnedFrame = previous }
        body()
    }

    private static func exchange(_ original: Selector, _ replacement: Selector) {
        guard let originalMethod = class_getInstanceMethod(NSWindow.self, original),
              let replacementMethod = class_getInstanceMethod(NSWindow.self, replacement)
        else { return }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }
}

private extension NSWindow {
    @objc func jarvis_setFrame(_ frame: NSRect, display: Bool, animate: Bool) {
        if let pinned = jarvisPinnedFrame(insteadOf: frame) {
            JarvisLaunchFrameBlock.performPinned {
                jarvis_setFrame(pinned, display: display, animate: false)
            }
            return
        }
        jarvis_setFrame(frame, display: display, animate: animate)
    }

    @objc func jarvis_setFrameOrigin(_ point: NSPoint) {
        let proposed = NSRect(origin: point, size: frame.size)
        if let pinned = jarvisPinnedFrame(insteadOf: proposed) {
            JarvisLaunchFrameBlock.performPinned {
                jarvis_setFrameOrigin(pinned.origin)
            }
            return
        }
        jarvis_setFrameOrigin(point)
    }

    @objc func jarvis_setContentSize(_ size: NSSize) {
        let current = frame
        let proposedSize = frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        let proposed = NSRect(
            x: current.origin.x,
            y: current.maxY - proposedSize.height,
            width: proposedSize.width,
            height: proposedSize.height
        )
        if let pinned = jarvisPinnedFrame(insteadOf: proposed) {
            JarvisLaunchFrameBlock.performPinned {
                jarvis_setFrame(pinned, display: true, animate: false)
            }
            return
        }
        jarvis_setContentSize(size)
    }

    @objc func jarvis_reallySetFrame(_ frame: NSRect) {
        if let pinned = jarvisPinnedFrame(insteadOf: frame) {
            JarvisLaunchFrameBlock.performPinned {
                jarvis_reallySetFrame(pinned)
            }
            return
        }
        jarvis_reallySetFrame(frame)
    }

    /// `_setFrame:` is the private entry SwiftUI uses for implicit moves.
    /// The Swift name has to differ from `jarvis_setFrame(_:display:animate:)`.
    @objc(jarvis_setFrameIgnoringPublicAPI:)
    func jarvis_setFrameIgnoringPublicAPI(_ frame: NSRect) {
        if let pinned = jarvisPinnedFrame(insteadOf: frame) {
            JarvisLaunchFrameBlock.performPinned {
                jarvis_setFrameIgnoringPublicAPI(pinned)
            }
            return
        }
        jarvis_setFrameIgnoringPublicAPI(frame)
    }

    @objc(jarvis_setFrame:display:allowImplicitAnimation:stashSize:)
    func jarvis_setFrameAllowingImplicitAnimation(
        _ frame: NSRect,
        display: Bool,
        allowImplicitAnimation: Bool,
        stashSize: Bool
    ) {
        if let pinned = jarvisPinnedFrame(insteadOf: frame) {
            JarvisLaunchFrameBlock.performPinned {
                jarvis_setFrameAllowingImplicitAnimation(
                    pinned,
                    display: display,
                    allowImplicitAnimation: false,
                    stashSize: stashSize
                )
            }
            return
        }
        jarvis_setFrameAllowingImplicitAnimation(
            frame,
            display: display,
            allowImplicitAnimation: allowImplicitAnimation,
            stashSize: stashSize
        )
    }

    @objc(jarvis_setFrame:fromAdjustmentToScreen:animate:)
    func jarvis_setFrameForScreenAdjustment(_ frame: NSRect, screen: AnyObject?, animate: Bool) {
        if let pinned = jarvisPinnedFrame(insteadOf: frame) {
            JarvisLaunchFrameBlock.performPinned {
                jarvis_setFrameForScreenAdjustment(pinned, screen: screen, animate: false)
            }
            return
        }
        jarvis_setFrameForScreenAdjustment(frame, screen: screen, animate: animate)
    }

    @objc(jarvis_setFrameCommon:display:stashSize:)
    func jarvis_setFrameCommon(_ frame: NSRect, display: Bool, stashSize: Bool) {
        if let pinned = jarvisPinnedFrame(insteadOf: frame) {
            JarvisLaunchFrameBlock.performPinned {
                jarvis_setFrameCommon(pinned, display: display, stashSize: stashSize)
            }
            return
        }
        jarvis_setFrameCommon(frame, display: display, stashSize: stashSize)
    }

    @objc(jarvis_setFrameCommon:display:fromServer:)
    func jarvis_setFrameCommonFromServer(_ frame: NSRect, display: Bool, fromServer: Bool) {
        if let pinned = jarvisPinnedFrame(insteadOf: frame) {
            JarvisLaunchFrameBlock.performPinned {
                jarvis_setFrameCommonFromServer(pinned, display: display, fromServer: fromServer)
            }
            return
        }
        jarvis_setFrameCommonFromServer(frame, display: display, fromServer: fromServer)
    }

    @objc func jarvis_setFrameTopLeftPoint(_ point: NSPoint) {
        let userMoving = JarvisLaunchFrameBlock.isUserMoving
            || NSApp.currentEvent?.type == .leftMouseDragged
        guard let pinned = JarvisLaunchFrameBlock.frame,
              JarvisLaunchFrameBlock.window === self,
              !JarvisLaunchFrameBlock.isApplyingPinnedFrame,
              !inLiveResize,
              !userMoving
        else {
            jarvis_setFrameTopLeftPoint(point)
            return
        }
        let pinnedTopLeft = NSPoint(x: pinned.origin.x, y: pinned.origin.y + pinned.height)
        let moved = abs(point.x - pinnedTopLeft.x) > 1 || abs(point.y - pinnedTopLeft.y) > 1
        guard moved else {
            jarvis_setFrameTopLeftPoint(point)
            return
        }
        JarvisLaunchFrameBlock.performPinned {
            jarvis_setFrameTopLeftPoint(pinnedTopLeft)
        }
    }

    func jarvisPinnedFrame(insteadOf proposed: NSRect) -> NSRect? {
        guard !JarvisLaunchFrameBlock.isApplyingPinnedFrame else { return nil }
        guard let guarded = JarvisLaunchFrameBlock.window, guarded === self,
              let pinned = JarvisLaunchFrameBlock.frame
        else { return nil }
        let userMoving = JarvisLaunchFrameBlock.isUserMoving
            || NSApp.currentEvent?.type == .leftMouseDragged
        return JarvisMainWindowController.pinnedFrame(
            insteadOf: proposed,
            pinned: pinned,
            isLiveResizing: inLiveResize,
            isUserMoving: userMoving
        )
    }
}

struct JarvisMainWindowAccessor: NSViewRepresentable {
    let controller: JarvisMainWindowController

    func makeNSView(context _: Context) -> NSView {
        let view = JarvisMainWindowAnchorView(frame: .zero)
        view.onResolveWindow = { [weak controller] window in
            controller?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        MainActor.assumeIsolated {
            controller.attach(to: nsView.window)
        }
    }
}

/// Receives the NSWindow while it is being attached, before SwiftUI has a
/// chance to show the default size and animate it to the saved frame.
private final class JarvisMainWindowAnchorView: NSView {
    var onResolveWindow: ((NSWindow) -> Void)?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard let newWindow else { return }
        MainActor.assumeIsolated {
            onResolveWindow?(newWindow)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        MainActor.assumeIsolated {
            onResolveWindow?(window)
        }
    }
}
