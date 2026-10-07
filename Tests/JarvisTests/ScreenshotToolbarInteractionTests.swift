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
    /// 不会出现。点图标只打开二级栏，翻译要等「开始翻译」。
    func testFirstTranslationTapOpensTheBarWithoutStarting() throws {
        let editor = try makeEditor()
        XCTAssertFalse(editor.secondaryBarVisible)

        editor.toggleTranslationMode()

        XCTAssertTrue(editor.translationMode)
        XCTAssertTrue(editor.secondaryBarVisible, "进入翻译模式后二级栏应当展开")
        XCTAssertEqual(editor.translationState, .idle)
        XCTAssertEqual(editor.translationActionTitle, "开始翻译")
    }

    func testSecondTranslationTapLeavesModeWithoutRestarting() throws {
        let editor = try makeEditor()
        editor.toggleTranslationMode()

        editor.toggleTranslationMode()

        XCTAssertFalse(editor.translationMode)
        XCTAssertFalse(editor.secondaryBarVisible, "再点一次翻译图标应当收起二级栏")
        XCTAssertEqual(editor.translationState, .idle)
    }

    func testTranslationButtonTitleSwitchesAfterARunStarts() throws {
        let editor = try makeEditor()
        XCTAssertEqual(editor.translationActionTitle, "开始翻译")

        editor.translationState = .recognizing
        XCTAssertEqual(editor.translationActionTitle, "重新翻译")

        editor.translationState = .completed(count: 1)
        XCTAssertEqual(editor.translationActionTitle, "重新翻译")

        editor.translationState = .failed("没有识别到可翻译的文字")
        XCTAssertEqual(editor.translationActionTitle, "重新翻译")

        editor.translationState = .idle
        XCTAssertEqual(editor.translationActionTitle, "开始翻译")
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

extension ScreenshotToolbarInteractionTests {
    /// 截图快捷键的迁移只做一次。
    ///
    /// 用户手动把快捷键录成 ⌘⇧J 或 F2（正是两个旧默认值）之后，重启不该被静默
    /// 改回 F1——迁移标记一旦置位，选什么就是什么。
    func testShortcutMigrationOnlyRunsOnce() {
        XCTAssertTrue(
            AppModel.shouldMigrateScreenshotShortcut(hasMigrated: false, stored: .previousDefault),
            "首次迁移时应当把旧默认值换掉"
        )
        XCTAssertFalse(
            AppModel.shouldMigrateScreenshotShortcut(hasMigrated: true, stored: .previousDefault),
            "已经迁移过就不该再覆盖用户的选择"
        )
        XCTAssertFalse(
            AppModel.shouldMigrateScreenshotShortcut(hasMigrated: true, stored: .legacyDefault),
            "F2 同理：用户选它就是选它"
        )
        XCTAssertFalse(
            AppModel.shouldMigrateScreenshotShortcut(hasMigrated: true, stored: .default)
        )
    }
}
