import AppKit
import SwiftUI

enum MeetingRecordingStyle {
    static let foregroundColor = Color.white
    static let foregroundNSColor = NSColor.white
    static let backgroundNSColor = NSColor(
        calibratedRed: 0.88,
        green: 0.29,
        blue: 0.27,
        alpha: 1
    )
    static let backgroundColor = Color(nsColor: backgroundNSColor)
    static let idleBackgroundOpacity: CGFloat = 0.14
    static let horizontalPadding: CGFloat = 12
    static let controlHeight: CGFloat = 32
    static let fontSize: CGFloat = 12
    static let statusBarImageHeight: CGFloat = 22
    static let statusBarHorizontalPadding: CGFloat = 10
    static let statusBarIconSize: CGFloat = 13
    static let statusBarIconSpacing: CGFloat = 6

    static var font: Font {
        .system(size: fontSize, weight: .medium, design: .monospaced)
    }

    static var nsFont: NSFont {
        .monospacedSystemFont(ofSize: fontSize, weight: .medium)
    }

    /// Compact visual label used by the in-app and menu-bar recording indicators.
    static func displayTitle(for duration: TimeInterval) -> String {
        formatDuration(duration)
    }

    /// Full action label retained for the menu command and accessibility text.
    static func stopActionTitle(for duration: TimeInterval) -> String {
        "停止录制 \(formatDuration(duration))"
    }

    static func formatDuration(_ duration: TimeInterval) -> String {
        formatTimestamp(duration, roundedDown: true)
    }

    static func formatTimestamp(_ time: TimeInterval, roundedDown: Bool = false) -> String {
        let totalSeconds = max(0, Int(roundedDown ? time.rounded(.down) : time.rounded()))
        if totalSeconds >= 3600 {
            return String(
                format: "%d:%02d:%02d",
                totalSeconds / 3600,
                (totalSeconds / 60) % 60,
                totalSeconds % 60
            )
        }
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    static func makeStatusBarImage(for duration: TimeInterval) -> NSImage {
        let title = displayTitle(for: duration)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: foregroundNSColor,
            .font: nsFont
        ]
        let textSize = (title as NSString).size(withAttributes: textAttributes)
        let icon = NSImage(
            systemSymbolName: "mic.fill",
            accessibilityDescription: "录音中"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(
                pointSize: statusBarIconSize,
                weight: .medium,
                scale: .small
            ).applying(
                NSImage.SymbolConfiguration(paletteColors: [foregroundNSColor])
            )
        )
        let iconWidth = icon?.size.width ?? statusBarIconSize
        let imageSize = NSSize(
            width: statusBarHorizontalPadding * 2 + iconWidth + statusBarIconSpacing + textSize.width,
            height: statusBarImageHeight
        )
        let scale = max(NSScreen.main?.backingScaleFactor ?? 2, 2)
        let pixelWidth = Int((imageSize.width * scale).rounded(.up))
        let pixelHeight = Int((imageSize.height * scale).rounded(.up))
        let image = NSImage(size: imageSize)

        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return image
        }
        representation.size = imageSize
        image.addRepresentation(representation)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)

        backgroundNSColor.setFill()
        NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: imageSize),
            xRadius: imageSize.height / 2,
            yRadius: imageSize.height / 2
        ).fill()

        if let icon {
            let iconRect = NSRect(
                x: statusBarHorizontalPadding,
                y: (imageSize.height - icon.size.height) / 2,
                width: icon.size.width,
                height: icon.size.height
            )
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
        }

        let textX = statusBarHorizontalPadding + iconWidth + statusBarIconSpacing
        title.draw(
            at: NSPoint(x: textX, y: (imageSize.height - textSize.height) / 2),
            withAttributes: textAttributes
        )
        NSGraphicsContext.restoreGraphicsState()
        return image
    }
}
