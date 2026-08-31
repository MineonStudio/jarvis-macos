import Foundation
import SwiftUI

enum ScreenshotTimeFilter: String, CaseIterable, Identifiable {
    case all
    case threeDays
    case sevenDays
    case oneMonth
    case halfYear

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all: "全部时间"
        case .threeDays: "3天"
        case .sevenDays: "7天"
        case .oneMonth: "1个月"
        case .halfYear: "近半年"
        }
    }

    static let displayCases: [Self] = [.threeDays, .sevenDays, .oneMonth, .all]

    func matches(
        _ item: ScreenshotHistoryItem,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let components else { return true }
        guard let startDate = calendar.date(byAdding: components, to: now) else { return false }
        // Use updatedAt because the screenshot list is ordered and displayed
        // by the last edit time, so filtering follows the visible timestamp.
        return item.updatedAt >= startDate
    }

    private var components: DateComponents? {
        switch self {
        case .all: nil
        case .threeDays: DateComponents(day: -3)
        case .sevenDays: DateComponents(day: -7)
        case .oneMonth: DateComponents(month: -1)
        case .halfYear: DateComponents(month: -6)
        }
    }
}

enum ScreenshotTimeFilterLogic {
    static func filteredItems(
        from items: [ScreenshotHistoryItem],
        filter: ScreenshotTimeFilter,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ScreenshotHistoryItem] {
        items.filter { filter.matches($0, now: now, calendar: calendar) }
    }

    static func count(
        for filter: ScreenshotTimeFilter,
        in items: [ScreenshotHistoryItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        filteredItems(from: items, filter: filter, now: now, calendar: calendar).count
    }
}

struct ScreenshotTimeFilterBar: ToolbarContent {
    @Binding var selectedFilter: ScreenshotTimeFilter

    var body: some ToolbarContent {
        ToolbarItem(id: "screenshot.time.three-days", placement: .navigation) {
            selectionButton(for: .threeDays)
        }
        ToolbarItem(id: "screenshot.time.seven-days", placement: .navigation) {
            selectionButton(for: .sevenDays)
        }
        ToolbarItem(id: "screenshot.time.one-month", placement: .navigation) {
            selectionButton(for: .oneMonth)
        }
        ToolbarItem(id: "screenshot.time.all", placement: .navigation) {
            selectionButton(for: .all)
        }
    }

    private func selectionButton(for filter: ScreenshotTimeFilter) -> some View {
        JarvisToolbarSelectionButton(
            title: filter.title,
            isSelected: selectedFilter == filter
        ) {
            selectedFilter = filter
        }
    }
}
