import CoreGraphics
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

enum ScreenshotTranslationImageDetail: String, Sendable {
    case low
    case high
}

struct ScreenshotTranslationImageSize: Equatable, Sendable {
    let width: Int
    let height: Int
}

struct ScreenshotTranslationInput: Sendable {
    static let maxModelDimension = 2048

    let data: Data
    let detail: ScreenshotTranslationImageDetail
    let sourcePixelSize: ScreenshotTranslationImageSize
    let modelPixelSize: ScreenshotTranslationImageSize
    let originalByteCount: Int
    let modelByteCount: Int
    let wasDownsampled: Bool

    static func prepare(from imageData: Data) -> ScreenshotTranslationInput? {
        guard !imageData.isEmpty,
              let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0,
              image.height > 0
        else {
            return nil
        }

        let maxDimension = max(image.width, image.height)
        let detail = imageDetail(for: imageData, maxDimension: maxDimension)
        guard maxDimension > maxModelDimension else {
            return ScreenshotTranslationInput(
                data: imageData,
                detail: detail,
                sourcePixelSize: ScreenshotTranslationImageSize(
                    width: image.width,
                    height: image.height
                ),
                modelPixelSize: ScreenshotTranslationImageSize(
                    width: image.width,
                    height: image.height
                ),
                originalByteCount: imageData.count,
                modelByteCount: imageData.count,
                wasDownsampled: false
            )
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Keep the model image in the same pixel orientation as the render source.
            kCGImageSourceCreateThumbnailWithTransform: false,
            kCGImageSourceThumbnailMaxPixelSize: maxModelDimension
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ), let modelData = encodePNG(thumbnail) else {
            return nil
        }

        return ScreenshotTranslationInput(
            data: modelData,
            detail: detail,
            sourcePixelSize: ScreenshotTranslationImageSize(
                width: image.width,
                height: image.height
            ),
            modelPixelSize: ScreenshotTranslationImageSize(
                width: thumbnail.width,
                height: thumbnail.height
            ),
            originalByteCount: imageData.count,
            modelByteCount: modelData.count,
            wasDownsampled: true
        )
    }

    static func imageDetail(for imageData: Data, maxDimension: Int) -> ScreenshotTranslationImageDetail {
        if maxDimension >= 2400 || imageData.count >= 2_000_000 {
            return .low
        }
        return .high
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return outputData as Data
    }
}

enum ScreenshotTranslationTiming {
    static func now() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    static func milliseconds(since start: UInt64) -> Double {
        Double(now() - start) / 1_000_000
    }
}

enum ScreenshotTranslationLog {
    static let logger = Logger(subsystem: "com.jarvis.mac", category: "screenshot-translation")
}
