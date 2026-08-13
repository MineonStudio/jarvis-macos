import AppKit
import Carbon.HIToolbox
import OSLog
import SwiftUI

struct ScreenshotShortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt

    // F1 is the default global shortcut for screenshot capture.
    static let `default` = ScreenshotShortcut(
        keyCode: 122, // F1
        modifiers: 0
    )

    // Previous builds used F2 and then ⌘⇧J for screenshot capture while the
    // clipboard panel was being introduced. Both built-in values migrate to F1.
    static let legacyDefault = ScreenshotShortcut(
        keyCode: 120, // F2
        modifiers: 0
    )

    static let previousDefault = ScreenshotShortcut(
        keyCode: 38, // J
        modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue
    )

    static let clipboardDefault = ScreenshotShortcut(
        keyCode: 120, // F2
        modifiers: 0
    )

    private static let functionKeyCodes: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111
    ]

    /// When macOS is configured to use the F-keys as media keys, the physical
    /// F1/F2 keys do not arrive as `.keyDown` events. They arrive as
    /// `NX_SYSDEFINED` events carrying the brightness-down/brightness-up key
    /// types instead. Keep the translation here so the shortcut manager can
    /// support both keyboard settings without asking users to change macOS.
    static func functionKeyCode(forSystemDefinedData data: UInt32, subtype: Int) -> UInt16? {
        guard subtype == 8 else {
            return nil
        }

        let keyType = (data >> 16) & 0xFF
        let keyState = (data >> 8) & 0xFF
        guard keyState == 0x0A else { return nil }

        switch keyType {
        case 2: return 122 // Brightness down = physical F1
        case 3: return 120 // Brightness up = physical F2
        default: return nil
        }
    }

    fileprivate static func functionKeyCode(forSystemDefinedEvent event: NSEvent) -> UInt16? {
        guard event.type == .systemDefined else { return nil }
        return functionKeyCode(
            forSystemDefinedData: UInt32(truncatingIfNeeded: event.data1),
            subtype: Int(event.subtype.rawValue)
        )
    }

    init(keyCode: UInt16, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let allowed = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // F-keys are valid standalone shortcuts. Other keys still require at
        // least one modifier so an accidental character press is not bound.
        guard !allowed.isEmpty || Self.functionKeyCodes.contains(event.keyCode) else {
            return nil
        }
        self.init(keyCode: event.keyCode, modifiers: allowed.rawValue)
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    fileprivate func matches(_ event: NSEvent) -> Bool {
        if let systemDefinedKeyCode = Self.functionKeyCode(forSystemDefinedEvent: event) {
            return keyCode == systemDefinedKeyCode && modifiers == 0
        }

        guard event.type == .keyDown else { return false }
        let allowed = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return event.keyCode == keyCode && allowed.rawValue == modifiers
    }

    var displayString: String {
        let flags = modifierFlags
        var value = ""
        if flags.contains(.control) { value += "⌃" }
        if flags.contains(.option) { value += "⌥" }
        if flags.contains(.shift) { value += "⇧" }
        if flags.contains(.command) { value += "⌘" }
        return value + Self.keyNames[keyCode, default: "键\(keyCode)"]
    }

    fileprivate var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        let flags = modifierFlags
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 50: "`", 36: "↩", 48: "⇥", 49: "空格",
        51: "⌫", 53: "Esc", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]
}

enum ScreenshotShortcutValidation: Equatable {
    case available
    case conflict
    case unavailable

    var message: String {
        switch self {
        case .available:
            return ""
        case .conflict:
            return "快捷键与其他应用或系统快捷键冲突"
        case .unavailable:
            return "当前快捷键无法注册，请换一个组合键"
        }
    }
}

final class ScreenshotShortcutManager {
    private static let logger = Logger(subsystem: "com.jarvis.mac", category: "shortcuts")
    private let handler: () -> Void
    private let hotKeyID: UInt32
    private var binding: ScreenshotShortcut
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var eventHandlerUPP: EventHandlerUPP?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var globalSystemDefinedMonitor: Any?
    private var localSystemDefinedMonitor: Any?
    private var lastTriggeredAt = Date.distantPast

    init(binding: ScreenshotShortcut, hotKeyID: UInt32 = 1, handler: @escaping () -> Void) {
        self.binding = binding
        self.hotKeyID = hotKeyID
        self.handler = handler
        installEventHandler()
        _ = registerHotKey()
        installFallbackKeyMonitors()
    }

