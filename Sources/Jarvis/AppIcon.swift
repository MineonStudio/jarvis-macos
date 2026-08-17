import AppKit

enum JarvisAppIcon: String, CaseIterable, Identifiable {
    case standard = "AppIcon"
    case inverted = "AppIconInverted"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .standard: "默认"
        case .inverted: "反色"
        }
    }
}

extension AppModel {
    func updateAppIcon(_ icon: JarvisAppIcon) {
        guard applyAppIcon(icon) else { return }
        appIcon = icon
        UserDefaults.standard.set(icon.rawValue, forKey: appIconKey)
    }

    func loadAppIconPreference() {
        guard let rawValue = UserDefaults.standard.string(forKey: appIconKey),
              let icon = JarvisAppIcon(rawValue: rawValue)
        else {
            return
        }

        if applyAppIcon(icon) {
            appIcon = icon
        }
    }

    private func applyAppIcon(_ icon: JarvisAppIcon) -> Bool {
        if icon == .standard {
            // nil restores the primary CFBundleIconName asset.
            NSApp.applicationIconImage = nil
            NSApp.dockTile.display()
            return true
        }

        guard let image = NSImage(named: NSImage.Name(icon.rawValue)) else {
            showToast("反色图标资源加载失败")
            return false
        }

        NSApp.applicationIconImage = image
        NSApp.dockTile.display()
        return true
    }
}
