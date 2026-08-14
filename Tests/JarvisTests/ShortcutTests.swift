import AppKit
@testable import Jarvis
import XCTest

final class ShortcutTests: XCTestCase {
    func testShortcutRecorderIgnoresKeyEventsUntilEditingStarts() throws {
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .shift],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "j",
                charactersIgnoringModifiers: "j",
                isARepeat: false,
                keyCode: 38
            )
        )

        XCTAssertNil(ShortcutRecorderEventHandling.shortcut(for: event, isRecording: false))
        XCTAssertEqual(
            ShortcutRecorderEventHandling.shortcut(for: event, isRecording: true),
            ScreenshotShortcut(keyCode: 38, modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue)
        )
    }

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
