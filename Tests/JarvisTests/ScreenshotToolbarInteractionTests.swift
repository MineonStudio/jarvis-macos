import AppKit
@testable import Jarvis
import XCTest

/// 一级编辑栏的按钮行为要一致：点一下开二级栏，再点一下关。
@MainActor
final class ScreenshotToolbarInteractionTests: XCTestCase {
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

    /// 走按钮真正调用的那个入口：进入时必须置上 translationMode，否则二级栏根本
    /// 不会出现（上一版就是漏了这一步，而且测试测的是模型方法、覆盖不到接线）。
    func testFirstTranslationTapEntersModeAndStartsTranslation() throws {
        let editor = try makeEditor()
        XCTAssertFalse(editor.secondaryBarVisible)

        let shouldStart = editor.toggleTranslationMode()

        XCTAssertTrue(shouldStart, "第一次点翻译图标应当发起翻译")
        XCTAssertTrue(editor.translationMode)
        XCTAssertTrue(editor.secondaryBarVisible, "进入翻译模式后二级栏应当展开")
    }

    func testSecondTranslationTapLeavesModeWithoutRestarting() throws {
        let editor = try makeEditor()
        XCTAssertTrue(editor.toggleTranslationMode())

        let shouldStartAgain = editor.toggleTranslationMode()

        XCTAssertFalse(shouldStartAgain, "再点一次只是退出，不该重跑一遍翻译")
        XCTAssertFalse(editor.translationMode)
        XCTAssertFalse(editor.secondaryBarVisible, "再点一次翻译图标应当收起二级栏")
    }

    func testSelectingAnotherToolLeavesTranslationMode() throws {
        let editor = try makeEditor()
        editor.enterTranslationMode()

        editor.selectTool(.arrow)
        XCTAssertFalse(editor.translationMode)
        XCTAssertEqual(editor.selectedTool, .arrow)
        XCTAssertTrue(editor.secondaryBarVisible)
    }

    /// 重复退出不应把状态搅乱（按钮回调可能被连续触发）。
    func testExitingTranslationModeTwiceIsHarmless() throws {
        let editor = try makeEditor()
        editor.enterTranslationMode()
        editor.exitTranslationMode()
        editor.exitTranslationMode()
        XCTAssertFalse(editor.translationMode)
        XCTAssertFalse(editor.secondaryBarVisible)
    }
}
