@testable import Jarvis
import XCTest

final class EntertainmentPlatformTests: XCTestCase {
    func testPlatformsExposeOfficialWebAddresses() {
        XCTAssertEqual(
            EntertainmentPlatform.allCases.map(\.title),
            ["X", "YouTube", "TikTok"]
        )
        XCTAssertEqual(EntertainmentPlatform.x.url.absoluteString, "https://x.com/")
        XCTAssertEqual(EntertainmentPlatform.youtube.url.absoluteString, "https://www.youtube.com/")
        XCTAssertEqual(EntertainmentPlatform.tiktok.url.absoluteString, "https://www.tiktok.com/")
    }

    func testHostAllowlistsCoverLoginAndSubdomains() {
        XCTAssertTrue(EntertainmentPlatform.x.allowsHost("x.com"))
        XCTAssertTrue(EntertainmentPlatform.x.allowsHost("www.x.com"))
        XCTAssertTrue(EntertainmentPlatform.x.allowsHost("twitter.com"))
        XCTAssertFalse(EntertainmentPlatform.x.allowsHost("evil.example"))

        XCTAssertTrue(EntertainmentPlatform.youtube.allowsHost("www.youtube.com"))
        XCTAssertTrue(EntertainmentPlatform.youtube.allowsHost("accounts.google.com"))
        XCTAssertTrue(EntertainmentPlatform.youtube.allowsHost("youtu.be"))
        XCTAssertFalse(EntertainmentPlatform.youtube.allowsHost("evil.example"))

        XCTAssertTrue(EntertainmentPlatform.tiktok.allowsHost("www.tiktok.com"))
        XCTAssertTrue(EntertainmentPlatform.tiktok.allowsHost("m.tiktok.com"))
        XCTAssertFalse(EntertainmentPlatform.tiktok.allowsHost("evil.example"))
    }

    func testEmbeddedFramesStayInsideTheWebView() {
        let ads = URL(string: "https://www.google.com/recaptcha/api2/anchor")
        XCTAssertEqual(
            JarvisWebPlatformNavigationPolicy.decision(
                url: ads,
                isMainFrame: false,
                isPrimaryWebView: true,
                shouldDownload: false,
                allowsHost: EntertainmentPlatform.youtube.allowsHost
            ),
            .allow
        )
        XCTAssertEqual(
            JarvisWebPlatformNavigationPolicy.decision(
                url: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
                isMainFrame: true,
                isPrimaryWebView: true,
                shouldDownload: false,
                allowsHost: EntertainmentPlatform.youtube.allowsHost
            ),
            .allow
        )
        XCTAssertEqual(
            JarvisWebPlatformNavigationPolicy.decision(
                url: URL(string: "https://evil.example/phish"),
                isMainFrame: true,
                isPrimaryWebView: true,
                shouldDownload: false,
                allowsHost: EntertainmentPlatform.youtube.allowsHost
            ),
            .openExternally
        )
    }

    func testEmbeddedWebViewsAllowElementFullscreen() {
        XCTAssertTrue(
            JarvisWebPlatformConfiguration.make().preferences.isElementFullscreenEnabled
        )
    }

    func testWebModuleSectionsUseMatchingSymbols() {
        XCTAssertEqual(AppSection.aiConversation.icon, "sparkles")
        XCTAssertEqual(AppSection.aiConversation.navigationTitle, "AI聚合")
        XCTAssertEqual(AppSection.entertainment.icon, "play.rectangle")
        XCTAssertEqual(AppSection.entertainment.navigationTitle, "娱乐广场")
        XCTAssertEqual(
            EntertainmentPlatform.allCases.map(\.iconResourceName),
            ["x", "youtube", "tiktok"]
        )
    }
}
