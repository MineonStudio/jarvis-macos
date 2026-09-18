import AppKit
@testable import Jarvis
import SwiftUI
import XCTest

/// 标注的图层收窄到自己的外接矩形之后，仍然必须画在画布上的正确位置。
///
/// 这条很重要：坐标从「画布绝对」改成「局部 + 平移回位」，画错位置在单元测试里
/// 完全静默，只有肉眼能看出来。所以这里把标注真实渲染出来，量它落在哪。
@MainActor
final class ScreenshotAnnotationPlacementTests: XCTestCase {
    private let canvas = CGSize(width: 400, height: 300)

    private func makeAnnotation(
        kind: ScreenshotAnnotation.Kind,
        points: [CGPoint]
    ) -> ScreenshotAnnotation {
        ScreenshotAnnotation(
            kind: kind,
            points: points,
            text: kind == .text ? "标题" : nil,
            brushSize: 20,
            color: .red,
            lineWidth: 6
        )
    }

    /// 渲染标注（铺在白色画布上），返回指定通道像素的包围盒。
    private func inkBounds(
        of annotation: ScreenshotAnnotation,
        isDraft: Bool = false,
        matches: (NSColor) -> Bool = { $0.redComponent > 0.5 && $0.greenComponent < 0.5 }
    ) throws -> CGRect {
        let content = ZStack(alignment: .topLeading) {
            Color.white
            ScreenshotAnnotationView(
                annotation: annotation,
                canvasSize: canvas,
                mosaicImage: nil,
                isDraft: isDraft
            )
        }
        .frame(width: canvas.width, height: canvas.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let cgImage = try XCTUnwrap(renderer.cgImage, "离屏渲染失败")
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let scale = CGFloat(cgImage.width) / canvas.width

        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                guard matches(color) else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX <= maxX else { return .zero }
        // 位图第 0 行是图像顶部，画布坐标也是左上原点，方向一致。
        return CGRect(
            x: CGFloat(minX) / scale,
            y: CGFloat(minY) / scale,
            width: CGFloat(maxX - minX + 1) / scale,
            height: CGFloat(maxY - minY + 1) / scale
        )
    }

    func testRectangleIsDrawnAtItsCanvasPosition() throws {
        let annotation = makeAnnotation(
            kind: .rectangle,
            points: [CGPoint(x: 100, y: 60), CGPoint(x: 200, y: 140)]
        )

        let ink = try inkBounds(of: annotation)

        XCTAssertEqual(ink.minX, 100, accuracy: 6, "矩形的左边缘画错位置")
        XCTAssertEqual(ink.minY, 60, accuracy: 6, "矩形的上边缘画错位置")
        XCTAssertEqual(ink.maxX, 200, accuracy: 6, "矩形的右边缘画错位置")
        XCTAssertEqual(ink.maxY, 140, accuracy: 6, "矩形的下边缘画错位置")
    }

    func testArrowIsDrawnAtItsCanvasPosition() throws {
        let annotation = makeAnnotation(
            kind: .arrow,
            points: [CGPoint(x: 60, y: 200), CGPoint(x: 160, y: 120)]
        )

        let ink = try inkBounds(of: annotation)

        // 箭头两端（含箭头头部）都要落在画布上对应的位置附近。
        XCTAssertEqual(ink.minX, 60, accuracy: 12)
        XCTAssertEqual(ink.minY, 120, accuracy: 12)
        XCTAssertEqual(ink.maxX, 160, accuracy: 12)
        XCTAssertEqual(ink.maxY, 200, accuracy: 12)
    }

    /// 图层只占标注那一块，不再铺满整个画布。
    func testLayerIsScopedToTheAnnotation() {
        let annotation = makeAnnotation(
            kind: .rectangle,
            points: [CGPoint(x: 100, y: 60), CGPoint(x: 200, y: 140)]
        )
        let view = ScreenshotAnnotationView(
            annotation: annotation,
            canvasSize: canvas,
            mosaicImage: nil
        )

        let bounds = view.scopedBounds
        XCTAssertLessThan(bounds.width, canvas.width, "图层不该铺满整个画布")
        XCTAssertLessThan(bounds.height, canvas.height)
        XCTAssertLessThanOrEqual(bounds.width, 100 + 2 * 14 + 1, "余量不该给得过大")
        XCTAssertTrue(bounds.contains(CGRect(x: 100, y: 60, width: 100, height: 80)))
    }
}

extension ScreenshotAnnotationPlacementTests {
    /// 马赛克用的是「整幅过滤图 + 遮罩」的路径（和矢量的 Canvas 不同），草稿态画出
    /// 的是青色边框，用它来验证这条路径的平移也对。
    func testDraftMosaicOutlineIsDrawnAtItsCanvasPosition() throws {
        let annotation = makeAnnotation(
            kind: .mosaic,
            points: [CGPoint(x: 120, y: 90), CGPoint(x: 260, y: 180)]
        )

        let ink = try inkBounds(of: annotation, isDraft: true) { color in
            // 青色：绿蓝高、红低
            color.redComponent < 0.5 && color.greenComponent > 0.5 && color.blueComponent > 0.5
        }

        XCTAssertEqual(ink.minX, 120, accuracy: 6, "马赛克框左边画错位置")
        XCTAssertEqual(ink.minY, 90, accuracy: 6, "马赛克框上边画错位置")
        XCTAssertEqual(ink.maxX, 260, accuracy: 6, "马赛克框右边画错位置")
        XCTAssertEqual(ink.maxY, 180, accuracy: 6, "马赛克框下边画错位置")
    }
}
