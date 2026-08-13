import XCTest
@testable import Jarvis

final class ScreenshotTranslationTests: XCTestCase {
    func testTranslationLanguagesExposeStablePersistedValues() {
        XCTAssertEqual(
            ScreenshotTranslationLanguage.allCases.map(\.rawValue),
            ["中文", "English", "日本語", "한국어", "Français", "Español"]
        )
        XCTAssertEqual(
            ScreenshotTranslationLanguage(rawValue: "日本語"),
            .japanese
        )
    }

    func testTranslationStatesRemainEquatable() {
        XCTAssertEqual(
            ScreenshotTranslationState.success("你好"),
            ScreenshotTranslationState.success("你好")
        )
        XCTAssertNotEqual(
            ScreenshotTranslationState.translating,
            ScreenshotTranslationState.failed("网络错误")
        )
    }

    func testTranslationPromptPreservesFormattingRequirements() {
        let prompt = ModelGateway.translationPrompt(sourceText: "Hello\nWorld", targetLanguage: "English")

        XCTAssertTrue(prompt.contains("English"))
        XCTAssertTrue(prompt.contains("段落、列表和换行"))
        XCTAssertTrue(prompt.contains("只返回完整译文"))
        XCTAssertTrue(prompt.contains("Hello\nWorld"))
        XCTAssertFalse(prompt.contains("image_url"))
    }
}
