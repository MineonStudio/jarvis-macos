import AppKit
import ApplicationServices
import CoreGraphics

enum JarvisPrivacyPermission {
    case screenCapture
    case accessibility

    var settingsAnchor: String {
        switch self {
        case .screenCapture: "Privacy_ScreenCapture"
        case .accessibility: "Privacy_Accessibility"
        }
    }
}

enum JarvisPrivacyPermissionAccess {
    static func isScreenCaptureTrusted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibilityAccess() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            openSettings(for: .accessibility)
        }
        return trusted
    }

    @discardableResult
    static func openSettings(for permission: JarvisPrivacyPermission) -> Bool {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(permission.settingsAnchor)",
            "x-apple.systempreferences:com.apple.preference.security?\(permission.settingsAnchor)"
        ].compactMap(URL.init(string:))

        for url in urls where NSWorkspace.shared.open(url) {
            NSApp.activate(ignoringOtherApps: true)
            return true
        }
        return false
    }
}
