import Foundation
@testable import Jarvis
import XCTest

final class ScreenshotHistoryFilterTests: XCTestCase {
    func testTimeFiltersUseUpdatedAtAndCalendarBoundaries() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let items = try [
            item(updatedAt: XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: now))),
            item(updatedAt: XCTUnwrap(calendar.date(byAdding: .day, value: -5, to: now))),
            item(updatedAt: XCTUnwrap(calendar.date(byAdding: .month, value: -2, to: now))),
            item(updatedAt: XCTUnwrap(calendar.date(byAdding: .month, value: -7, to: now)))
        ]

        XCTAssertEqual(
            ScreenshotTimeFilterLogic.filteredItems(
                from: items,
                filter: .all,
                now: now,
                calendar: calendar
            ).count,
            4
        )
        XCTAssertEqual(
            ScreenshotTimeFilterLogic.count(
                for: .threeDays,
                in: items,
                now: now,
                calendar: calendar
            ),
            1
        )
        XCTAssertEqual(
            ScreenshotTimeFilterLogic.count(
                for: .sevenDays,
                in: items,
                now: now,
                calendar: calendar
            ),
            2
        )
        XCTAssertEqual(
            ScreenshotTimeFilterLogic.count(
                for: .oneMonth,
                in: items,
                now: now,
                calendar: calendar
            ),
            2
        )
        XCTAssertEqual(
            ScreenshotTimeFilterLogic.count(
                for: .halfYear,
                in: items,
                now: now,
                calendar: calendar
            ),
            3
        )
    }

    private func item(updatedAt: Date) -> ScreenshotHistoryItem {
        ScreenshotHistoryItem(
            id: UUID(),
            createdAt: updatedAt.addingTimeInterval(-60),
            updatedAt: updatedAt,
            fileName: "screenshot-\(UUID().uuidString).png"
        )
    }
}
