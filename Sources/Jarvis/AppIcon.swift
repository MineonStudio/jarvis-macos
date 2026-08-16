import AppKit
import SwiftUI

enum JarvisAppIconColor: String, CaseIterable, Identifiable {
    case red
    case orange
    case yellow
    case green
    case cyan
    case blue
    case purple

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .red: "红色"
        case .orange: "橙色"
        case .yellow: "黄色"
        case .green: "绿色"
        case .cyan: "青色"
        case .blue: "蓝色"
        case .purple: "紫色"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .red: NSColor(srgbRed: 0.88, green: 0.12, blue: 0.16, alpha: 1)
        case .orange: NSColor(srgbRed: 0.95, green: 0.39, blue: 0.04, alpha: 1)
        case .yellow: NSColor(srgbRed: 0.86, green: 0.64, blue: 0.02, alpha: 1)
        case .green: NSColor(srgbRed: 0.13, green: 0.62, blue: 0.24, alpha: 1)
        case .cyan: NSColor(srgbRed: 0.02, green: 0.60, blue: 0.63, alpha: 1)
        case .blue: NSColor(srgbRed: 0.10, green: 0.34, blue: 0.86, alpha: 1)
        case .purple: NSColor(srgbRed: 0.48, green: 0.20, blue: 0.72, alpha: 1)
        }
    }

    var swiftUIColor: Color {
        Color(nsColor: nsColor)
    }
}

enum JarvisAppIconRenderer {
    static func image(for color: JarvisAppIconColor) -> NSImage? {
        guard let sourceImage = sourceImage() else { return nil }
        return tintedImage(sourceImage, color: color)
    }

    static func tintedImage(_ sourceImage: NSImage, color: JarvisAppIconColor) -> NSImage? {
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

        guard let tintColor = color.nsColor.usingColorSpace(.deviceRGB) else {
            return nil
        }

        let tintRed = tintColor.redComponent
        let tintGreen = tintColor.greenComponent
        let tintBlue = tintColor.blueComponent

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
                let alpha = Double(bytes[offset + 3]) / 255
                guard alpha > 0 else { continue }

                let red = Double(bytes[offset]) / 255
                let green = Double(bytes[offset + 1]) / 255
                let blue = Double(bytes[offset + 2]) / 255
                let luminance = (red * 0.2126) + (green * 0.7152) + (blue * 0.0722)
                let mask = min(max(1 - luminance, 0), 1)

                bytes[offset] = UInt8(((red + ((tintRed - red) * mask)) * 255).rounded())
                bytes[offset + 1] = UInt8(((green + ((tintGreen - green) * mask)) * 255).rounded())
                bytes[offset + 2] = UInt8(((blue + ((tintBlue - blue) * mask)) * 255).rounded())
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
    static func apply(_ color: JarvisAppIconColor) {
        guard let image = JarvisAppIconRenderer.image(for: color) else { return }
        image.isTemplate = false
        NSApp.applicationIconImage = image
    }
}
