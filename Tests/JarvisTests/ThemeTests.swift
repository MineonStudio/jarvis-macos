@testable import Jarvis
import SwiftUI
import XCTest

final class JarvisOrbMoodTests: XCTestCase {
    func testMoodMapsConversationPhases() {
        XCTAssertEqual(
            JarvisOrbMood.from(
                isSending: false,
                progress: "",
                isListening: false,
                isSpeaking: false,
                lastAssistantText: ""
            ),
            .idle
        )
        XCTAssertEqual(
            JarvisOrbMood.from(
                isSending: false,
                progress: "",
                isListening: true,
                isSpeaking: false,
                lastAssistantText: "hello"
            ),
            .listening
        )
        XCTAssertEqual(
            JarvisOrbMood.from(
                isSending: true,
                progress: "正在用 DeepSeek（deepseek-v4-flash）思考",
                isListening: false,
                isSpeaking: false,
                lastAssistantText: ""
            ),
            .thinking
        )
        XCTAssertEqual(
            JarvisOrbMood.from(
                isSending: true,
                progress: "已完成：读取文件",
                isListening: false,
                isSpeaking: false,
                lastAssistantText: ""
            ),
            .working
        )
        XCTAssertEqual(
            JarvisOrbMood.from(
                isSending: true,
                progress: "免费额度已用完，正在重试…",
                isListening: false,
                isSpeaking: false,
                lastAssistantText: ""
            ),
            .trouble
        )
        XCTAssertEqual(
            JarvisOrbMood.from(
                isSending: false,
                progress: "",
                isListening: false,
                isSpeaking: true,
                lastAssistantText: "好的"
            ),
            .speaking
        )
        XCTAssertEqual(
            JarvisOrbMood.from(
                isSending: false,
                progress: "",
                isListening: false,
                isSpeaking: false,
                lastAssistantText: "Hermes 对话失败：免费模型额度已用完"
            ),
            .trouble
        )
    }

    func testCancelledToolLooksLikeWorking() {
        XCTAssertEqual(
            JarvisOrbMood.from(
                isSending: true,
                progress: "已取消：执行命令",
                isListening: false,
                isSpeaking: false,
                lastAssistantText: ""
            ),
            .working
        )
    }

    func testListeningWinsOverFailedReply() {
        XCTAssertEqual(
            JarvisOrbMood.from(
                isSending: false,
                progress: "",
                isListening: true,
                isSpeaking: false,
                lastAssistantText: "Hermes 对话失败：接口超时"
            ),
            .listening
        )
    }
}

final class ThemeTests: XCTestCase {
    func testThemePreferencesExposeAllDisplayModes() {
        XCTAssertEqual(
            JarvisTheme.allCases.map(\.rawValue),
            ["system", "light", "dark"]
        )
    }

    func testThemePreferencesMapToColorSchemes() {
        XCTAssertNil(JarvisTheme.system.preferredColorScheme)
        XCTAssertEqual(JarvisTheme.light.preferredColorScheme, .light)
        XCTAssertEqual(JarvisTheme.dark.preferredColorScheme, .dark)
    }

    func testSystemThemeResolvesToTheCurrentSystemScheme() {
        XCTAssertEqual(JarvisTheme.system.resolvedColorScheme(system: .dark), .dark)
        XCTAssertEqual(JarvisTheme.system.resolvedColorScheme(system: .light), .light)
        XCTAssertEqual(JarvisTheme.light.resolvedColorScheme(system: .dark), .light)
        XCTAssertEqual(JarvisTheme.dark.resolvedColorScheme(system: .light), .dark)
    }
}
