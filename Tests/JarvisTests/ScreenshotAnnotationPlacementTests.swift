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

extension ScreenshotAnnotationPlacementTests {
    /// 提交后的马赛克走的是「整幅过滤图 + 遮罩」这条路径——草稿测试用的
    /// `mosaicImage: nil` 覆盖不到它。
    func testCommittedMosaicFillsExactlyItsRectangle() throws {
        let annotation = makeAnnotation(
            kind: .mosaic,
            points: [CGPoint(x: 120, y: 90), CGPoint(x: 260, y: 180)]
        )

        // 过滤图用纯红，背景纯白：能一眼看出马赛克块落在哪、有多大。
        let filtered = NSImage(size: canvas)
        filtered.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: canvas).fill()
        filtered.unlockFocus()

        let content = ZStack(alignment: .topLeading) {
            Color.white
            ScreenshotAnnotationView(
                annotation: annotation,
                canvasSize: canvas,
                mosaicImage: filtered
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
                guard color.redComponent > 0.5, color.greenComponent < 0.5 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        XCTAssertTrue(minX <= maxX, "马赛克完全没有画出来")

        let ink = CGRect(
            x: CGFloat(minX) / scale,
            y: CGFloat(minY) / scale,
            width: CGFloat(maxX - minX + 1) / scale,
            height: CGFloat(maxY - minY + 1) / scale
        )
        XCTAssertEqual(ink.minX, 120, accuracy: 6, "马赛克块的左边不对")
        XCTAssertEqual(ink.minY, 90, accuracy: 6, "马赛克块的上边不对")
        XCTAssertEqual(ink.maxX, 260, accuracy: 6, "马赛克块的右边不对")
        XCTAssertEqual(ink.maxY, 180, accuracy: 6, "马赛克块的下边不对")
    }
}

extension ScreenshotAnnotationPlacementTests {
    /// 多行文字：换行必须真的渲染成两行，而不是被压成一行或者跑到别处。
    func testMultiLineTextRendersEveryLineAtTheRightPlace() throws {
        let editor = ScreenshotEditorModel(
            image: NSImage(size: canvas),
            data: Data(),
            outputData: Data(),
            canvasSize: canvas
        )
        editor.textFontSize = 20
        editor.addText(alignedAtLeft: CGPoint(x: 60, y: 40), text: "第一行\n第二行")
        let annotation = try XCTUnwrap(editor.annotations.first)

        let ink = try inkBounds(of: annotation)

        // 渲染端把文字画在 start - size/2 + 9 处，行高由字号决定。
        let expected = annotation.textSize
        let left = annotation.start.x - expected.width / 2 + 9
        let top = annotation.start.y - expected.height / 2 + 9
        XCTAssertEqual(ink.minX, left, accuracy: 8, "文字左边不对")
        XCTAssertEqual(ink.minY, top, accuracy: 8, "文字上边不对")
        XCTAssertGreaterThan(
            ink.height,
            annotation.fontSize * 1.4,
            "两行文字的高度不该只有一行"
        )
    }

    /// 二次编辑：从既有标注反推出来的输入锚点，必须能原样还原它的位置。
    ///
    /// 这条同时是「光标位置 = 确认后文字位置」的保证：输入控件把内边距归零、放在
    /// 这个锚点上，而确认时文字的左上角也落在这个锚点上。
    func testReeditingAnchorRoundTrips() throws {
        let editor = ScreenshotEditorModel(
            image: NSImage(size: canvas),
            data: Data(),
            outputData: Data(),
            canvasSize: canvas
        )
        let anchor = CGPoint(x: 120, y: 80)
        editor.addText(alignedAtLeft: anchor, text: "原文")
        let annotation = try XCTUnwrap(editor.annotations.first)

        // 用的是画布视图里那个反推函数本身，不是另抄一遍公式。
        let reconstructed = ScreenshotCanvasView.textEditingAnchor(for: annotation)

        XCTAssertEqual(reconstructed.x, anchor.x, accuracy: 0.001, "二次编辑的锚点偏了")
        XCTAssertEqual(reconstructed.y, anchor.y, accuracy: 0.001)
    }
}

extension ScreenshotAnnotationPlacementTests {
    /// 光标所在的位置就是确认后文字落下的位置。
    ///
    /// 输入控件把内边距归零、整体放在锚点上，所以「光标位置 = 锚点」；这条断言渲染端
    /// 也把文字画在锚点上——两边一致，确认后文字才不会偏。用户反馈过的「确认后明显
    /// 偏左上」，差的就是原来 SwiftUI 控件那圈改不掉的内容内边距。
    func testCommittedTextTopLeftLandsOnTheEditingAnchor() throws {
        let editor = ScreenshotEditorModel(
            image: NSImage(size: canvas),
            data: Data(),
            outputData: Data(),
            canvasSize: canvas
        )
        let anchor = CGPoint(x: 140, y: 100)
        editor.addText(alignedAtLeft: anchor, text: "对齐检查")

        let annotation = try XCTUnwrap(editor.annotations.first)
        let ink = try inkBounds(of: annotation)

        XCTAssertEqual(ink.minX, anchor.x, accuracy: 8, "确认后的文字应当落在锚点上")
        XCTAssertEqual(ink.minY, anchor.y, accuracy: 10, "确认后的文字应当落在锚点上")
    }
}
