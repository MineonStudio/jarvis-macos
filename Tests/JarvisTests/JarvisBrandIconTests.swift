import AppKit
@testable import Jarvis
import XCTest

/// 品牌图标（AI 提供商 / 娱乐平台）的呈现规则。
///
/// 两套素材的「画布占用」不一样：AI 那几个是透明底的字形，娱乐那几个是铺满画布的
/// 圆角方块。统一到墨迹尺寸上，两排图标才会一样大。这里钉住裁剪那一步的规矩——
/// 真实素材要 `Bundle.main` 里的资源，测试进程里读不到，所以用合成图量。
final class JarvisBrandIconTests: XCTestCase {
    /// 造一张中间有不透明方块、四周透明的图。
    ///
    /// 走 `NSBitmapImageRep` 而不是 `NSImage.lockFocus()`：后者建出来的上下文可能
    /// 没有 alpha 通道，四周会被当成不透明，裁不裁都一样。
    private func makeImage(canvas: Int, ink: Int, offset: Int) throws -> NSImage {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: canvas,
            pixelsHigh: canvas,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()
        NSColor.black.setFill()
        NSRect(x: offset, y: offset, width: ink, height: ink).fill()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: canvas, height: canvas))
        image.addRepresentation(rep)
        return image
    }

    func testTrimmingRemovesTheTransparentMargin() throws {
        let canvas = 40, ink = 20, offset = 10

        let trimmed = try JarvisBrandIconMetrics.trimmed(makeImage(canvas: canvas, ink: ink, offset: offset))

        XCTAssertEqual(trimmed.size.width, CGFloat(ink), accuracy: 1.5, "透明边没裁干净")
        XCTAssertEqual(trimmed.size.height, CGFloat(ink), accuracy: 1.5, "透明边没裁干净")
    }

    /// 本来就铺满画布的图（娱乐那几个方块）没有可裁的，原样返回——不然会把图形切掉。
    func testTrimLeavesFullBleedImagesAlone() throws {
        let image = try makeImage(canvas: 32, ink: 32, offset: 0)

        let trimmed = JarvisBrandIconMetrics.trimmed(image)

        XCTAssertEqual(trimmed.size.width, 32, accuracy: 0.5)
        XCTAssertEqual(trimmed.size.height, 32, accuracy: 0.5)
    }

    /// 内缩 + 墨迹尺寸 = 图标框：这一圈余量就是两种素材看上去一样大的原因。
    func testInsetAndInkSizeFillTheBox() {
        XCTAssertEqual(
            JarvisBrandIconMetrics.inkSize + JarvisBrandIconMetrics.inset * 2,
            JarvisBrandIconMetrics.box,
            accuracy: 0.001
        )
        XCTAssertLessThan(
            JarvisBrandIconMetrics.inkSize,
            JarvisBrandIconMetrics.box,
            "墨迹等于整框时，方块状图标又会顶满，和字形状的差一圈"
        )
    }
}
