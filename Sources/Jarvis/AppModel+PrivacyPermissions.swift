import AVFoundation
import Foundation

struct JarvisTaskPermissionPrompt: Equatable {
    let permission: JarvisRequiredPermission

    var title: String {
        switch permission {
        case .screenCapture: "截图需要屏幕录制权限"
        case .accessibility: "窗口布局需要辅助功能权限"
        case .microphone: "会议记录需要麦克风权限"
        case .camera: "此功能需要摄像头权限"
        }
    }

    var message: String {
        switch permission {
        case .screenCapture: "macOS 需要授予屏幕录制权限，Jarvis 才能读取你选择的屏幕区域并完成截图。"
        case .accessibility: "macOS 需要授予辅助功能权限，Jarvis 才能调整其他应用窗口的位置和大小。"
        case .microphone: "macOS 需要授予麦克风权限，Jarvis 才能录制会议中的声音。"
        case .camera: "macOS 需要授予摄像头权限，Jarvis 才能使用摄像头。"
        }
    }
}

extension AppModel {
    func isRequiredPermissionGranted(_ permission: JarvisRequiredPermission) -> Bool {
        switch permission {
        case .screenCapture: screenCapturePermissionGranted
        case .accessibility: accessibilityPermissionGranted
        case .microphone: microphonePermissionGranted
        case .camera: cameraPermissionGranted
        }
    }

    func promptForTaskPermission(_ permission: JarvisRequiredPermission) {
        refreshPermissionStatus()
        guard !isRequiredPermissionGranted(permission) else { return }
        taskPermissionPrompt = JarvisTaskPermissionPrompt(permission: permission)
        JarvisMenuBarController.shared.reopenMainWindow()
    }

    func handleTaskPermissionPromptAction() {
        guard let prompt = taskPermissionPrompt else { return }
        requestRequiredPermission(prompt.permission)
    }

    func refreshPermissionStatus() {
        screenCapturePermissionGranted = screenshotController.hasScreenCaptureAccess
        accessibilityPermissionGranted = windowLayoutController?.isAccessibilityTrusted ?? false
        microphonePermissionGranted = JarvisPrivacyPermissionAccess.isMicrophoneTrusted()
        cameraPermissionGranted = JarvisPrivacyPermissionAccess.isCameraTrusted()
    }

    func requestRequiredPermission(_ permission: JarvisRequiredPermission) {
        switch permission {
        case .screenCapture:
            _ = requestScreenCapturePermission()
        case .accessibility:
            requestAccessibilityPermission()
        case .microphone:
            requestMicrophonePermission()
        case .camera:
            requestCameraPermission()
        }
    }

    @discardableResult
    func requestScreenCapturePermission() -> Bool {
        let granted = screenshotController.requestScreenCaptureAccess()
        refreshPermissionStatus()
        if !granted {
            screenshotController.openScreenCaptureSettings()
            showToast("请在系统设置的屏幕录制中开启贾维斯")
        } else {
            showToast("屏幕录制权限已开启")
        }
        return granted
    }

    func requestAccessibilityPermission() {
        let granted = windowLayoutController?.requestAccessibilityAccess() ?? false
        refreshPermissionStatus()
        statusMessage = granted
            ? "辅助功能权限已开启"
            : "请在系统设置的辅助功能中开启贾维斯"
        showToast(statusMessage)
    }

    func requestMicrophonePermission() {
        requestMediaPermission(for: .audio, privacyPermission: .microphone)
    }

    func requestCameraPermission() {
        requestMediaPermission(for: .video, privacyPermission: .camera)
    }

    private func requestMediaPermission(
        for mediaType: AVMediaType,
        privacyPermission: JarvisPrivacyPermission
    ) {
        JarvisPrivacyPermissionAccess.requestMediaAccess(for: mediaType) { [weak self] granted in
            guard let self else { return }
            let mediaName = privacyPermission == .microphone ? "麦克风" : "摄像头"
            refreshPermissionStatus()
            if granted, taskPermissionPrompt?.permission == privacyPermission.requiredPermission {
                taskPermissionPrompt = nil
            }
            statusMessage = granted
                ? "\(mediaName)权限已开启"
                : "请在系统设置中开启\(mediaName)权限"
            showToast(statusMessage)
            if !granted {
                JarvisPrivacyPermissionAccess.openSettings(for: privacyPermission)
            }
        }
    }
}

private extension JarvisPrivacyPermission {
    var requiredPermission: JarvisRequiredPermission {
        switch self {
        case .screenCapture: .screenCapture
        case .accessibility: .accessibility
        case .microphone: .microphone
        case .camera: .camera
        }
    }
}
