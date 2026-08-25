import AppKit
import ApplicationServices

enum WindowLayout: String, CaseIterable, Hashable, Identifiable {
    case halfLeft
    case halfRight
    case upperLeft
    case upperRight
    case lowerLeft
    case lowerRight

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .halfLeft: "左半屏"
        case .halfRight: "右半屏"
        case .upperLeft: "左上角"
        case .upperRight: "右上角"
        case .lowerLeft: "左下角"
        case .lowerRight: "右下角"
        }
    }

    var shortTitle: String {
        title
    }

    var menuIcon: NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 16))
        image.lockFocus()
        defer { image.unlockFocus() }

        let bounds = NSRect(x: 2, y: 2, width: 20, height: 11.25)

        let halfWidth = bounds.width / 2
        let halfHeight = bounds.height / 2
        let selectedRect = switch self {
        case .halfLeft:
            NSRect(
                x: bounds.minX,
                y: bounds.minY,
                width: halfWidth,
                height: bounds.height
            )
        case .halfRight:
            NSRect(
                x: bounds.midX,
                y: bounds.minY,
                width: halfWidth,
                height: bounds.height
            )
        case .upperLeft:
            NSRect(
                x: bounds.minX,
                y: bounds.midY,
                width: halfWidth,
                height: halfHeight
            )
        case .upperRight:
            NSRect(
                x: bounds.midX,
                y: bounds.midY,
                width: halfWidth,
                height: halfHeight
            )
        case .lowerLeft:
            NSRect(
                x: bounds.minX,
                y: bounds.minY,
                width: halfWidth,
                height: halfHeight
            )
        case .lowerRight:
            NSRect(
                x: bounds.midX,
                y: bounds.minY,
                width: halfWidth,
                height: halfHeight
            )
        }
        NSColor.controlAccentColor.setFill()
        selectedRect.fill()

        NSColor.labelColor.withAlphaComponent(0.72).setStroke()
        let border = NSBezierPath(rect: bounds)
        border.lineWidth = 1
        border.stroke()
        return image
    }

    var shortcutDisplay: String {
        shortcutDisplayParts.joined()
    }

    var shortcutDisplayParts: [String] {
        switch self {
        case .halfLeft: ["⇧", "⌘", "←"]
        case .halfRight: ["⇧", "⌘", "→"]
        case .upperLeft: ["⇧", "⌘", "U"]
        case .upperRight: ["⇧", "⌘", "I"]
        case .lowerLeft: ["⇧", "⌘", "J"]
        case .lowerRight: ["⇧", "⌘", "K"]
        }
    }

    var menuKeyEquivalent: String {
        switch self {
        case .halfLeft: Self.functionKey(0xF702)
        case .halfRight: Self.functionKey(0xF703)
        case .upperLeft: "u"
        case .upperRight: "i"
        case .lowerLeft: "j"
        case .lowerRight: "k"
        }
    }

    private static func functionKey(_ value: UInt32) -> String {
        String(decoding: [UInt16(value)], as: UTF16.self)
    }

    var shortcutKeyCode: UInt16 {
        switch self {
        case .halfLeft: 123
        case .halfRight: 124
        case .upperLeft: 32
        case .upperRight: 34
        case .lowerLeft: 38
        case .lowerRight: 40
        }
    }

    static let shortcutModifierFlags: NSEvent.ModifierFlags = [.command, .shift]

    static func layout(for keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> WindowLayout? {
        let relevantModifiers = modifiers.intersection([.command, .option, .control, .shift])
        guard relevantModifiers == shortcutModifierFlags else {
            return nil
        }
        return allCases.first { $0.shortcutKeyCode == keyCode }
    }

    static func layout(for directions: Set<WindowLayoutDirection>) -> WindowLayout? {
        switch directions {
        case [.left]: .halfLeft
        case [.right]: .halfRight
        case [.left, .up]: .upperLeft
        case [.right, .up]: .upperRight
        case [.left, .down]: .lowerLeft
        case [.right, .down]: .lowerRight
        default: nil
        }
    }

    static func frame(for layout: WindowLayout, in visibleFrame: NSRect) -> NSRect {
        let halfWidth = visibleFrame.width / 2
        let halfHeight = visibleFrame.height / 2
        let middleX = visibleFrame.minX + halfWidth
        let middleY = visibleFrame.minY + halfHeight

        switch layout {
        case .halfLeft:
            return NSRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: halfWidth,
                height: visibleFrame.height
            )
        case .halfRight:
            return NSRect(
                x: middleX,
                y: visibleFrame.minY,
                width: halfWidth,
                height: visibleFrame.height
            )
        case .upperLeft:
            return NSRect(
                x: visibleFrame.minX,
                y: middleY,
                width: halfWidth,
                height: halfHeight
            )
        case .upperRight:
            return NSRect(
                x: middleX,
                y: middleY,
                width: halfWidth,
                height: halfHeight
            )
        case .lowerLeft:
            return NSRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: halfWidth,
                height: halfHeight
            )
        case .lowerRight:
            return NSRect(
                x: middleX,
                y: visibleFrame.minY,
                width: halfWidth,
                height: halfHeight
            )
        }
    }
}

enum WindowLayoutDirection: Hashable {
    case left
    case right
    case up
    case down