    deinit {
        unregisterHotKey()
        removeFallbackKeyMonitors()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    @discardableResult
    func update(_ binding: ScreenshotShortcut) -> Bool {
        unregisterHotKey()
        self.binding = binding
        return registerHotKey()
    }

    func validate(_ candidate: ScreenshotShortcut) -> ScreenshotShortcutValidation {
        guard candidate != binding else { return .available }

        let current = binding
        unregisterHotKey()
        let status = registerHotKey(for: candidate)
        unregisterHotKey()

        binding = current
        _ = registerHotKey()

        if status == noErr { return .available }
        if status == eventHotKeyExistsErr { return .conflict }
        return .unavailable
    }

    private func installEventHandler() {
        eventHandlerUPP = { _, event, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<ScreenshotShortcutManager>
                .fromOpaque(userData)
                .takeUnretainedValue()

            var eventHotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &eventHotKeyID
            )
            guard status == noErr else {
                return OSStatus(eventNotHandledErr)
            }
            guard eventHotKeyID.id == manager.hotKeyID else {
                // Two managers share the Carbon dispatcher target. Do not
                // consume the other manager's hotkey event.
                return OSStatus(eventNotHandledErr)
            }

            manager.triggerOnce()
            return noErr
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            eventHandlerUPP,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        if status != noErr {
            Self.logger.error("InstallEventHandler failed for hotKeyID=\(self.hotKeyID, privacy: .public), status=\(status, privacy: .public)")
        }
    }

    @discardableResult
    private func registerHotKey() -> Bool {
        let status = registerHotKey(for: binding)
        if status != noErr {
            Self.logger.error("RegisterEventHotKey failed for hotKeyID=\(self.hotKeyID, privacy: .public), keyCode=\(self.binding.keyCode, privacy: .public), modifiers=\(self.binding.modifiers, privacy: .public), status=\(status, privacy: .public)")
        }
        return status == noErr
    }

    @discardableResult
    private func registerHotKey(for binding: ScreenshotShortcut) -> OSStatus {
        let hotKeyID = EventHotKeyID(signature: 0x4A415256, id: self.hotKeyID)
        return RegisterEventHotKey(
            UInt32(binding.keyCode),
            binding.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKey
        )
    }

    private func unregisterHotKey() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }

    private func installFallbackKeyMonitors() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.binding.matches(event) else { return }
            self.triggerOnce()
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.binding.matches(event) else { return event }
            self.triggerOnce()
            return event
        }

        // A MacBook with "Use F1, F2, etc. keys as standard function keys"
        // disabled emits brightness media events for the physical F1/F2 keys.
        // Carbon registration and `.keyDown` monitors cannot see those events.
        globalSystemDefinedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard let self, self.binding.matches(event) else { return }
            self.triggerOnce()
        }
        localSystemDefinedMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard let self, self.binding.matches(event) else { return event }
            self.triggerOnce()
            return event
        }
    }

    private func removeFallbackKeyMonitors() {
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalSystemDefinedMonitor {
            NSEvent.removeMonitor(globalSystemDefinedMonitor)
            self.globalSystemDefinedMonitor = nil
        }
        if let localSystemDefinedMonitor {
            NSEvent.removeMonitor(localSystemDefinedMonitor)
            self.localSystemDefinedMonitor = nil
        }
    }

    private func triggerOnce() {
        let now = Date()
        guard now.timeIntervalSince(lastTriggeredAt) > 0.2 else { return }
        lastTriggeredAt = now
        DispatchQueue.main.async { [handler] in
            handler()
        }
    }
}

struct ShortcutRecorderControl: NSViewRepresentable {
    @Binding var shortcut: ScreenshotShortcut
    @Binding var isRecording: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(shortcut: $shortcut, isRecording: $isRecording)
    }

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.shortcut = shortcut
        view.isRecording = isRecording
        view.onShortcut = { value in
            context.coordinator.shortcut.wrappedValue = value
            context.coordinator.isRecording.wrappedValue = false
        }
        view.onRecordingChanged = { value in
            context.coordinator.isRecording.wrappedValue = value
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.shortcut = shortcut
        nsView.isRecording = isRecording
        nsView.needsDisplay = true
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    final class Coordinator {
        let shortcut: Binding<ScreenshotShortcut>
        let isRecording: Binding<Bool>

        init(shortcut: Binding<ScreenshotShortcut>, isRecording: Binding<Bool>) {
            self.shortcut = shortcut
            self.isRecording = isRecording
        }
    }
}

final class ShortcutRecorderNSView: NSView {
    var shortcut = ScreenshotShortcut.default
    var isRecording = false
    var onShortcut: ((ScreenshotShortcut) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let background = isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.22)
            : NSColor.controlBackgroundColor
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()

        let title = isRecording ? "按下快捷键…" : shortcut.displayString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let size = title.size(withAttributes: attributes)
        title.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        onRecordingChanged?(true)
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            isRecording = false
            onRecordingChanged?(false)
            needsDisplay = true
            return
        }

        guard let shortcut = ScreenshotShortcut(event: event) else {
            NSSound.beep()
            return
        }
        onShortcut?(shortcut)
        needsDisplay = true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        keyDown(with: event)
        return true
    }
}
