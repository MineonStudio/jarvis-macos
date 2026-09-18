import AppKit
@testable import Jarvis
import XCTest

/// Esc 的分级处理：正在输入文字 → 取消这次输入；选中了标注 → 取消选中；
/// 都没有才结束整场截图。
///
/// 原来所有 Esc 都直达「结束整场」：打字打到一半本能按 Esc，整张截图连同已经画好的
/// 标注一起丢掉，而且没有二次确认。
@MainActor
final class ScreenshotEditorEscapeTests: XCTestCase {
    private func makeEditor() throws -> ScreenshotEditorModel {
        let canvas = CGSize(width: 600, height: 400)
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

    func testEscapeCancelsTextEditingFirst() throws {
        let editor = try makeEditor()
        editor.beginTextEditing(at: CGPoint(x: 100, y: 100))
        editor.selectedAnnotationID = UUID()

        XCTAssertTrue(editor.handleEscape(), "应当由文字编辑这一步消化")
        XCTAssertFalse(editor.isEditingText)
        XCTAssertNotNil(
            editor.selectedAnnotationID,
            "取消输入时不该顺手把标注选中也清掉"
        )
    }

    func testEscapeClearsAnnotationSelectionNext() throws {
        let editor = try makeEditor()
        editor.selectedAnnotationID = UUID()

        XCTAssertTrue(editor.handleEscape(), "应当由「取消选中」这一步消化")
        XCTAssertNil(editor.selectedAnnotationID)
    }

    func testEscapeFallsThroughWhenThereIsNothingToDismiss() throws {
        let editor = try makeEditor()

        XCTAssertFalse(
            editor.handleEscape(),
            "没有可取消的东西时要交回调用方，否则 Esc 再也退不出截图"
        )
    }

    func testEndingTextEditingClearsBothAnchorAndTarget() throws {
        let editor = try makeEditor()
        let target = UUID()
        editor.textInputAnchor = CGPoint(x: 10, y: 20)
        editor.editingTextID = target

        editor.endTextEditing()

        XCTAssertNil(editor.textInputAnchor)
        XCTAssertNil(editor.editingTextID)
    }

    /// 换工具时也要收掉输入框，否则锚点会留在模型里、Esc 第一步永远被它吃掉。
    func testSelectingAToolEndsTextEditing() throws {
        let editor = try makeEditor()
        editor.beginTextEditing(at: CGPoint(x: 10, y: 10))

        editor.selectTool(.arrow)

        XCTAssertFalse(editor.isEditingText)
    }
}
