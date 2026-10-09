import AppKit
@testable import Jarvis
import XCTest

@MainActor
final class JarvisMainWindowControllerTests: XCTestCase {
    func testSettingsModalUsesFixedCenteredLayoutSize() {
        XCTAssertEqual(
            SettingsLayout.modalSize,
            CGSize(width: 728, height: 680)
        )
        XCTAssertEqual(SettingsLayout.modalSize.width, 1040 * 0.7, accuracy: 0.001)
    }

    func testSettingsModalShrinksToStayInsideTheMainWindow() {
        XCTAssertEqual(
            SettingsLayout.fittedModalSize(in: CGSize(width: 1600, height: 1000)),
            SettingsLayout.modalSize
        )

        let tight = SettingsLayout.fittedModalSize(in: CGSize(width: 700, height: 600))
        let margin = SettingsLayout.modalEdgeMargin * 2
        XCTAssertEqual(tight.width, 700 - margin, accuracy: 0.001)
        XCTAssertEqual(tight.height, 600 - margin, accuracy: 0.001)
        XCTAssertLessThan(tight.width, SettingsLayout.modalSize.width)
        XCTAssertLessThan(tight.height, SettingsLayout.modalSize.height)
    }

    func testSettingsSidebarStaysInsideTheCard() {
        XCTAssertEqual(
            SettingsLayout.sidebarWidth(forModalWidth: SettingsLayout.modalSize.width),
            SettingsLayout.sidebarIdealWidth
        )
        let narrow = SettingsLayout.sidebarWidth(forModalWidth: 480)
        XCTAssertGreaterThan(narrow, 0)
        XCTAssertLessThan(narrow, 480)
        XCTAssertEqual(SettingsLayout.sidebarWidth(forModalWidth: 0), 0)
    }

    func testSettingsSectionsExposeStableSidebarOrder() {
        XCTAssertEqual(
            SettingsSection.allCases,
            [.general, .appearance, .wallpaperSources, .shortcuts, .model, .privacyCache, .diagnostics, .about]
        )
        XCTAssertEqual(
            SettingsSection.allCases.map(\.title),
            ["常规", "外观", "壁纸源", "快捷键", "模型", "隐私与缓存", "诊断", "关于"]
        )
        XCTAssertTrue(SettingsSection.allCases.allSatisfy { !$0.icon.isEmpty })
    }

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
                + JarvisWebPlatformLayoutMetrics.minimumTopBarWidth
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
