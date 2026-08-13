import XCTest
@testable import Jarvis

final class ShortcutTests: XCTestCase {
    func testMediaKeyEventsMapToPhysicalFunctionKeys() {
        XCTAssertEqual(
            ScreenshotShortcut.functionKeyCode(
                forSystemDefinedData: (2 << 16) | (0x0A << 8),
                subtype: 8
            ),
            122
        )
        XCTAssertEqual(
            ScreenshotShortcut.functionKeyCode(
                forSystemDefinedData: (3 << 16) | (0x0A << 8),
                subtype: 8
            ),
            120
        )
    }

    func testMediaKeyReleaseAndUnrelatedEventsAreIgnored() {
        XCTAssertNil(
            ScreenshotShortcut.functionKeyCode(
                forSystemDefinedData: (2 << 16) | (0x0B << 8),
                subtype: 8
            )
        )
        XCTAssertNil(
            ScreenshotShortcut.functionKeyCode(
                forSystemDefinedData: (2 << 16) | (0x0A << 8),
                subtype: 7
            )
        )
        XCTAssertNil(
            ScreenshotShortcut.functionKeyCode(
                forSystemDefinedData: (4 << 16) | (0x0A << 8),
                subtype: 8
            )
        )
    }
}
