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

        let blurRects = ocrResult.blocks.map {
            pixelRect(for: $0.boundingBox, width: width, height: height)
        }
        if let blurredImage = blurredImage(sourceImage, radius: 10), !blurRects.isEmpty {
            context.saveGState()
            blurRects.forEach { context.addRect($0) }
            context.clip()
            context.draw(blurredImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            context.restoreGState()
        }

        if translatedLines.count == ocrResult.blocks.count, !translatedLines.isEmpty {
            for (block, translation) in zip(ocrResult.blocks, translatedLines) {
                let sourceRect = pixelRect(for: block.boundingBox, width: width, height: height)
                let rect = sourceRect
                    .insetBy(dx: -6, dy: -4)
                drawReplacement(
                    translation,
                    in: rect,
                    sourceLineHeight: sourceRect.height,
                    context: context
                )
            }
        } else if !translatedLines.isEmpty, let firstRect = blurRects.first {
            // A model may slightly change the line count. Keep the translation inside
            // the blurred OCR area instead of putting it in a separate result panel.
            let unionRect = blurRects.dropFirst().reduce(firstRect) { $0.union($1) }
            drawReplacement(
                translatedText,
                in: unionRect.insetBy(dx: -6, dy: -4),
                sourceLineHeight: median(
                    ocrResult.blocks.map {
                        pixelRect(for: $0.boundingBox, width: width, height: height).height
                    }
                ),
                context: context
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

    static func composite(
        baseData: Data,
        translatedSelectionData: Data,
        outputRect: CGRect,
        canvasSize: CGSize
    ) -> Data? {
        guard let baseImage = image(from: baseData),
              let translatedImage = image(from: translatedSelectionData),
              canvasSize.width > 0,
              canvasSize.height > 0 else { return nil }

        let width = baseImage.width
        let height = baseImage.height
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
        context.draw(baseImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let targetRect = CGRect(
            x: outputRect.minX / canvasSize.width * CGFloat(width),
            y: outputRect.minY / canvasSize.height * CGFloat(height),
            width: outputRect.width / canvasSize.width * CGFloat(width),
            height: outputRect.height / canvasSize.height * CGFloat(height)
        )
        context.draw(translatedImage, in: targetRect)

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
            y: normalizedRect.minY * CGFloat(height),
            width: normalizedRect.width * CGFloat(width),
            height: normalizedRect.height * CGFloat(height)
        )
    }

    private static func drawReplacement(
        _ text: String,
        in rect: CGRect,
        sourceLineHeight: CGFloat,
        context: CGContext
    ) {
        context.setFillColor(NSColor.white.withAlphaComponent(0.18).cgColor)
        context.fill(rect)
        let textRect = rect.insetBy(dx: 8, dy: 4)
        let fontSize = fittedFontSize(
            text,
            in: textRect,
            startingAt: estimatedSourceFontSize(forLineHeight: sourceLineHeight)
        )
        drawText(
            text,
            in: textRect,
            context: context,
            color: .black,
            fontSize: fontSize
        )
    }

    static func estimatedSourceFontSize(forLineHeight lineHeight: CGFloat) -> CGFloat {
        guard lineHeight > 0 else { return 8 }
        let probeFont = CTFontCreateWithName("PingFang SC" as CFString, 1, nil)
        let metrics = CTFontGetAscent(probeFont)
            + CTFontGetDescent(probeFont)
            + CTFontGetLeading(probeFont)
        return max(6, lineHeight / max(metrics, 1) * 0.92)
    }

    private static func fittedFontSize(
        _ text: String,
        in rect: CGRect,
        startingAt startingSize: CGFloat
    ) -> CGFloat {
        var size = startingSize
        while size > 8 {
            let measured = measuredTextSize(text, fontSize: size, width: rect.width)
            if measured.width <= rect.width + 1 && measured.height <= rect.height + 1 {
                return size
            }
            size -= 1
        }
        return 8
    }

    private static func measuredTextSize(_ text: String, fontSize: CGFloat, width: CGFloat) -> CGSize {
        let attributedText = makeAttributedText(text, fontSize: fontSize, color: .black)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        return CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedText.length),
            nil,
            CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
            nil
        )
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.filter { $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted[sorted.count / 2]
        if sorted.count.isMultiple(of: 2) {
            return (sorted[sorted.count / 2 - 1] + middle) / 2
        }
        return middle
    }

    private static func blurredImage(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        return CIContext(options: nil).createCGImage(output, from: input.extent)
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        context: CGContext,
        color: NSColor,
        fontSize: CGFloat
    ) {
        guard !text.isEmpty, rect.width > 0, rect.height > 0 else { return }
        let attributedText = makeAttributedText(text, fontSize: fontSize, color: color)
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

    private static func makeAttributedText(
        _ text: String,
        fontSize: CGFloat,
        color: NSColor
    ) -> NSAttributedString {
        let font = CTFontCreateWithName("PingFang SC" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor
        ]
        return NSAttributedString(string: text, attributes: attributes)
    }
}
