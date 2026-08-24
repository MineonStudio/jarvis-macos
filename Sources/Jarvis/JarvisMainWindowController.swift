import AppKit
import SwiftUI

/// Owns the main window's AppKit lifecycle independently from SwiftUI's view
/// redraws. The window frame is restored once when the NSWindow is attached and
/// persisted from window lifecycle notifications afterward.
final class JarvisMainWindowController: NSObject, ObservableObject {
    static let frameAutosaveName = "Jarvis.MainWindow"
    static let defaultWindowSize = CGSize(width: 1120, height: 760)
    static let minimumWindowSize = CGSize(width: 980, height: 680)

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
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = .textBackgroundColor
        window.sharingType = .readOnly

        if let close = window.standardWindowButton(.closeButton),
           let miniaturize = window.standardWindowButton(.miniaturizeButton),
           let zoom = window.standardWindowButton(.zoomButton)
        {
            // The native traffic lights belong to the sidebar in the reference
            // layout, so move the standard button group into that column.
            let titlebarY = close.frame.minY
            close.setFrameOrigin(NSPoint(x: 18, y: titlebarY))
            miniaturize.setFrameOrigin(NSPoint(x: close.frame.maxX + 8, y: titlebarY))
            zoom.setFrameOrigin(NSPoint(x: miniaturize.frame.maxX + 8, y: titlebarY))
            close.isHidden = false
            miniaturize.isHidden = false
            zoom.isHidden = false
            close.translatesAutoresizingMaskIntoConstraints = true
            miniaturize.translatesAutoresizingMaskIntoConstraints = true
            zoom.translatesAutoresizingMaskIntoConstraints = true
        }
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
