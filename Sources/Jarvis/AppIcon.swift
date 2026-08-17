import AppKit

enum JarvisAppIconAppearance: String, CaseIterable {
    case light
    case dark

    var iconResourceName: String {
        switch self {
        case .light:
            "AppIcon"
        case .dark:
            "AppIconDark"
        }
    }
}

enum JarvisAppIconRenderer {
    static func image(for appearance: JarvisAppIconAppearance) -> NSImage? {
        guard let url = Bundle.main.url(
            forResource: appearance.iconResourceName,
            withExtension: "icns"
        ) else {
            return NSApp.applicationIconImage
        }

        guard let image = NSImage(contentsOf: url) else {
            return nil
        }
        return image
    }
}

@MainActor
enum JarvisAppIconController {
    static func apply(_ appearance: JarvisAppIconAppearance) {
        guard let image = JarvisAppIconRenderer.image(for: appearance) else { return }
        image.isTemplate = false
        NSApp.applicationIconImage = image
    }
}
