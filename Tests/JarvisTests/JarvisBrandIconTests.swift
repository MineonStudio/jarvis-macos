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

    /// #42：以前用 10×10 对称墨块——垂直翻转下包围盒不变，翻转了也看不出来，
    /// 注释却承诺"裁反了上下能测出来"（过度承诺）。改用非对称的 L 形墨迹
    /// （横杠在底部），直接断言横杠在裁剪结果里的绝对 y 位置：翻转实现会把它搬到顶部。
    /// 注意 L 的竖条不能贯穿全高——否则包围盒上下对称，翻转后裁剪矩形不变，
    /// 照样测不出来。
    func testTrimmingDoesNotVerticallyMirrorInk() throws {
        let trimmed = try JarvisBrandIconMetrics.trimmed(makeLShapeImage())

        // 包围盒：x=2..<18，y=8..<28 → 16×20。
        XCTAssertEqual(trimmed.size.width, 16, accuracy: 1.5)
        XCTAssertEqual(trimmed.size.height, 20, accuracy: 1.5)
        var rect = NSRect(origin: .zero, size: trimmed.size)
        let cgImage = try XCTUnwrap(trimmed.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        let rep = try XCTUnwrap(NSBitmapImageRep(cgImage: cgImage))
        // colorAt 的 y=0 是顶部（AuditRegressionTests 的 mosaic 用例用的同一约定）。
        // 横杠在原图 y=24..<28，落在裁剪结果的底部（y≈16..<20）。
        let footPixel = try XCTUnwrap(rep.colorAt(x: 12, y: 18))
        XCTAssertGreaterThan(footPixel.alphaComponent, 0.9, "横杠应在底部")
        let mirroredPositionPixel = try XCTUnwrap(rep.colorAt(x: 12, y: 4))
        XCTAssertLessThan(
            mirroredPositionPixel.alphaComponent, 0.1,
            "顶部不该出现横杠：翻转实现会把它搬上来"
        )
        // 阳性对照：竖条中部不透明，排除"裁到透明区"时的空转通过。
        let barPixel = try XCTUnwrap(rep.colorAt(x: 2, y: 10))
        XCTAssertGreaterThan(barPixel.alphaComponent, 0.9)
    }

    /// L 形墨迹：竖条 x=2..<6、y=8..<28，横杠 y=24..<28、x=2..<18 落在底部。
    /// 包围盒上下不对称（顶部留 8，底部留 11），翻转后裁剪矩形必然变化。
    /// 直接写原始像素（第 0 行是顶部），不走 NSGraphicsContext，免得再猜一遍它的 y 方向。
    private func makeLShapeImage() throws -> NSImage {
        let canvas = 40
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
        let raw = try XCTUnwrap(rep.bitmapData)
        for row in 0 ..< canvas {
            for column in 0 ..< canvas {
                let inBar = (2 ..< 6).contains(column) && (8 ..< 28).contains(row)
                let inFoot = (24 ..< 28).contains(row) && (2 ..< 18).contains(column)
                let offset = row * rep.bytesPerRow + column * 4
                raw[offset] = 0
                raw[offset + 1] = 0
                raw[offset + 2] = 0
                raw[offset + 3] = (inBar || inFoot) ? 255 : 0
            }
        }
        let image = NSImage(size: NSSize(width: canvas, height: canvas))
        image.addRepresentation(rep)
        return image
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
