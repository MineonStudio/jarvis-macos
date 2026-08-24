import AppKit
@testable import Jarvis
import XCTest

final class JarvisMainWindowControllerTests: XCTestCase {
    func testLaunchWindowSizeUsesSavedFrameBeforeWindowCreation() {
        let savedFrame = NSRect(x: 120, y: 180, width: 1360, height: 820)

        XCTAssertEqual(
            JarvisMainWindowController.launchWindowSize(savedFrame: savedFrame),
            savedFrame.size
        )
    }

    func testLaunchWindowSizeFallsBackForTooSmallSavedFrame() {
        let savedFrame = NSRect(x: 120, y: 180, width: 420, height: 300)

        XCTAssertEqual(
            JarvisMainWindowController.launchWindowSize(savedFrame: savedFrame),
            JarvisMainWindowController.defaultWindowSize
        )
    }
}
