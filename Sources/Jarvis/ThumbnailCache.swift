import AppKit
import Foundation
import ImageIO

enum JarvisThumbnailCache {
    private static let imageCache = JarvisThreadSafeImageCache(
        countLimit: 384,
        totalCostLimit: 96 * 1024 * 1024
    )
    private static let loadGate = JarvisThumbnailLoadGate(limit: 4)

    static func cached(fileURL: URL, maxPixelSize: Int, token: String = "") -> NSImage? {
        imageCache.object(forKey: cacheKey(for: fileURL, maxPixelSize: maxPixelSize, token: token))
    }

    static func loadAsync(
        fileURL: URL,
        maxPixelSize: Int,
        token: String = ""
    ) async -> NSImage? {
        if let cached = cached(fileURL: fileURL, maxPixelSize: maxPixelSize, token: token) {
            return cached
        }
        guard !Task.isCancelled else { return nil }
        return await loadGate.withPermit {
            if let cached = cached(fileURL: fileURL, maxPixelSize: maxPixelSize, token: token) {
                return cached
            }
            guard !Task.isCancelled else { return nil }
            return await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(
                        returning: load(
                            fileURL: fileURL,
                            maxPixelSize: maxPixelSize,
                            token: token
                        )
                    )
                }
            }
        }
    }

    static func purge() {
        imageCache.removeAllObjects()
    }

    private static func load(fileURL: URL, maxPixelSize: Int, token: String) -> NSImage? {
        let key = cacheKey(for: fileURL, maxPixelSize: maxPixelSize, token: token)
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
        imageCache.setObject(
            image,
            forKey: key,
            cost: max(1, cgImage.bytesPerRow * cgImage.height)
        )
        return image
    }

    private static func cacheKey(for fileURL: URL, maxPixelSize: Int, token: String) -> NSString {
        "\(fileURL.path)|\(token)|\(maxPixelSize)" as NSString
    }
}

/// Caps in-flight ImageIO work so scrolling a dense grid cannot start dozens
/// of thumbnail decodes at once.
actor JarvisThumbnailLoadGate {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func withPermit<T>(_ work: () async -> T) async -> T {
        await acquire()
        defer { release() }
        return await work()
    }

    private func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            running = max(0, running - 1)
            return
        }
        waiters.removeFirst().resume()
    }
}

final class JarvisThreadSafeImageCache: @unchecked Sendable {
    private let cache: NSCache<NSString, NSImage>
    private let lock = NSLock()

    init(countLimit: Int, totalCostLimit: Int) {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
        self.cache = cache
    }

    func object(forKey key: NSString) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache.object(forKey: key)
    }

    func setObject(_ object: NSImage, forKey key: NSString, cost: Int) {
        lock.lock()
        cache.setObject(object, forKey: key, cost: cost)
        lock.unlock()
    }

    func removeAllObjects() {
        lock.lock()
        cache.removeAllObjects()
        lock.unlock()
    }
}
