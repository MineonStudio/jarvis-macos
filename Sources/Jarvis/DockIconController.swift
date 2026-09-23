import AppKit
import Foundation

@MainActor
final class JarvisDockIconController {
    static let shared = JarvisDockIconController()

    private var imageCache: [JarvisAppIconAppearance: NSImage] = [:]

    func apply(appearance: JarvisAppIconAppearance, isSystemDark: Bool) {
        let resolvedAppearance = appearance.resolvedVariant(isSystemDark: isSystemDark)
        applyBundledIcon(
            for: resolvedAppearance,
            resourceName: resolvedAppearance == .dark ? "jarvis-dark" : "jarvis-light"
        )
    }

    func previewImage(
        for appearance: JarvisAppIconAppearance,
        isSystemDark: Bool
    ) -> NSImage? {
        let resolvedAppearance = appearance.resolvedVariant(isSystemDark: isSystemDark)
        return image(
            for: resolvedAppearance,
            resourceName: resolvedAppearance == .dark ? "jarvis-dark" : "jarvis-light"
        )
    }

    private func restoreSystemIcon() {
        // Keep a safe fallback when a built bundle is missing the explicit
        // light/dark resources required for deterministic Dock rendering.
        NSApp.applicationIconImage = nil
        NSApp.dockTile.display()
    }

    private func applyBundledIcon(
        for appearance: JarvisAppIconAppearance,
        resourceName: String
    ) {
        guard let image = image(for: appearance, resourceName: resourceName) else {
            // Never leave an icon from a previous preference active when a
            // production bundle is missing its runtime icon resources.
            restoreSystemIcon()
            return
        }

        image.isTemplate = false
        NSApp.applicationIconImage = image
        NSApp.dockTile.display()
    }

    private func image(
        for appearance: JarvisAppIconAppearance,
        resourceName: String
    ) -> NSImage? {
        if let cachedImage = imageCache[appearance] {
            return cachedImage
        }

        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "icns",
            subdirectory: "DockIcons"
        ), let image = NSImage(contentsOf: url) else {
            JarvisLog.error(
                category: .lifecycle,
                event: "dockIcon.load.failed",
                fields: ["resource": resourceName]
            )
            return nil
        }

        imageCache[appearance] = image
        return image
    }
}
