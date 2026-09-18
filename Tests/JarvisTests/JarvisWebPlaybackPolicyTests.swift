@testable import Jarvis
import XCTest

final class JarvisWebPlaybackPolicyTests: XCTestCase {
    func testVisibleHostKeepsPlaying() {
        XCTAssertFalse(
            JarvisWebPlaybackPolicy.shouldSuspendMediaPlayback(
                isSuspendedByView: false,
                isHostVisible: true,
                isElementFullscreen: false
            )
        )
    }

    /// 窗口被遮挡/最小化/关闭后视图并不会消失，只靠 `onDisappear` 会让后台视频
    /// 一直解码——这是这次修复盯住的场景。
    func testHiddenHostSuspendsEvenWhenViewIsStillAlive() {
        XCTAssertTrue(
            JarvisWebPlaybackPolicy.shouldSuspendMediaPlayback(
                isSuspendedByView: false,
                isHostVisible: false,
                isElementFullscreen: false
            )
        )
    }

    func testViewLifecycleSuspendsRegardlessOfHostState() {
        XCTAssertTrue(
            JarvisWebPlaybackPolicy.shouldSuspendMediaPlayback(
                isSuspendedByView: true,
                isHostVisible: true,
                isElementFullscreen: false
            )
        )
        XCTAssertTrue(
            JarvisWebPlaybackPolicy.shouldSuspendMediaPlayback(
                isSuspendedByView: true,
                isHostVisible: false,
                isElementFullscreen: true
            )
        )
    }

    /// 元素全屏时网页被移进独立窗口，容器所在窗口多半已经不可见，但那是用户
    /// 正在看的画面，不能暂停。
    func testElementFullscreenKeepsPlayingWhenHostLooksHidden() {
        XCTAssertFalse(
            JarvisWebPlaybackPolicy.shouldSuspendMediaPlayback(
                isSuspendedByView: false,
                isHostVisible: false,
                isElementFullscreen: true
            )
        )
    }

    /// 退出全屏的那一帧遮挡状态还没补上，若按「不在全屏」处理，刚退出全屏的视频
    /// 会被立刻暂停。
    func testExitingFullscreenStillProtectsPlayback() {
        XCTAssertTrue(
            JarvisWebPlaybackPolicy.isElementFullscreenProtectingPlayback(.enteringFullscreen)
        )
        XCTAssertTrue(
            JarvisWebPlaybackPolicy.isElementFullscreenProtectingPlayback(.inFullscreen)
        )
        XCTAssertTrue(
            JarvisWebPlaybackPolicy.isElementFullscreenProtectingPlayback(.exitingFullscreen)
        )
        XCTAssertFalse(
            JarvisWebPlaybackPolicy.isElementFullscreenProtectingPlayback(.notInFullscreen)
        )
    }
}
