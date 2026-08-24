import AppKit

extension AppModel {
    func applyWindowLayout(_ layout: WindowLayout) {
        windowLayoutController?.apply(layout)
    }

    func refreshWindowLayoutAccessibility() {
        windowLayoutAccessibilityTrusted = windowLayoutController?.refreshAccessibilityStatus() ?? false
    }

    func openWindowLayoutAccessibilitySettings() {
        windowLayoutController?.openAccessibilitySettings()
        statusMessage = "请在系统设置的辅助功能中允许贾维斯"
    }
}
