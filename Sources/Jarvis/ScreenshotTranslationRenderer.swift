import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct SourceTextStyle {
    let fontSize: CGFloat
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
        bytes = Array(
            UnsafeBufferPointer(
                start: rawData.assumingMemoryBound(to: UInt8.self),
                count: byteCount
            )
        )
        width = image.width
        height = image.height
        bytesPerRow = context.bytesPerRow
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
              colorDistance(candidate, background) > 0.035
        else {
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
        // Bitmap context rows are top-down. Convert from the renderer's
        // bottom-left pixel coordinate to the bitmap row before sampling.
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
        result: ScreenshotTranslationResult,
        isDarkMode: Bool = false
    ) -> Data? {
        render(
            sourceData: sourceData,
            blocks: result.blocks,
            isDarkMode: isDarkMode
        )
    }

    static func render(
        sourceData: Data,
        blocks: [ScreenshotTranslationBlock],
        isDarkMode: Bool = false
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

        guard !blocks.isEmpty else { return nil }

        let blurRects = blocks.map {
            pixelRect(
                forTopLeftNormalizedRect: $0.boundingBox,
                imageSize: CGSize(width: width, height: height)
            )
        }
        if let blurredImage = blurredImage(
            sourceImage,
            radius: 10,
            brightness: translationBlurBrightness(isDarkMode: isDarkMode)
        ), !blurRects.isEmpty {
            context.saveGState()
            blurRects.forEach { context.addRect($0) }
            context.clip()
            context.draw(blurredImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            context.restoreGState()
        }

        for block in blocks {
            let sourceRect = pixelRect(
                forTopLeftNormalizedRect: block.boundingBox,
                imageSize: CGSize(width: width, height: height)
            )
            let rect = sourceRect
                .insetBy(dx: -6, dy: -4)
            let style = sourceStyle(
                for: block.sourceText,
                in: sourceRect
            )
            drawReplacement(
                block.translatedText,
                in: rect,
                sourceFontSize: style.fontSize,
                isDarkMode: isDarkMode,
                context: context
            )
        }

        guard let outputImage = context.makeImage() else { return nil }
        return encodePNG(outputImage)
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
        return encodePNG(outputImage)
    }

    private static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return outputData as Data
    }

    static func pixelRect(
        forTopLeftNormalizedRect normalizedRect: CGRect,
        imageSize: CGSize
    ) -> CGRect {
        CGRect(
            x: normalizedRect.minX * imageSize.width,
            y: (1 - normalizedRect.maxY) * imageSize.height,
            width: normalizedRect.width * imageSize.width,
            height: normalizedRect.height * imageSize.height
        )
    }

    private static func drawReplacement(
        _ text: String,
        in rect: CGRect,
        sourceFontSize: CGFloat,
        isDarkMode: Bool,
        context: CGContext
    ) {
        let fillColor = (isDarkMode ? NSColor.white : NSColor.black)
            .withAlphaComponent(0.22)
        context.setFillColor(fillColor.cgColor)
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
            color: translationTextColor(isDarkMode: isDarkMode),
            fontSize: fontSize
        )
    }

    private static func sourceStyle(
        for text: String,
        in sourceRect: CGRect
    ) -> SourceTextStyle {
        SourceTextStyle(
            fontSize: estimatedSourceFontSize(for: text, in: sourceRect)
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
              let sampler = SourcePixelSampler(image: sourceImage)
        else {
            return .black
        }
        let sourceRect = pixelRect(
            forTopLeftNormalizedRect: boundingBox,
            imageSize: CGSize(width: sourceImage.width, height: sourceImage.height)
        )
        return sampler.foregroundColor(in: sourceRect)
    }

    static func translationTextColor(isDarkMode: Bool) -> NSColor {
        isDarkMode ? .black : .white
    }

    static func translationBlurBrightness(isDarkMode: Bool) -> CGFloat {
        isDarkMode ? 0.22 : -0.22
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
            if measured.width <= rect.width + 1, measured.height <= rect.height + 1 {
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

    private static func blurredImage(
        _ image: CGImage,
        radius: CGFloat,
        brightness: CGFloat
    ) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let blurredOutput = filter.outputImage?.cropped(to: input.extent),
              let colorFilter = CIFilter(name: "CIColorControls")
        else {
            return nil
        }
        colorFilter.setValue(blurredOutput, forKey: kCIInputImageKey)
        colorFilter.setValue(brightness, forKey: kCIInputBrightnessKey)
        colorFilter.setValue(1, forKey: kCIInputContrastKey)
        colorFilter.setValue(1, forKey: kCIInputSaturationKey)
        guard let output = colorFilter.outputImage?.cropped(to: input.extent) else { return nil }
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
