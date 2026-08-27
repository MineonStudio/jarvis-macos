import AppKit
import Foundation

@MainActor
final class JarvisDockIconController {
    static let shared = JarvisDockIconController()

    private var imageCache: [JarvisTheme: NSImage] = [:]

    func apply(theme: JarvisTheme, isSystemDark: Bool) {
        switch theme {
        case .system:
            applyBundledIcon(
                for: isSystemDark ? .dark : .light,
                resourceName: isSystemDark ? "jarvis-dark" : "jarvis-light"
            )
        case .light:
            applyBundledIcon(for: .light, resourceName: "jarvis-light")
        case .dark:
            applyBundledIcon(for: .dark, resourceName: "jarvis-dark")
        }
    }

    private func applyBundledIcon(for theme: JarvisTheme, resourceName: String) {
        guard let image = image(for: theme, resourceName: resourceName) else {
            // Never leave an icon from a previous preference active when a
            // production bundle is missing its runtime icon resources.
            NSApp.applicationIconImage = nil
            NSApp.dockTile.display()
            return
        }

        image.isTemplate = false
        NSApp.applicationIconImage = image
        NSApp.dockTile.display()
    }

    private func image(for theme: JarvisTheme, resourceName: String) -> NSImage? {
        if let cachedImage = imageCache[theme] {
            return cachedImage
        }

        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "icns",
            subdirectory: "DockIcons"
        ), let image = NSImage(contentsOf: url) else {
            NSLog("Jarvis could not load Dock icon resource: \(resourceName).icns")
            return nil
        }

        imageCache[theme] = image
        return image
    }
}
