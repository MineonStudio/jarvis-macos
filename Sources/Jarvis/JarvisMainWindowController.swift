import AppKit
import SwiftUI

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
            AIConversationLayoutMetrics.minimumTopBarWidth
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

    /// The scene uses this before SwiftUI creates the NSWindow. Feeding the
    /// saved size into `.defaultSize` prevents the default frame from flashing
    /// before the accessor can restore the complete frame.
    static var launchWindowSize: CGSize {
        launchWindowSize(savedFrame: JarvisWindowFrameStore().load())
    }

    static func launchWindowSize(savedFrame: NSRect?) -> CGSize {
        guard let savedFrame, isUsable(savedFrame) else { return defaultWindowSize }
        return savedFrame.size
    }

    private let frameStore = JarvisWindowFrameStore()
    private weak var window: NSWindow?
    private var frameObservers: [NSObjectProtocol] = []
    private var pendingFrameSave: DispatchWorkItem?

    deinit {
        pendingFrameSave?.cancel()
        removeFrameObservers()
    }

    func attach(to window: NSWindow?) {
        guard let window, self.window !== window else { return }

        detach()
        self.window = window
        window.setFrameAutosaveName(Self.frameAutosaveName)
        window.minSize = NSSize(
            width: Self.minimumWindowSize.width,
            height: Self.minimumWindowSize.height
        )
        restoreFrame(to: window)
        configureAppearance(for: window)
        observeFrameChanges(of: window)
    }

    private func detach() {
        pendingFrameSave?.cancel()
        pendingFrameSave = nil
        removeFrameObservers()
        window = nil
    }

    private func restoreFrame(to window: NSWindow) {
        guard let savedFrame = frameStore.load(),
              Self.isUsable(savedFrame)
        else {
            return
        }

        let isVisibleOnScreen = NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(savedFrame)
        }
        let restoredFrame = isVisibleOnScreen
            ? savedFrame
            : NSRect(origin: window.frame.origin, size: savedFrame.size)
        window.setFrame(restoredFrame, display: false)
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
                self?.scheduleFrameSave()
            },
            notificationCenter.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleFrameSave()
            },
            notificationCenter.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.saveFrameImmediately()
            }
        ]
    }

    private func scheduleFrameSave() {
        pendingFrameSave?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveFrameImmediately()
        }
        pendingFrameSave = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
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
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            controller.attach(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        DispatchQueue.main.async {
            controller.attach(to: nsView.window)
        }
    }
}
