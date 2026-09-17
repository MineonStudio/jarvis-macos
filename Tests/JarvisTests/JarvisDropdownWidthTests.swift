import AppKit
@testable import Jarvis
import XCTest

final class JarvisDropdownWidthTests: XCTestCase {
    private let wallpaperSortingOptions = [
        JarvisDropdownOption(id: "toplist", title: "热门"),
        JarvisDropdownOption(id: "dateAdded", title: "最新"),
        JarvisDropdownOption(id: "views", title: "浏览量"),
        JarvisDropdownOption(id: "favorites", title: "收藏数")
    ]

    func testTriggerWidthFollowsTheCurrentTitleInsteadOfTheLongestOption() {
        let shortTitle = JarvisDropdownMetrics.triggerWidth(for: "最新")
        let longTitle = JarvisDropdownMetrics.triggerWidth(for: "浏览量")

        XCTAssertLessThan(shortTitle, longTitle)
        XCTAssertLessThan(shortTitle, JarvisDropdownMetrics.menuWidth(
            for: "最新",
            options: wallpaperSortingOptions
        ))
    }

    func testTriggerWidthKeepsASmallFloorForVeryShortTitles() {
        XCTAssertGreaterThanOrEqual(
            JarvisDropdownMetrics.triggerWidth(for: "热"),
            JarvisDropdownMetrics.minimumTriggerWidth
        )
    }

    func testMenuWidthStillReservesTheLongestOption() {
        let menuWidth = JarvisDropdownMetrics.menuWidth(
            for: "最新",
            options: wallpaperSortingOptions
        )
        let widestOptionWidth = JarvisDropdownMetrics.triggerWidth(for: "浏览量")

        XCTAssertGreaterThanOrEqual(menuWidth, widestOptionWidth)
        XCTAssertGreaterThanOrEqual(menuWidth, JarvisDropdownMetrics.minimumMenuWidth)
    }

    func testWidthsRespectTheMaximumCap() {
        let longTitle = "5120 × 1440 及以上，以及更长的分辨率描述文本"

        XCTAssertLessThanOrEqual(
            JarvisDropdownMetrics.triggerWidth(for: longTitle, maximumWidth: 480),
            480
        )
        XCTAssertLessThanOrEqual(
            JarvisDropdownMetrics.menuWidth(
                for: longTitle,
                options: [JarvisDropdownOption(id: "any", title: longTitle)],
                maximumWidth: 480
            ),
            480
        )
    }

    func testWidthsDropTheArrowWhenTheControlHidesIt() {
        let withArrow = JarvisDropdownMetrics.triggerWidth(for: "最新", includesArrow: true)
        let withoutArrow = JarvisDropdownMetrics.triggerWidth(for: "最新", includesArrow: false)

        XCTAssertGreaterThan(withArrow, withoutArrow)
    }
}
