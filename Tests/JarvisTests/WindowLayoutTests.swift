import AppKit
@testable import Jarvis
import XCTest

final class WindowLayoutTests: XCTestCase {
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
