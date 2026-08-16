import AppKit

enum JarvisAppIconAppearance: String, CaseIterable {
    case light
    case dark
}

enum JarvisAppIconRenderer {
    static func image(for appearance: JarvisAppIconAppearance) -> NSImage? {
        guard let sourceImage = sourceImage() else { return nil }
        return renderedImage(sourceImage, appearance: appearance)
    }

    static func renderedImage(
        _ sourceImage: NSImage,
        appearance: JarvisAppIconAppearance
    ) -> NSImage? {
        guard appearance == .dark else { return sourceImage }

        var proposedRect = NSRect(origin: .zero, size: sourceImage.size)
        guard let source = sourceImage.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else {
            return nil
        }

        let width = source.width
        let height = source.height
        let bytesPerRow = width * 4
        var output: CGImage?
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else {
                return
            }

            context.interpolationQuality = .high
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

            let bytes = buffer.bindMemory(to: UInt8.self)
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                bytes[offset] = 255 - bytes[offset]
                bytes[offset + 1] = 255 - bytes[offset + 1]
                bytes[offset + 2] = 255 - bytes[offset + 2]
            }

            output = context.makeImage()
        }

        guard let output else { return nil }
        return NSImage(cgImage: output, size: sourceImage.size)
    }

    private static func sourceImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "Jarvis", withExtension: "icns") else {
            return NSApp.applicationIconImage
        }
        return NSImage(contentsOf: url)
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
