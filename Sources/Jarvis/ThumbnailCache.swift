import AppKit
import Foundation
import ImageIO

enum JarvisThumbnailCache {
    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static func loadAsync(fileURL: URL, maxPixelSize: Int) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = load(fileURL: fileURL, maxPixelSize: maxPixelSize)
                DispatchQueue.main.async {
                    continuation.resume(returning: image)
                }
            }
        }
    }

    private static func load(fileURL: URL, maxPixelSize: Int) -> NSImage? {
        let key = cacheKey(for: fileURL, maxPixelSize: maxPixelSize)
        if let cached = imageCache.object(forKey: key) {
            return cached
        }

        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }

        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        imageCache.setObject(image, forKey: key, cost: cgImage.width * cgImage.height)
        return image
    }

    private static func cacheKey(for fileURL: URL, maxPixelSize: Int) -> NSString {
        let values = try? fileURL.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        )
        let modificationDate = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = values?.fileSize ?? 0
        return "\(fileURL.path)|\(fileSize)|\(modificationDate)|\(maxPixelSize)" as NSString
    }
}
