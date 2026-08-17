import AppKit

enum JarvisAppIconAppearance: String, CaseIterable {
    case light
    case dark

    var assetName: String {
        switch self {
        case .light:
            "JarvisIconLight"
        case .dark:
            "JarvisIconDark"
        }
    }
}

enum JarvisAppIconRenderer {
    static let standardDockIconSize = NSSize(width: 128, height: 128)

    static func image(for appearance: JarvisAppIconAppearance) -> NSImage? {
        guard let sourceImage = NSImage(named: appearance.assetName) ?? NSApp.applicationIconImage else {
            return nil
        }

        let image = sourceImage.copy() as? NSImage ?? sourceImage
        image.size = standardDockIconSize
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
