import AppKit
@testable import Jarvis
import SwiftUI
import XCTest

/// 编辑器里几处原本零覆盖的行为：撤销栈、零尺寸标注、以及工具栏视图本身能不能
/// 渲染出来（原来从未被实例化过——把保存和完成的 action 接反，三套测试也会全绿）。
@MainActor
final class ScreenshotEditorBehaviorTests: XCTestCase {
    private func makeEditor() throws -> ScreenshotEditorModel {
        let canvas = CGSize(width: 400, height: 300)
        let image = NSImage(size: canvas)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: canvas).fill()
        image.unlockFocus()
        let data = try XCTUnwrap(image.tiffRepresentation)
        return ScreenshotEditorModel(
            image: image,
            data: data,
            outputData: data,
            canvasSize: canvas
        )
    }

    func testUndoRedoWalksTheAnnotationStack() throws {
        let editor = try makeEditor()
        editor.addRectangle(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 60))
        editor.addArrow(from: CGPoint(x: 80, y: 80), to: CGPoint(x: 140, y: 120))
        XCTAssertEqual(editor.annotations.count, 2)
        XCTAssertTrue(editor.canUndo)

        editor.undo()
        XCTAssertEqual(editor.annotations.count, 1)
        XCTAssertTrue(editor.canRedo)

        editor.redo()
        XCTAssertEqual(editor.annotations.count, 2)
        XCTAssertFalse(editor.canRedo)
    }

    /// 撤销之后再画一笔，重做历史必须作废（否则会把被撤销的分支又接回来）。
    func testNewAnnotationClearsTheRedoStack() throws {
        let editor = try makeEditor()
        editor.addRectangle(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 60))
        editor.undo()
        XCTAssertTrue(editor.canRedo)

        editor.addArrow(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 260, y: 240))
        XCTAssertFalse(editor.canRedo)
    }

    /// 点一下就松手不该留下看不见、也删不掉的零尺寸马赛克。
    func testZeroSizeMosaicIsIgnored() throws {
        let editor = try makeEditor()
        editor.mosaicMode = .rectangle
        editor.addMosaic(points: [CGPoint(x: 50, y: 50), CGPoint(x: 50, y: 50)])
        XCTAssertTrue(editor.annotations.isEmpty, "零尺寸马赛克应当被丢弃")

        editor.addMosaic(points: [CGPoint(x: 50, y: 50), CGPoint(x: 80, y: 80)])
        XCTAssertEqual(editor.annotations.count, 1, "正常尺寸仍要能画上")
    }

    func testZeroLengthBrushStrokeIsIgnored() throws {
        let editor = try makeEditor()
        editor.mosaicMode = .brush
        editor.addMosaic(points: [CGPoint(x: 50, y: 50), CGPoint(x: 51, y: 50)])
        XCTAssertTrue(editor.annotations.isEmpty)

        editor.addMosaic(points: [CGPoint(x: 50, y: 50), CGPoint(x: 90, y: 50)])
        XCTAssertEqual(editor.annotations.count, 1)
    }

    /// 工具栏视图本身（不是单个图标）从未被实例化过：接错 action、行序写反、把胶囊
    /// 排在错误的顺序上，都不会有任何测试信号。这里让它真的渲染一次。
    func testToolbarRendersInBothRowOrders() throws {
        let editor = try makeEditor()
        let layout = ScreenshotToolbarLayoutModel(width: ScreenshotToolbarMetrics.baseWidth)

        for placesAbove in [false, true] {
            layout.placesSecondaryRowAboveMain = placesAbove
            for tool in [ScreenshotTool.arrow, .mosaic, .text] {
                editor.selectTool(tool)
                let size = NSHostingView(
                    rootView: ScreenshotToolbar(editor: editor, layout: layout, onAction: { _ in })
                ).fittingSize
                XCTAssertEqual(
                    size.height,
                    ScreenshotToolbarMetrics.expandedHeight,
                    accuracy: 1,
                    "展开态的高度应当与交给面板的口径一致（placesAbove=\(placesAbove)）"
                )
                XCTAssertGreaterThan(size.width, 0)
            }
            editor.selectTool(nil)
            let collapsed = NSHostingView(
                rootView: ScreenshotToolbar(editor: editor, layout: layout, onAction: { _ in })
            ).fittingSize
            XCTAssertEqual(
                collapsed.height,
                ScreenshotToolbarMetrics.compactHeight,
                accuracy: 1
            )
        }
    }
}
