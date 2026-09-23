import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics

enum JarvisPrivacyPermission: Hashable {
    case screenCapture
    case accessibility
    case microphone
    case camera

    var settingsAnchor: String {
        switch self {
        case .screenCapture: "Privacy_ScreenCapture"
        case .accessibility: "Privacy_Accessibility"
        case .microphone: "Privacy_Microphone"
        case .camera: "Privacy_Camera"
        }
    }
}

enum JarvisRequiredPermission: String, CaseIterable, Identifiable, Equatable {
    case screenCapture
    case accessibility
    case microphone
    case camera

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .screenCapture: "屏幕录制"
        case .accessibility: "辅助功能"
        case .microphone: "麦克风"
        case .camera: "摄像头"
        }
    }

    var systemImage: String {
        switch self {
        case .screenCapture: "rectangle.dashed.badge.record"
        case .accessibility: "accessibility"
        case .microphone: "mic.fill"
        case .camera: "camera.fill"
        }
    }

    var privacyPermission: JarvisPrivacyPermission {
        switch self {
        case .screenCapture: .screenCapture
        case .accessibility: .accessibility
        case .microphone: .microphone
        case .camera: .camera
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

    static func isMicrophoneTrusted() -> Bool {
        isMediaAccessGranted(for: .audio)
    }

    static func isCameraTrusted() -> Bool {
        isMediaAccessGranted(for: .video)
    }

    static func isMediaAccessGranted(for mediaType: AVMediaType) -> Bool {
        AVCaptureDevice.authorizationStatus(for: mediaType) == .authorized
    }

    static func requestMediaAccess(for mediaType: AVMediaType) async -> Bool {
        await AVCaptureDevice.requestAccess(for: mediaType)
    }

    static func requestMediaAccess(
        for mediaType: AVMediaType,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        AVCaptureDevice.requestAccess(for: mediaType) { granted in
            Task { @MainActor in
                completion(granted)
            }
        }
    }

    @discardableResult
    @MainActor
    static func requestAccessibilityAccess() -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            openSettings(for: .accessibility)
        }
        return trusted
    }

    @discardableResult
    @MainActor
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
