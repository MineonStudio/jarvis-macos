import AppKit
import SwiftUI

/// 品牌图标（AI 提供商、娱乐平台）的统一呈现。
///
/// 两套素材本身就不一样：AI 那几个是透明底的**字形**（DeepSeek 的鲸、OpenAI 的结），
/// 娱乐那几个是**铺满画布的圆角方块**（X、YouTube 的图标）。都按 `.scaledToFit()`
/// 塞进同一个方框里，方块顶满画布、字形只占中间一条——并排放就是两种大小。
///
/// 统一到「墨迹」上：先裁掉四周的透明边（方块本来就是满的，裁不动），再让墨迹的
/// 最大边等于 `inkSize`（靠外面留一圈等宽的内缩）。两套图标的墨迹尺寸从此一样，
/// 方块也会离开框边一线。
enum JarvisBrandIconMetrics {
    /// 分段控件里给图标留的方框。
    static let box: CGFloat = 16
    /// 墨迹（不透明部分）的最大边长。这一圈余量就是「方块 vs 字形」看上去一样大的关键。
    static let inkSize: CGFloat = 14
    /// 墨迹到方框的内缩。
    static var inset: CGFloat {
        (box - inkSize) / 2
    }

    /// 裁掉透明边之后的图。同一个资源只量一次。
    static func trimmed(_ image: NSImage, cacheKey: String) -> NSImage {
        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached
        }
        let result = makeTrimmed(image) ?? image
        cache.setObject(result, forKey: cacheKey as NSString)
        return result
    }

    static func trimmed(_ image: NSImage) -> NSImage {
        makeTrimmed(image) ?? image
    }

    /// `NSCache` 自己就是线程安全的（它不是 Sendable 只是没标），
    /// 语言模式下要显式说明这一点。
    private nonisolated(unsafe) static let cache = NSCache<NSString, NSImage>()

    /// 不透明边界只在缩小后的位图上扫。`colorAt` 走原图像素，OpenRouter 那张
    /// 会被栅成 2048×1460，第一次进模型设置要在主线程上卡一秒多。
    private static let sampleLimit = 128
    private static let alphaThreshold = UInt8(0.06 * 255)

    private static func makeTrimmed(_ image: NSImage) -> NSImage? {
        var proposed = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            return nil
        }
        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let sampleScale = min(1, CGFloat(sampleLimit) / CGFloat(max(pixelWidth, pixelHeight)))
        let sampleWidth = max(1, Int((CGFloat(pixelWidth) * sampleScale).rounded()))
        let sampleHeight = max(1, Int((CGFloat(pixelHeight) * sampleScale).rounded()))
        guard let bounds = opaqueBounds(
            of: cgImage,
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight
        ) else {
            return nil
        }
        if bounds.minX == 0, bounds.minY == 0,
           bounds.maxX == sampleWidth - 1, bounds.maxY == sampleHeight - 1
        {
            return nil
        }

        let scaleX = CGFloat(pixelWidth) / CGFloat(sampleWidth)
        let scaleY = CGFloat(pixelHeight) / CGFloat(sampleHeight)
        let crop = CGRect(
            x: floor(CGFloat(bounds.minX) * scaleX),
            y: floor(CGFloat(bounds.minY) * scaleY),
            width: ceil(CGFloat(bounds.maxX - bounds.minX + 1) * scaleX),
            height: ceil(CGFloat(bounds.maxY - bounds.minY + 1) * scaleY)
        ).intersection(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        guard crop.width >= 1, crop.height >= 1,
              let cropped = cgImage.cropping(to: crop)
        else {
            return nil
        }
        return NSImage(cgImage: cropped, size: NSSize(width: crop.width, height: crop.height))
    }

    private struct OpaqueBounds {
        var minX: Int
        var maxX: Int
        var minY: Int
        var maxY: Int
    }

    /// 缓冲的第 0 行是图像顶部，和 `CGImage.cropping` 的坐标一致。
    private static func opaqueBounds(
        of image: CGImage,
        sampleWidth: Int,
        sampleHeight: Int
    ) -> OpaqueBounds? {
        let bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)
        return pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: sampleWidth,
                      height: sampleHeight,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else {
                return nil
            }
            context.interpolationQuality = .none
            context.setShouldAntialias(false)
            context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

            let buffer = base.assumingMemoryBound(to: UInt8.self)
            var minX = sampleWidth
            var maxX = -1
            var minY = sampleHeight
            var maxY = -1
            for y in 0 ..< sampleHeight {
                let row = y * bytesPerRow
                for x in 0 ..< sampleWidth {
                    guard buffer[row + x * bytesPerPixel + 3] > alphaThreshold else { continue }
                    if x < minX {
                        minX = x
                    }
                    if x > maxX {
                        maxX = x
                    }
                    if y < minY {
                        minY = y
                    }
                    if y > maxY {
                        maxY = y
                    }
                }
            }
            guard maxX >= minX, maxY >= minY else { return nil }
            return OpaqueBounds(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
        }
    }
}
