import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct SourceTextStyle {
    let fontSize: CGFloat
    let color: NSColor
}

private struct SourcePixelSampler {
    private struct ColorBucket {
        var count = 0
        var red = 0
        var green = 0
        var blue = 0

        mutating func append(red: UInt8, green: UInt8, blue: UInt8) {
            count += 1
            self.red += Int(red)
            self.green += Int(green)
            self.blue += Int(blue)
        }

        var average: (CGFloat, CGFloat, CGFloat) {
            guard count > 0 else { return (0, 0, 0) }
            let divisor = CGFloat(count * 255)
            return (
                CGFloat(red) / divisor,
                CGFloat(green) / divisor,
                CGFloat(blue) / divisor
            )
        }
    }

    private let bytes: [UInt8]
    private let width: Int
    private let height: Int
    private let bytesPerRow: Int

    init?(image: CGImage) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let rawData = context.data else {
            return nil
        }

        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let byteCount = context.bytesPerRow * image.height
        self.bytes = Array(
            UnsafeBufferPointer(
                start: rawData.assumingMemoryBound(to: UInt8.self),
                count: byteCount
            )
        )
        self.width = image.width
        self.height = image.height
        self.bytesPerRow = context.bytesPerRow
    }

    func foregroundColor(in rect: CGRect) -> NSColor {
        let xStart = max(0, Int(floor(rect.minX)))
        let xEnd = min(width - 1, Int(ceil(rect.maxX)))
        let yStart = max(0, Int(floor(rect.minY)))
        let yEnd = min(height - 1, Int(ceil(rect.maxY)))
        guard xStart <= xEnd, yStart <= yEnd else { return .black }

        let step = max(1, Int(min(rect.width, rect.height) / 28))
        var buckets = [Int: ColorBucket]()
        var sampleCount = 0
        for y in stride(from: yStart, through: yEnd, by: step) {
            for x in stride(from: xStart, through: xEnd, by: step) {
                let pixel = pixel(x: x, y: y)
                guard pixel.alpha > 16 else { continue }
                let red = pixel.red / 16
                let green = pixel.green / 16
                let blue = pixel.blue / 16
                let key = (Int(red) << 8) | (Int(green) << 4) | Int(blue)
                buckets[key, default: ColorBucket()].append(
                    red: pixel.red,
                    green: pixel.green,
                    blue: pixel.blue
                )
                sampleCount += 1
            }
        }

        guard let background = buckets.max(by: { $0.value.count < $1.value.count })?.value.average else {
            return .black
        }

        let minimumCandidateCount = max(2, sampleCount / 2500)
        let candidate = buckets
            .filter { $0.value.count >= minimumCandidateCount }
            .max { lhs, rhs in
                foregroundScore(lhs.value, against: background) < foregroundScore(rhs.value, against: background)
            }?.value.average

        guard let candidate,
              colorDistance(candidate, background) > 0.035 else {
            return .black
        }
        return NSColor(
            calibratedRed: candidate.0,
            green: candidate.1,
            blue: candidate.2,
            alpha: 1
        )
    }

    private func pixel(x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        let clampedX = min(max(x, 0), width - 1)
        let clampedY = min(max(y, 0), height - 1)
        // Bitmap context rows are top-down while Vision bounding boxes use a
        // bottom-left origin. Convert back before sampling the source color.
        let row = height - 1 - clampedY
        let offset = row * bytesPerRow + clampedX * 4
        return (
            bytes[offset],
            bytes[offset + 1],
            bytes[offset + 2],
            bytes[offset + 3]
        )
    }

    private func foregroundScore(
        _ bucket: ColorBucket,
        against background: (CGFloat, CGFloat, CGFloat)
    ) -> CGFloat {
        let distance = colorDistance(bucket.average, background)
        return distance * log(CGFloat(bucket.count) + 1)
    }

    private func colorDistance(
        _ lhs: (CGFloat, CGFloat, CGFloat),
        _ rhs: (CGFloat, CGFloat, CGFloat)
    ) -> CGFloat {
        sqrt(
            pow(lhs.0 - rhs.0, 2)
                + pow(lhs.1 - rhs.1, 2)
                + pow(lhs.2 - rhs.2, 2)
        )
    }
}

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
        let pixelSampler = SourcePixelSampler(image: sourceImage)
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
                let style = sourceStyle(
                    for: block.text,
                    in: sourceRect,
                    sampler: pixelSampler
                )
                drawReplacement(
                    translation,
                    in: rect,
                    sourceFontSize: style.fontSize,
                    textColor: style.color,
                    context: context
                )
            }
        } else if !translatedLines.isEmpty, let firstRect = blurRects.first {
            // A model may slightly change the line count. Keep the translation inside
            // the blurred OCR area instead of putting it in a separate result panel.
            let unionRect = blurRects.dropFirst().reduce(firstRect) { $0.union($1) }
            let styles = zip(ocrResult.blocks, blurRects).map { block, rect in
                sourceStyle(for: block.text, in: rect, sampler: pixelSampler)
            }
            drawReplacement(
                translatedText,
                in: unionRect.insetBy(dx: -6, dy: -4),
                sourceFontSize: median(styles.map(\.fontSize)),
                textColor: averageColor(styles.map(\.color)),
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
        sourceFontSize: CGFloat,
        textColor: NSColor,
        context: CGContext
    ) {
        context.setFillColor(NSColor.white.withAlphaComponent(0.18).cgColor)
        context.fill(rect)
        let textRect = rect.insetBy(dx: 8, dy: 4)
        let fontSize = fittedFontSize(
            text,
            in: textRect,
            startingAt: sourceFontSize
        )
        drawText(
            text,
            in: textRect,
            context: context,
            color: textColor,
            fontSize: fontSize
        )
    }

    private static func sourceStyle(
        for text: String,
        in sourceRect: CGRect,
        sampler: SourcePixelSampler?
    ) -> SourceTextStyle {
        SourceTextStyle(
            fontSize: estimatedSourceFontSize(for: text, in: sourceRect),
            color: sampler?.foregroundColor(in: sourceRect) ?? .black
        )
    }

    static func estimatedSourceFontSize(for text: String, in sourceRect: CGRect) -> CGFloat {
        let lineBasedSize = estimatedSourceFontSize(forLineHeight: sourceRect.height)
        guard !text.isEmpty, sourceRect.width > 0, lineBasedSize > 0 else {
            return lineBasedSize
        }

        let measured = measuredNaturalTextSize(text, fontSize: lineBasedSize)
        guard measured.width > 0, measured.height > 0 else { return lineBasedSize }
        let widthBasedSize = lineBasedSize * sourceRect.width / measured.width
        let heightBasedSize = lineBasedSize * sourceRect.height / measured.height
        return max(6, min(widthBasedSize, heightBasedSize))
    }

    static func estimatedSourceTextColor(
        for sourceData: Data,
        boundingBox: CGRect
    ) -> NSColor {
        guard let sourceImage = image(from: sourceData),
              let sampler = SourcePixelSampler(image: sourceImage) else {
            return .black
        }
        let sourceRect = pixelRect(
            for: boundingBox,
            width: sourceImage.width,
            height: sourceImage.height
        )
        return sampler.foregroundColor(in: sourceRect)
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
        while size > 6 {
            let measured = measuredTextSize(text, fontSize: size, width: rect.width)
            if measured.width <= rect.width + 1 && measured.height <= rect.height + 1 {
                return size
            }
            size -= 0.5
        }
        return 6
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

    private static func measuredNaturalTextSize(_ text: String, fontSize: CGFloat) -> CGSize {
        let attributedText = makeAttributedText(text, fontSize: fontSize, color: .black)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        return CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedText.length),
            nil,
            CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            ),
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

    private static func averageColor(_ colors: [NSColor]) -> NSColor {
        let components = colors.compactMap { color -> (CGFloat, CGFloat, CGFloat, CGFloat)? in
            guard let rgb = color.usingColorSpace(.deviceRGB) else { return nil }
            return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent)
        }
        guard !components.isEmpty else { return .black }
        let count = CGFloat(components.count)
        return NSColor(
            calibratedRed: components.reduce(0) { $0 + $1.0 } / count,
            green: components.reduce(0) { $0 + $1.1 } / count,
            blue: components.reduce(0) { $0 + $1.2 } / count,
            alpha: components.reduce(0) { $0 + $1.3 } / count
        )
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
