import AVFoundation

extension AppModel {
    func refreshPermissionStatus() {
        screenCapturePermissionGranted = screenshotController.hasScreenCaptureAccess
        accessibilityPermissionGranted = windowLayoutController?.isAccessibilityTrusted ?? false
        microphonePermissionGranted = JarvisPrivacyPermissionAccess.isMicrophoneTrusted()
        cameraPermissionGranted = JarvisPrivacyPermissionAccess.isCameraTrusted()
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