    init?(keyCode: UInt16) {
        switch keyCode {
        case 123: self = .left
        case 124: self = .right
        case 125: self = .down
        case 126: self = .up
        default: return nil
        }
    }
}

@MainActor
final class WindowLayoutController {
    private let statusHandler: (String) -> Void
    private var shortcutManagers: [ScreenshotShortcutManager] = []

    init(statusHandler: @escaping (String) -> Void) {
        self.statusHandler = statusHandler
        installShortcuts()
    }

    deinit {
        shortcutManagers.removeAll()
    }

    var isAccessibilityTrusted: Bool {
        JarvisPrivacyPermissionAccess.isAccessibilityTrusted()
    }

    @discardableResult
    func requestAccessibilityAccess() -> Bool {
        JarvisPrivacyPermissionAccess.requestAccessibilityAccess()
    }

    func apply(_ layout: WindowLayout) {
        guard isAccessibilityTrusted else {
            statusHandler("请先在系统设置中允许贾维斯控制电脑")
            return
        }

        guard let target = focusedWindowOfFrontmostApplication() else {
            statusHandler("没有找到可调整的前台窗口")
            return
        }

        guard let geometry = windowGeometry(for: target.window) else {
            statusHandler("无法读取当前窗口的位置和大小")
            return
        }

        let targetFrame = WindowLayout.frame(for: layout, in: geometry.screen.visibleFrame)
        guard setFrame(targetFrame, on: target.window, using: geometry.screen) else {
            statusHandler("当前窗口不允许调整大小或位置")
            return
        }

        statusHandler("已将 \(target.application.localizedName ?? "当前窗口") 调整为\(layout.shortTitle)")
    }

    private func installShortcuts() {
        shortcutManagers = WindowLayout.allCases.enumerated().map { index, layout in
            let binding = ScreenshotShortcut(
                keyCode: layout.shortcutKeyCode,
                modifiers: WindowLayout.shortcutModifierFlags.rawValue
            )
            return ScreenshotShortcutManager(
                binding: binding,
                hotKeyID: UInt32(10 + index)
            ) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.apply(layout)
                }
            }
        }
    }

    private struct FocusedWindow {
        let application: NSRunningApplication
        let window: AXUIElement
    }

    private struct WindowGeometry {
        let screen: NSScreen
    }

    private func focusedWindowOfFrontmostApplication() -> FocusedWindow? {
        // The frontmost app is the target, including Jarvis itself. Older
        // builds deliberately skipped Jarvis and therefore could never tile
        // the main window when it was active.
        let application = NSWorkspace.shared.frontmostApplication
        guard let application, !application.isTerminated else { return nil }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &value
        )
        guard result == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let window = unsafeBitCast(value, to: AXUIElement.self)
        return FocusedWindow(application: application, window: window)
    }

    private func windowGeometry(for window: AXUIElement) -> WindowGeometry? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let positionAXValue = unsafeBitCast(positionValue, to: AXValue.self)
        let sizeAXValue = unsafeBitCast(sizeValue, to: AXValue.self)
        guard AXValueGetType(positionAXValue) == .cgPoint,
              AXValueGetType(sizeAXValue) == .cgSize,
              AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue, .cgSize, &size),
              size.width > 0,
              size.height > 0,
              let screen = screen(containing: CGRect(origin: position, size: size))
        else {
            return nil
        }

        return WindowGeometry(screen: screen)
    }

    private func setFrame(_ frame: NSRect, on window: AXUIElement, using screen: NSScreen) -> Bool {
        let position = CGPoint(
            x: frame.minX,
            y: accessibilityY(for: frame, on: screen)
        )
        var positionValue = position
        var sizeValue = frame.size
        guard let axPosition = AXValueCreate(.cgPoint, &positionValue),
              let axSize = AXValueCreate(.cgSize, &sizeValue)
        else {
            return false
        }

        // Some applications clamp the size when the position is changed in
        // the same AX transaction. Apply the position, apply the exact target
        // size, then apply the position once more to stabilize both halves.
        let initialPositionResult = AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            axPosition
        )
        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axSize)
        let finalPositionResult = AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            axPosition
        )
        return initialPositionResult == .success
            && sizeResult == .success
            && finalPositionResult == .success
    }

    private func screen(containing windowRect: CGRect) -> NSScreen? {
        let candidates = NSScreen.screens
        let containing = candidates.first { screen in
            accessibilityFrame(for: screen).contains(windowRect.mid)
        }
        if let containing {
            return containing
        }

        return candidates.max { lhs, rhs in
            accessibilityFrame(for: lhs).intersection(windowRect).area
                < accessibilityFrame(for: rhs).intersection(windowRect).area
        }
    }

    private func accessibilityFrame(for screen: NSScreen) -> CGRect {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? screen.frame.maxY
            return CGRect(
                x: screen.frame.minX,
                y: desktopTop - screen.frame.maxY,
                width: screen.frame.width,
                height: screen.frame.height
            )
        }
        return CGDisplayBounds(displayID)
    }

    private func accessibilityY(for frame: NSRect, on screen: NSScreen) -> CGFloat {
        let fullFrame = accessibilityFrame(for: screen)
        let relativeMaxY = frame.maxY - screen.frame.minY
        return fullFrame.minY + (screen.frame.height - relativeMaxY)
    }
}

private extension CGRect {
    var mid: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
