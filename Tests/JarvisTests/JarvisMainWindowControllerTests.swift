import AppKit
@testable import Jarvis
import XCTest

final class JarvisMainWindowControllerTests: XCTestCase {
    func testMinimumWindowSizeKeepsTheMainInterfaceUsable() {
        XCTAssertEqual(
            JarvisMainWindowController.minimumWindowSize.width,
            JarvisWindowLayoutMetrics.mainWindowMinimumWidth
        )
        XCTAssertEqual(
            JarvisMainWindowController.minimumWindowSize.height,
            JarvisWindowLayoutMetrics.mainWindowMinimumHeight
        )
        XCTAssertGreaterThanOrEqual(
            JarvisMainWindowController.minimumWindowSize.width,
            JarvisMetrics.sidebarMinimumWidth
                + JarvisMetrics.shellHorizontalPadding * 2
                + AIConversationLayoutMetrics.minimumTopBarWidth
        )
        XCTAssertLessThan(JarvisMainWindowController.minimumWindowSize.width, 1380)
        XCTAssertLessThan(JarvisMainWindowController.minimumWindowSize.height, 660)
        XCTAssertGreaterThanOrEqual(
            JarvisMainWindowController.defaultWindowSize.width,
            JarvisMainWindowController.minimumWindowSize.width
        )
        XCTAssertGreaterThanOrEqual(
            JarvisMainWindowController.defaultWindowSize.height,
            JarvisMainWindowController.minimumWindowSize.height
        )
    }

    func testLaunchWindowSizeUsesSavedFrameBeforeWindowCreation() {
        let savedFrame = NSRect(x: 120, y: 180, width: 1460, height: 820)

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

    func testClipboardPanelMinimumWidthUsesTheSameGridMetrics() {
        XCTAssertEqual(
            JarvisWindowLayoutMetrics.clipboardPanelMinimumWidth,
            ceil(
                max(
                    HistoryGridMetrics.clipboardCardWidth,
                    HistoryGridMetrics.clipboardSearchFieldWidth
                )
                    + JarvisWindowLayoutMetrics.clipboardPanelHorizontalPadding
                    + JarvisWindowLayoutMetrics.contentSafetyMargin
            )
        )
        XCTAssertGreaterThanOrEqual(
            JarvisWindowLayoutMetrics.clipboardPanelMinimumWidth,
            HistoryGridMetrics.clipboardSearchFieldWidth
        )
        XCTAssertEqual(
            JarvisWindowLayoutMetrics.clipboardPanelMinimumHeight,
            ceil(
                JarvisWindowLayoutMetrics.clipboardPanelTopPadding
                    + JarvisWindowLayoutMetrics.clipboardPanelCompactFilterBarHeight
                    + HistoryGridMetrics.imageSpacing
                    + JarvisWindowLayoutMetrics.clipboardPanelDividerHeight
                    + HistoryGridMetrics.imageSpacing
                    + max(
                        HistoryGridMetrics.clipboardCardHeight
                            + HistoryGridMetrics.clipboardContentSpacing
                            + HistoryGridMetrics.clipboardMetadataHeight,
                        JarvisWindowLayoutMetrics.emptyStateMinimumHeight
                    )
                    + HistoryGridMetrics.imageSpacing
                    + JarvisWindowLayoutMetrics.clipboardPanelFooterHeight
                    + JarvisWindowLayoutMetrics.clipboardPanelBottomPadding
                    + JarvisWindowLayoutMetrics.contentSafetyMargin
            )
        )
    }

    func testClipboardCompactHeightsMatchTheirResponsiveHeaderRows() {
        XCTAssertEqual(
            JarvisWindowLayoutMetrics.clipboardMainCompactFilterBarHeight,
            HistoryGridMetrics.topControlHeight * 3
                + HistoryGridMetrics.clipboardFilterToGridSpacing * 2
        )
        XCTAssertEqual(
            JarvisWindowLayoutMetrics.clipboardPanelCompactFilterBarHeight,
            HistoryGridMetrics.topControlHeight * 2
                + HistoryGridMetrics.clipboardFilterToGridSpacing
        )
        XCTAssertGreaterThan(
            JarvisWindowLayoutMetrics.clipboardMainCompactFilterBarHeight,
            JarvisWindowLayoutMetrics.clipboardPanelCompactFilterBarHeight
        )
    }
}
