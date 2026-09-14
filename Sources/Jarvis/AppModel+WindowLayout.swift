import AppKit

extension AppModel {
    func applyWindowLayout(_ layout: WindowLayout) {
        guard requireAllPermissions() else { return }
        windowLayoutController?.apply(layout)
    }
}
