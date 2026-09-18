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

    private static func makeTrimmed(_ image: NSImage) -> NSImage? {
        var proposed = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return nil }

        var minX = rep.pixelsWide
        var maxX = -1
        var minY = rep.pixelsHigh
        var maxY = -1
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.06 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let isFullBleed = minX == 0 && minY == 0
            && maxX == rep.pixelsWide - 1 && maxY == rep.pixelsHigh - 1
        guard !isFullBleed else { return nil }

        let crop = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let cropped = cgImage.cropping(to: crop) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: crop.width, height: crop.height))
    }
}
