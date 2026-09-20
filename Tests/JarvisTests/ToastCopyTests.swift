@testable import Jarvis
import XCTest

@MainActor
final class ToastCopyTests: XCTestCase {
    func testCopySuccessIsAShortResultPhrase() {
        XCTAssertEqual(JarvisFeedbackCopy.copied, "复制成功")
        XCTAssertLessThanOrEqual(JarvisFeedbackCopy.copied.count, 6)
    }

    func testSharedSuccessPhrasesDoNotRepeatTheControlLabel() {
        XCTAssertEqual(JarvisFeedbackCopy.saved, "已保存")
        XCTAssertEqual(JarvisFeedbackCopy.deleted, "已删除")
        XCTAssertEqual(JarvisFeedbackCopy.favorited, "已收藏")
        XCTAssertEqual(JarvisFeedbackCopy.unfavorited, "已取消收藏")
        XCTAssertEqual(JarvisFeedbackCopy.applied, "已设置")
        XCTAssertFalse(JarvisFeedbackCopy.copied.contains("剪贴板"))
        XCTAssertFalse(JarvisFeedbackCopy.saved.contains("历史"))
        XCTAssertFalse(JarvisFeedbackCopy.deleted.contains("剪贴板"))
    }

    func testFailurePhrasesDoNotEmbedSystemErrors() {
        XCTAssertEqual(JarvisFeedbackCopy.saveFailed, "保存失败")
        XCTAssertEqual(JarvisFeedbackCopy.deleteFailed, "删除失败")
        XCTAssertEqual(JarvisFeedbackCopy.exportFailed, "导出失败")
        XCTAssertEqual(JarvisFeedbackCopy.connectionFailed, "连接失败")
        XCTAssertEqual(JarvisFeedbackCopy.applyFailed, "设置失败")
        XCTAssertFalse(JarvisFeedbackCopy.saveFailed.contains("%"))
        XCTAssertFalse(JarvisFeedbackCopy.connectionFailed.contains(":"))
    }

    func testWindowLayoutSuccessOmitsTheAppName() {
        let message = JarvisFeedbackCopy.windowAdjusted("左半屏")
        XCTAssertEqual(message, "已调整为左半屏")
        XCTAssertFalse(message.contains("Safari"))
        XCTAssertFalse(message.contains("当前窗口"))
    }

    func testANewActionReusesTheSameToastCapsule() {
        XCTAssertEqual(JarvisToastHost.capsuleIdentity, "jarvis.toast")
        XCTAssertTrue(JarvisToastHost.shouldAnimatePresence(from: nil, to: "复制成功"))
        XCTAssertFalse(JarvisToastHost.shouldAnimatePresence(from: "复制成功", to: "已删除"))
        XCTAssertTrue(JarvisToastHost.shouldAnimatePresence(from: "已删除", to: nil))
    }
}
