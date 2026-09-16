import AVFoundation

extension AppModel {
    var hasAllRequiredPermissions: Bool {
        screenCapturePermissionGranted
            && accessibilityPermissionGranted
            && microphonePermissionGranted
            && cameraPermissionGranted
    }

    func isRequiredPermissionGranted(_ permission: JarvisRequiredPermission) -> Bool {
        switch permission {
        case .screenCapture: screenCapturePermissionGranted
        case .accessibility: accessibilityPermissionGranted
        case .microphone: microphonePermissionGranted
        case .camera: cameraPermissionGranted
        }
    }

    @discardableResult
    func requireAllPermissions() -> Bool {
        refreshPermissionStatus()
        guard hasAllRequiredPermissions else {
            // Reopening the window is not enough on its own: the gate stays
            // dismissed until something asks for it again.
            isPermissionGatePresented = true
            JarvisMenuBarController.shared.reopenMainWindow()
            return false
        }
        return true
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
        }
        return granted
    }

    func requestAccessibilityPermission() {
        let granted = windowLayoutController?.requestAccessibilityAccess() ?? false
        refreshPermissionStatus()
        statusMessage = granted
            ? "辅助功能权限已开启"
            : "请在系统设置的辅助功能中开启贾维斯"
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
        guard !JarvisPrivacyPermissionAccess.isMediaAccessGranted(for: mediaType) else {
            refreshPermissionStatus()
            return
        }

        if AVCaptureDevice.authorizationStatus(for: mediaType) == .denied
            || AVCaptureDevice.authorizationStatus(for: mediaType) == .restricted
        {
            JarvisPrivacyPermissionAccess.openSettings(for: privacyPermission)
            return
        }

        JarvisPrivacyPermissionAccess.requestMediaAccess(for: mediaType) { [weak self] granted in
            guard let self else { return }
            let mediaName = privacyPermission == .microphone ? "麦克风" : "摄像头"
            refreshPermissionStatus()
            statusMessage = granted
                ? "\(mediaName)权限已开启"
                : "请在系统设置中开启\(mediaName)权限"
        }
    }
}
