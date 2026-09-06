import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics

enum JarvisPrivacyPermission: Equatable {
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
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: mediaType) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    static func requestMediaAccess(
        for mediaType: AVMediaType,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            Task { @MainActor in completion(true) }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: mediaType) { granted in
                Task { @MainActor in
                    completion(granted)
                }
            }
        case .denied, .restricted:
            Task { @MainActor in completion(false) }
        @unknown default:
            Task { @MainActor in completion(false) }
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
