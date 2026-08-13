import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ScreenshotTranslationRenderer {
    static func render(
        sourceData: Data,
        ocrResult: ScreenshotOCRResult,
        translatedText: String
    ) -> Data? {
        guard let sourceImage = image(from: sourceData),
              sourceImage.width > 0,
              sourceImage.height > 0 else { return nil }

        let width = sourceImage.width
        let height = sourceImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let translatedLines = translatedText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if translatedLines.count == ocrResult.blocks.count, !translatedLines.isEmpty {
            for (block, translation) in zip(ocrResult.blocks, translatedLines) {
                let rect = pixelRect(for: block.boundingBox, width: width, height: height)
                    .insetBy(dx: -6, dy: -4)
                drawReplacement(translation, in: rect, context: context)
            }
        } else {
            let panelHeight = min(CGFloat(height) * 0.36, max(120, CGFloat(translatedLines.count) * 34 + 44))
            let panelRect = CGRect(x: 0, y: 0, width: CGFloat(width), height: panelHeight)
            context.setFillColor(NSColor.black.withAlphaComponent(0.82).cgColor)
            context.fill(panelRect)
            drawText(
                translatedText,
                in: panelRect.insetBy(dx: 24, dy: 18),
                context: context,
                color: .white,
                fontSize: 22
            )
        }

        guard let outputImage = context.makeImage() else { return nil }
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, outputImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return outputData as Data
    }

    private static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func pixelRect(for normalizedRect: CGRect, width: Int, height: Int) -> CGRect {
        CGRect(
            x: normalizedRect.minX * CGFloat(width),
            y: (1 - normalizedRect.maxY) * CGFloat(height),
            width: normalizedRect.width * CGFloat(width),
            height: normalizedRect.height * CGFloat(height)
        )
    }

    private static func drawReplacement(_ text: String, in rect: CGRect, context: CGContext) {
        context.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.fill(rect)
        context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.65).cgColor)
        context.setLineWidth(2)
        context.stroke(rect)
        drawText(
            text,
            in: rect.insetBy(dx: 8, dy: 4),
            context: context,
            color: .black,
            fontSize: max(12, min(26, rect.height * 0.62))
        )
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        context: CGContext,
        color: NSColor,
        fontSize: CGFloat
    ) {
        guard !text.isEmpty, rect.width > 0, rect.height > 0 else { return }
        let font = CTFontCreateWithName("PingFang SC" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributedText.length),
            path,
            nil
        )
        CTFrameDraw(frame, context)
    }
}
