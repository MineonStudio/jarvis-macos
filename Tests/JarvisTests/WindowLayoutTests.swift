import AppKit
@testable import Jarvis
import XCTest

final class WindowLayoutTests: XCTestCase {
    func testUserFacingTitlesAndMenuIconsUseSquareRegionDiagrams() {
        XCTAssertEqual(WindowLayout.halfLeft.title, "左半屏")
        XCTAssertEqual(WindowLayout.halfRight.title, "右半屏")
        XCTAssertEqual(WindowLayout.upperLeft.title, "左上角")
        XCTAssertEqual(WindowLayout.upperRight.title, "右上角")
        XCTAssertEqual(WindowLayout.lowerLeft.title, "左下角")
        XCTAssertEqual(WindowLayout.lowerRight.title, "右下角")

        for layout in WindowLayout.allCases {
            XCTAssertEqual(layout.menuIcon.size, NSSize(width: 18, height: 18))
        }
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

    func testShortcutsMatchTilesDefaults() {
        let modifiers = WindowLayout.shortcutModifierFlags

        XCTAssertEqual(WindowLayout.layout(for: 123, modifiers: modifiers), .halfLeft)
        XCTAssertEqual(WindowLayout.layout(for: 124, modifiers: modifiers), .halfRight)
        XCTAssertEqual(WindowLayout.layout(for: 32, modifiers: modifiers), .upperLeft)
        XCTAssertEqual(WindowLayout.layout(for: 34, modifiers: modifiers), .upperRight)
        XCTAssertEqual(WindowLayout.layout(for: 38, modifiers: modifiers), .lowerLeft)
        XCTAssertEqual(WindowLayout.layout(for: 40, modifiers: modifiers), .lowerRight)
        XCTAssertNil(WindowLayout.layout(for: 123, modifiers: .shift))
        XCTAssertNil(WindowLayout.layout(for: 126, modifiers: modifiers))
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
