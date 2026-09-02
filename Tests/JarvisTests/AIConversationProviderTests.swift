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

    func testEmbeddedStripeFramesStayInsideTheWebView() {
        let stripe = URL(string: "https://js.stripe.com/v3/m-outer-3437aaddcdf6922d623e172c2d6f9278.html")
        XCTAssertEqual(
            AIConversationNavigationPolicy.decision(
                url: stripe,
                isMainFrame: false,
                isPrimaryWebView: true,
                shouldDownload: false,
                provider: .grok
            ),
            .allow
        )
        XCTAssertEqual(
            AIConversationNavigationPolicy.decision(
                url: stripe,
                isMainFrame: true,
                isPrimaryWebView: false,
                shouldDownload: false,
                provider: .grok
            ),
            .allow
        )
        XCTAssertEqual(
            AIConversationNavigationPolicy.decision(
                url: URL(string: "https://grok.com/"),
                isMainFrame: true,
                isPrimaryWebView: true,
                shouldDownload: false,
                provider: .grok
            ),
            .allow
        )
        XCTAssertEqual(
            AIConversationNavigationPolicy.decision(
                url: URL(string: "https://evil.example/phish"),
                isMainFrame: true,
                isPrimaryWebView: true,
                shouldDownload: false,
                provider: .grok
            ),
            .openExternally
        )
    }
}
