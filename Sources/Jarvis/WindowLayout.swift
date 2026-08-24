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
        case .halfLeft: "左侧二分之一"
        case .halfRight: "右侧二分之一"
        case .upperLeft: "左上四分之一"
        case .upperRight: "右上四分之一"
        case .lowerLeft: "左下四分之一"
        case .lowerRight: "右下四分之一"
        }
    }

    var shortTitle: String {
        switch self {
        case .halfLeft: "左半"
        case .halfRight: "右半"
        case .upperLeft: "左上"
        case .upperRight: "右上"
        case .lowerLeft: "左下"
        case .lowerRight: "右下"
        }
    }

    var icon: String {
        switch self {
        case .halfLeft: "rectangle.lefthalf.filled"
        case .halfRight: "rectangle.righthalf.filled"
        case .upperLeft, .upperRight, .lowerLeft, .lowerRight: "rectangle.grid.2x2"
        }
    }

    var shortcutDisplay: String {
        switch self {
        case .halfLeft: "⇧←"
        case .halfRight: "⇧→"
        case .upperLeft: "⇧←↑"
        case .upperRight: "⇧→↑"
        case .lowerLeft: "⇧←↓"
        case .lowerRight: "⇧→↓"
        }
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
        let middleX = visibleFrame.minX + floor(visibleFrame.width / 2)
        let middleY = visibleFrame.minY + floor(visibleFrame.height / 2)

        switch layout {
        case .halfLeft:
            return NSRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: middleX - visibleFrame.minX,
                height: visibleFrame.height
            )
        case .halfRight:
            return NSRect(
                x: middleX,
                y: visibleFrame.minY,
                width: visibleFrame.maxX - middleX,
                height: visibleFrame.height
            )
        case .upperLeft:
            return NSRect(
                x: visibleFrame.minX,
                y: middleY,
                width: middleX - visibleFrame.minX,
                height: visibleFrame.maxY - middleY
            )
        case .upperRight:
            return NSRect(
                x: middleX,
                y: middleY,
                width: visibleFrame.maxX - middleX,
                height: visibleFrame.maxY - middleY
            )
        case .lowerLeft:
            return NSRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: middleX - visibleFrame.minX,
                height: middleY - visibleFrame.minY
            )
        case .lowerRight:
            return NSRect(
                x: middleX,
                y: visibleFrame.minY,
                width: visibleFrame.maxX - middleX,
                height: middleY - visibleFrame.minY
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
    private static let shiftKeyCodes: Set<UInt16> = [56, 60]
    private static let halfLayoutDelay: TimeInterval = 0.18

    private let statusHandler: (String) -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var lastExternalApplication: NSRunningApplication?
    private var pressedDirections = Set<WindowLayoutDirection>()
    private var shiftIsDown = false
    private var didApplyCurrentChord = false
    private var halfLayoutWorkItem: DispatchWorkItem?

    init(statusHandler: @escaping (String) -> Void) {
        self.statusHandler = statusHandler
        if let application = NSWorkspace.shared.frontmostApplication,
           application.processIdentifier != ProcessInfo.processInfo.processIdentifier
        {
            lastExternalApplication = application
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else {
                return
            }
            Task { @MainActor [weak self] in
                self?.lastExternalApplication = application
            }
        }
        installMonitors()
    }

    deinit {
        halfLayoutWorkItem?.cancel()
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func refreshAccessibilityStatus() -> Bool {
        installMonitors()
        return isAccessibilityTrusted
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
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

    private func installMonitors() {
        let eventMask: NSEvent.EventTypeMask = [.keyDown, .keyUp]
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] event in
                self?.handle(event)
            }
        }
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
                self?.handle(event)
                return event
            }
        }
    }

    private func handle(_ event: NSEvent) {
        if Self.shiftKeyCodes.contains(event.keyCode) {
            if event.type == .keyDown {
                if !shiftIsDown {
                    pressedDirections.removeAll()
                    didApplyCurrentChord = false
                    halfLayoutWorkItem?.cancel()
                    halfLayoutWorkItem = nil
                }
                shiftIsDown = true
            } else {
                shiftIsDown = false
                if !didApplyCurrentChord,
                   let layout = WindowLayout.layout(for: pressedDirections),
                   pressedDirections.count == 1
                {
                    halfLayoutWorkItem?.cancel()
                    halfLayoutWorkItem = nil
                    apply(layout)
                }
                resetChord()
            }
            return
        }

        guard let direction = WindowLayoutDirection(keyCode: event.keyCode) else {
            if event.type == .keyUp, !event.modifierFlags.contains(.shift) {
                resetChord()
            }
            return
        }

        if event.type == .keyDown {
            shiftIsDown = shiftIsDown || event.modifierFlags.contains(.shift)
            guard shiftIsDown, !event.isARepeat else { return }
            pressedDirections.insert(direction)
            handlePressedDirections()
        }
    }

    private func handlePressedDirections() {
        guard let layout = WindowLayout.layout(for: pressedDirections) else {
            halfLayoutWorkItem?.cancel()
            halfLayoutWorkItem = nil
            return
        }

        if pressedDirections.count == 2 {
            halfLayoutWorkItem?.cancel()
            halfLayoutWorkItem = nil
            apply(layout)
            didApplyCurrentChord = true
            return
        }

        halfLayoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, pressedDirections.count == 1 else { return }
            apply(layout)
            didApplyCurrentChord = true
            halfLayoutWorkItem = nil
        }
        halfLayoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.halfLayoutDelay, execute: workItem)
    }

    private func resetChord() {
        halfLayoutWorkItem?.cancel()
        halfLayoutWorkItem = nil
        pressedDirections.removeAll()
        shiftIsDown = false
        didApplyCurrentChord = false
    }

    private struct FocusedWindow {
        let application: NSRunningApplication
        let window: AXUIElement
    }

    private struct WindowGeometry {
        let screen: NSScreen
    }

    private func focusedWindowOfFrontmostApplication() -> FocusedWindow? {
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let application = NSWorkspace.shared.frontmostApplication?.processIdentifier == currentProcessIdentifier
            ? lastExternalApplication
            : NSWorkspace.shared.frontmostApplication
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

        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axSize)
        let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axPosition)
        return sizeResult == .success && positionResult == .success
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
