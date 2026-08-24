extension AppModel {
    func refreshPermissionStatus() {
        screenCapturePermissionGranted = screenshotController.hasScreenCaptureAccess
        accessibilityPermissionGranted = windowLayoutController?.isAccessibilityTrusted ?? false
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
}
