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

    func testTranslationModeTogglesClosedOnSecondTap() throws {
        let editor = try makeEditor()
        XCTAssertFalse(editor.secondaryBarVisible)

        editor.enterTranslationMode()
        XCTAssertTrue(editor.translationMode)
        XCTAssertTrue(editor.secondaryBarVisible, "进入翻译模式后二级栏应当展开")

        editor.exitTranslationMode()
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
