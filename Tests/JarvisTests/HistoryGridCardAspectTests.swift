import AppKit
@testable import Jarvis
import SwiftUI
import XCTest

/// 宫格里的卡片比例必须恒为 16:9。
///
/// 踩过的坑：把 `.aspectRatio` 直接挂在**图片**上不管用——图片自带固有尺寸，
/// 一张竖图就能把卡片撑成 227×680（比例 0.33）。比例得锁在弹性的占位层
/// （`Color.clear`）上，内容盖上去、溢出裁掉。这里用一张竖图把这条钉住。
@MainActor
final class HistoryGridCardAspectTests: XCTestCase {
    private static let aspect = HistoryGridLayout.aspectRatio

    /// 一张 1:3 的竖图，专门用来把"比例被内容带跑"暴露出来。
    private func tallImage() throws -> NSImage {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 120,
            pixelsHigh: 360,
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
        NSColor.systemOrange.setFill()
        NSRect(x: 0, y: 0, width: 120, height: 360).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: 120, height: 360))
        image.addRepresentation(rep)
        return image
    }

    /// 量出预览区（橙色）的包围盒，换算成比例。
    private func previewAspect(view: some View) throws -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: 640).padding(8).background(Color.white))
        renderer.scale = 1
        let rep = try NSBitmapImageRep(cgImage: XCTUnwrap(renderer.cgImage))
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                guard color.redComponent > 0.85, color.greenComponent > 0.4, color.greenComponent < 0.75,
                      color.blueComponent < 0.3
                else {
                    continue
                }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX <= maxX else { throw XCTSkip("没画出来") }
        return CGFloat(maxX - minX + 1) / CGFloat(maxY - minY + 1)
    }

    /// 卡片预览用的写法：占位层带比例，内容当 overlay。
    private func preview(of image: NSImage) -> some View {
        Color.clear
            .aspectRatio(Self.aspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .clipped()
    }

    func testTallImageDoesNotStretchThePreview() throws {
        let image = try tallImage()

        let ratio = try previewAspect(view: preview(of: image))

        XCTAssertEqual(ratio, Self.aspect, accuracy: 0.05, "预览区被内容带成了 \(ratio)")
    }

    /// 反例：比例挂在图片自己身上（旧写法）会被竖图带跑——这条确认测试真的在测东西。
    func testAspectOnTheImageItselfIsNotEnough() throws {
        let image = try tallImage()

        let ratio = try previewAspect(view: Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .aspectRatio(Self.aspect, contentMode: .fit)
            .frame(maxWidth: .infinity))

        XCTAssertLessThan(ratio, 1, "旧写法居然锁住了比例？那这条测试就失去意义了（实测会得到 0.33）")
    }
}
