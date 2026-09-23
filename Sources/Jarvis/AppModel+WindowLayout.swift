import AppKit

extension AppModel {
    func applyWindowLayout(_ layout: WindowLayout) {
        refreshPermissionStatus()
        guard accessibilityPermissionGranted else {
            promptForTaskPermission(.accessibility)
            return
        }
        windowLayoutController?.apply(layout)
    }
}
