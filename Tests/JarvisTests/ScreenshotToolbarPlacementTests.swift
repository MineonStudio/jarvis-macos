@testable import Jarvis
import XCTest

final class ScreenshotToolbarPlacementTests: XCTestCase {
    private let toolbarHeight = ScreenshotToolbarMetrics.compactHeight
    private let toolbarWidth = ScreenshotToolbarMetrics.baseWidth
    private let visibleFrame = CGRect(x: 0, y: 80, width: 1440, height: 820)

    func testSmallSelectionPlacesToolbarBelowTheImage() {
        let image = CGRect(x: 400, y: 300, width: 480, height: 280)
        let frame = ScreenshotToolbarPlacement.frame(
            for: image,
            in: visibleFrame,
            height: toolbarHeight,
            width: toolbarWidth
        )

        XCTAssertEqual(frame.height, toolbarHeight)
        XCTAssertEqual(frame.width, toolbarWidth)
        XCTAssertEqual(
            frame.minY,
            image.minY - toolbarHeight - ScreenshotToolbarMetrics.gap,
            accuracy: 0.001
        )
        XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY)
        XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY)
        XCTAssertEqual(frame.midX, image.midX, accuracy: 0.001)
    }

    func testSelectionAgainstTheBottomPlacesToolbarAbove() {
        let image = CGRect(x: 200, y: 80, width: 640, height: 240)
        let frame = ScreenshotToolbarPlacement.frame(
            for: image,
            in: visibleFrame,
            height: toolbarHeight,
            width: toolbarWidth
        )

        XCTAssertEqual(
            frame.minY,
            image.maxY + ScreenshotToolbarMetrics.gap,
            accuracy: 0.001
        )
        XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY)
        XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY)
    }

    func testFullscreenSelectionKeepsToolbarInsideTheVisibleFrame() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = ScreenshotToolbarPlacement.frame(
            for: screenFrame,
            in: visibleFrame,
            height: toolbarHeight,
            width: toolbarWidth
        )

        XCTAssertTrue(visibleFrame.contains(frame))
        XCTAssertEqual(
            frame.minY,
            visibleFrame.minY + ScreenshotToolbarMetrics.overlayInset,
            accuracy: 0.001
        )
    }

    func testLargeDesktopSelectionOverlaysInsteadOfGoingOffscreen() {
        let frame = ScreenshotToolbarPlacement.frame(
            for: visibleFrame,
            in: visibleFrame,
            height: toolbarHeight,
            width: toolbarWidth
        )

        XCTAssertTrue(visibleFrame.contains(frame))
        XCTAssertEqual(
            frame.minY,
            visibleFrame.minY + ScreenshotToolbarMetrics.overlayInset,
            accuracy: 0.001
        )
        XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX)
        XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX)
    }

    func testToolbarStaysHorizontallyInsideANarrowVisibleFrame() {
        let narrow = CGRect(x: 100, y: 80, width: 400, height: 820)
        let image = CGRect(x: 0, y: 200, width: 1440, height: 400)
        let frame = ScreenshotToolbarPlacement.frame(
            for: image,
            in: narrow,
            height: toolbarHeight,
            width: toolbarWidth
        )

        XCTAssertGreaterThanOrEqual(frame.minX, narrow.minX)
        XCTAssertLessThanOrEqual(frame.maxX, narrow.maxX)
        XCTAssertTrue(narrow.contains(frame))
    }
}
