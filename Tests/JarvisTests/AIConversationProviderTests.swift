@testable import Jarvis
import XCTest

final class AIConversationProviderTests: XCTestCase {
    func testProvidersIncludeGrokWithOfficialWebAddress() {
        XCTAssertEqual(
            AIConversationProvider.allCases.map(\.title),
            ["DeepSeek", "ChatGPT", "豆包", "Grok"]
        )
        XCTAssertEqual(AIConversationProvider.grok.url.absoluteString, "https://grok.com/")
        XCTAssertEqual(
            AIConversationProvider.allCases.map(\.iconResourceName),
            ["deepseek", "gpt", "doubao", "grok"]
        )
        XCTAssertEqual(
            AIConversationProvider.allCases.map(\.iconResourceExtension),
            ["svg", "svg", "png", "svg"]
        )
        XCTAssertEqual(AIConversationProvider.deepSeek.selectedIconResourceName, "deepseek-selected")
        XCTAssertEqual(AIConversationProvider.doubao.selectedIconResourceName, nil)
        XCTAssertTrue(AIConversationProvider.gpt.allowsHost("chat.openai.com"))
        XCTAssertTrue(AIConversationProvider.doubao.allowsHost("doubao.com"))
        XCTAssertFalse(AIConversationProvider.grok.allowsHost("evil.example"))
    }
}
