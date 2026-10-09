import AppKit
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

    /// How long to keep rejecting SwiftUI's animated restore after the window attaches.
    private static let launchFramePinDuration: Duration = .milliseconds(400)

    private let frameStore = JarvisWindowFrameStore()
    private weak var window: NSWindow?
    private var frameObservers: [NSObjectProtocol] = []
    private var pendingFrameSave: Task<Void, Never>?
    private var launchFrameTask: Task<Void, Never>?
    private var pinnedLaunchFrame: NSRect?
    private var isApplyingLaunchFrame = false
    private var isCorrectingLaunchFrame = false

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
    /// animates the default size into the remembered one. Pin the saved frame,
    /// with window animation disabled, before the first paint and until that
    /// late restore has stopped changing the frame.
    private func pinLaunchFrame(on window: NSWindow) {
        let target = Self.resolvedLaunchFrame(
            savedFrame: frameStore.load(),
            fallbackOrigin: window.frame.origin,
            visibleFrames: NSScreen.screens.map(\.visibleFrame)
        )
        pinnedLaunchFrame = target
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

        launchFrameTask?.cancel()
        launchFrameTask = Task { @MainActor [weak self, weak window] in
            do {
                try await Task.sleep(for: Self.launchFramePinDuration)
            } catch {
                return
            }
            guard let self, let window, self.window === window else { return }
            self.finishLaunchFramePin(on: window)
        }
    }

    private func finishLaunchFramePin(on window: NSWindow) {
        guard isApplyingLaunchFrame else { return }
        correctLaunchFrameIfNeeded()
        window.animationBehavior = .default
        window.alphaValue = 1
        isApplyingLaunchFrame = false
        isCorrectingLaunchFrame = false
        pinnedLaunchFrame = nil
    }

    private func handleFrameDidChange() {
        if isApplyingLaunchFrame {
            correctLaunchFrameIfNeeded()
            return
        }
        scheduleFrameSave()
    }

    private func correctLaunchFrameIfNeeded() {
        guard isApplyingLaunchFrame, !isCorrectingLaunchFrame, let window, let pinnedLaunchFrame else {
            return
        }
        guard !window.inLiveResize else { return }
        guard !Self.framesMatch(window.frame, pinnedLaunchFrame) else { return }
        isCorrectingLaunchFrame = true
        Self.applyLaunchFrame(pinnedLaunchFrame, to: window)
        isCorrectingLaunchFrame = false
    }

    private static func isUsable(_ frame: NSRect) -> Bool {
        frame.width >= minimumWindowSize.width && frame.height >= minimumWindowSize.height
    }

    private func observeFrameChanges(of window: NSWindow) {
        let notificationCenter = NotificationCenter.default
        frameObservers = [
            notificationCenter.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleFrameDidChange()
                }
            },
            notificationCenter.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleFrameDidChange()
                }
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
