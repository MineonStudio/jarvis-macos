import AppKit
@testable import Jarvis
import XCTest

final class WindowLayoutTests: XCTestCase {
    func testUserFacingTitlesAndMenuIconsUseSixteenByNineRegionDiagrams() {
        XCTAssertEqual(WindowLayout.halfLeft.title, "左半屏")
        XCTAssertEqual(WindowLayout.halfRight.title, "右半屏")
        XCTAssertEqual(WindowLayout.upperLeft.title, "左上角")
        XCTAssertEqual(WindowLayout.upperRight.title, "右上角")
        XCTAssertEqual(WindowLayout.lowerLeft.title, "左下角")
        XCTAssertEqual(WindowLayout.lowerRight.title, "右下角")

        for layout in WindowLayout.allCases {
            XCTAssertEqual(layout.menuIcon.size, NSSize(width: 24, height: 16))
        }

        XCTAssertEqual(WindowLayout.halfLeft.shortcutDisplayParts, ["⇧", "⌘", "←"])
    }

    func testDirectionsMapToHalvesAndCornersRegardlessOfOrder() {
        XCTAssertEqual(WindowLayout.layout(for: [.left]), .halfLeft)
        XCTAssertEqual(WindowLayout.layout(for: [.right]), .halfRight)
        XCTAssertEqual(WindowLayout.layout(for: [.left, .up]), .upperLeft)
        XCTAssertEqual(WindowLayout.layout(for: [.up, .left]), .upperLeft)
        XCTAssertEqual(WindowLayout.layout(for: [.right, .up]), .upperRight)
        XCTAssertEqual(WindowLayout.layout(for: [.down, .left]), .lowerLeft)
        XCTAssertEqual(WindowLayout.layout(for: [.right, .down]), .lowerRight)
        XCTAssertNil(WindowLayout.layout(for: [.up]))
    }

    func testInAppShortcutLabelsUseTheExpectedPresentation() {
        XCTAssertEqual(WindowLayout.halfLeft.shortcutDisplay, "⇧⌘←")
        XCTAssertEqual(WindowLayout.upperRight.shortcutDisplay, "⇧⌘I")
    }

    func testLayoutShortcutBindingsMatchDisplayedShortcuts() {
        XCTAssertEqual(WindowLayout.halfLeft.shortcut.keyCode, 123)
        XCTAssertEqual(WindowLayout.halfRight.shortcut.keyCode, 124)
        XCTAssertEqual(WindowLayout.upperLeft.shortcut.keyCode, 32)
        XCTAssertEqual(WindowLayout.upperRight.shortcut.keyCode, 34)
        XCTAssertEqual(WindowLayout.lowerLeft.shortcut.keyCode, 38)
        XCTAssertEqual(WindowLayout.lowerRight.shortcut.keyCode, 40)

        for layout in WindowLayout.allCases {
            XCTAssertEqual(layout.shortcut.displayString, layout.shortcutDisplay)
            XCTAssertEqual(layout.shortcut.modifierFlags, WindowLayout.menuShortcutModifierFlags)
            XCTAssertEqual(layout.menuKeyEquivalent, layout.shortcut.menuKeyEquivalent)
        }
    }

    func testScreenshotGalleryUsesClipboardGridMetrics() {
        XCTAssertEqual(
            HistoryGridMetrics.clipboardCardHeight,
            HistoryGridMetrics.clipboardCardWidth * 9 / 16,
            accuracy: 0.001
        )
        XCTAssertEqual(HistoryGridMetrics.clipboardActionButtonSize, 32)
        XCTAssertEqual(HistoryGridMetrics.clipboardCornerRadius, 12)
        XCTAssertEqual(HistoryGridMetrics.clipboardGridSpacing, 10)
    }

    func testLowerLayoutsStayAboveBottomDock() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let safeFrame = WindowLayoutScreenArea.safeVisibleFrame(
            screenFrame: screenFrame,
            visibleFrame: screenFrame,
            dockFrame: NSRect(x: 0, y: 0, width: 1440, height: 96)
        )

        let lowerLeft = WindowLayout.frame(for: .lowerLeft, in: safeFrame)
        let lowerRight = WindowLayout.frame(for: .lowerRight, in: safeFrame)

        XCTAssertEqual(safeFrame.minY, 96)
        XCTAssertGreaterThanOrEqual(lowerLeft.minY, 96)
        XCTAssertGreaterThanOrEqual(lowerRight.minY, 96)
        XCTAssertLessThanOrEqual(lowerLeft.minY, lowerLeft.maxY)
        XCTAssertLessThanOrEqual(lowerRight.minY, lowerRight.maxY)
    }

    func testHalfFramesUseTheCompleteVisibleArea() {
        let visibleFrame = NSRect(x: 12, y: 24, width: 1001, height: 777)
        let left = WindowLayout.frame(for: .halfLeft, in: visibleFrame)
        let right = WindowLayout.frame(for: .halfRight, in: visibleFrame)

        XCTAssertEqual(left.minX, visibleFrame.minX)
        XCTAssertEqual(right.maxX, visibleFrame.maxX)
        XCTAssertEqual(left.minY, visibleFrame.minY)
        XCTAssertEqual(right.maxY, visibleFrame.maxY)
        XCTAssertEqual(left.maxX, right.minX)
        XCTAssertEqual(left.width + right.width, visibleFrame.width)
        XCTAssertEqual(left.width, visibleFrame.width / 2)
        XCTAssertEqual(right.width, visibleFrame.width / 2)
    }

    func testCornerFramesTileTheVisibleArea() {
        let visibleFrame = NSRect(x: 0, y: 23, width: 1280, height: 755)
        let upperLeft = WindowLayout.frame(for: .upperLeft, in: visibleFrame)
        let upperRight = WindowLayout.frame(for: .upperRight, in: visibleFrame)
        let lowerLeft = WindowLayout.frame(for: .lowerLeft, in: visibleFrame)
        let lowerRight = WindowLayout.frame(for: .lowerRight, in: visibleFrame)

        XCTAssertEqual(upperLeft.maxX, upperRight.minX)
        XCTAssertEqual(lowerLeft.maxX, lowerRight.minX)
        XCTAssertEqual(lowerLeft.maxY, upperLeft.minY)
        XCTAssertEqual(lowerRight.maxY, upperRight.minY)
        XCTAssertEqual(upperLeft.union(upperRight).union(lowerLeft).union(lowerRight), visibleFrame)
    }
}
