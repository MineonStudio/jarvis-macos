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

struct ScreenshotTimeFilterBar: View {
    @Binding var selectedFilter: ScreenshotTimeFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            JarvisSegmentedControl(
                items: ScreenshotTimeFilter.displayCases,
                selection: $selectedFilter
            ) { filter, isSelected in
                Text(filter.title)
                    .font(isSelected ? JarvisTypography.controlEmphasis : JarvisTypography.control)
                    .foregroundStyle(isSelected ? Color.white : Color.jarvisTextSecondary)
                    .frame(height: HistoryGridMetrics.filterChipHeight)
                    .padding(.horizontal, 14)
                    .contentShape(Capsule())
            }
        }
        // The glass projection extends beyond the scroll content bounds. Keep
        // that projection visible so the capsule's shadow is not cut into a
        // hard rectangular edge by ScrollView's default clipping.
        .scrollClipDisabled()
        .frame(height: HistoryGridMetrics.topControlHeight, alignment: .leading)
    }
}
