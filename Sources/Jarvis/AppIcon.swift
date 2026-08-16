import AppKit

enum JarvisAppIconAppearance: String, CaseIterable {
    case light
    case dark

    var assetName: String {
        switch self {
        case .light:
            return "JarvisIconLight"
        case .dark:
            return "JarvisIconDark"
        }
    }
}

enum JarvisAppIconRenderer {
    static func image(for appearance: JarvisAppIconAppearance) -> NSImage? {
        return NSImage(named: appearance.assetName) ?? NSApp.applicationIconImage
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
