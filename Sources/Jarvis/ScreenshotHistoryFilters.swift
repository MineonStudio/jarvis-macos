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

    var icon: String {
        switch self {
        case .all: "square.grid.2x2"
        case .threeDays: "clock"
        case .sevenDays: "calendar"
        case .oneMonth: "calendar.badge.clock"
        case .halfYear: "calendar"
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
            HStack(spacing: 7) {
                ForEach(ScreenshotTimeFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: filter.icon)
                                .font(.system(size: 10, weight: .semibold))
                            Text("\(filter.title)（\(ScreenshotTimeFilterLogic.count(for: filter, in: items))）")
                        }
                        .font(JarvisTypography.control)
                        .foregroundStyle(
                            selectedFilter == filter
                                ? Color.accentColor
                                : Color.jarvisTextSecondary
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(minHeight: HistoryGridMetrics.screenshotFilterBarHeight)
                        .background(
                            selectedFilter == filter
                                ? Color.accentColor.opacity(0.16)
                                : Color.primary.opacity(0.045),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    Color.primary.opacity(selectedFilter == filter ? 0.16 : 0.08),
                                    lineWidth: 0.75
                                )
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.82))
                    .contentShape(Capsule())
                    .jarvisHoverFeedback(in: Capsule(), scale: 1.02)
                }
            }
        }
        .frame(height: HistoryGridMetrics.screenshotFilterBarHeight, alignment: .leading)
    }
}
