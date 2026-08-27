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
        case .all: "全部"
        case .threeDays: "近3天"
        case .sevenDays: "近7天"
        case .oneMonth: "近1个月"
        case .halfYear: "近半年"
        }
    }

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

struct ScreenshotTimeFilterBar: View {
    @Binding var selectedFilter: ScreenshotTimeFilter
    let items: [ScreenshotHistoryItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HistoryGridMetrics.filterChipSpacing) {
                ForEach(ScreenshotTimeFilter.allCases) { filter in
                    HistoryFilterChip(
                        title: filter.title,
                        count: ScreenshotTimeFilterLogic.count(for: filter, in: items),
                        isSelected: selectedFilter == filter
                    ) {
                        selectedFilter = filter
                    }
                }
            }
        }
        .frame(height: HistoryGridMetrics.screenshotFilterBarHeight, alignment: .leading)
    }
}
