import AppKit

extension AppModel {
    func applyWindowLayout(_ layout: WindowLayout) {
        windowLayoutController?.apply(layout)
    }
}
