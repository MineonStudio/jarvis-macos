import AppKit
import SwiftUI

typealias ClipboardViewFilter = ClipboardCacheCategory

enum ClipboardTimeFilter: String, CaseIterable, Identifiable {
    case threeDays
    case sevenDays
    case oneMonth
    case all

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all: "全部时间"
        case .threeDays: "3天"
        case .sevenDays: "7天"
        case .oneMonth: "1个月"
        }
    }

    func matches(
        _ item: ClipboardItem,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let components else { return true }
        guard let startDate = calendar.date(byAdding: components, to: now) else { return false }
        return item.createdAt >= startDate
    }

    private var components: DateComponents? {
        switch self {
        case .all: nil
        case .threeDays: DateComponents(day: -3)
        case .sevenDays: DateComponents(day: -7)
        case .oneMonth: DateComponents(month: -1)
        }
    }
}

enum ClipboardTimeFilterLogic {
    static func filteredItems(
        from items: [ClipboardItem],
        filter: ClipboardTimeFilter,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ClipboardItem] {
        items.filter { filter.matches($0, now: now, calendar: calendar) }
    }

    static func count(
        for filter: ClipboardTimeFilter,
        in items: [ClipboardItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        filteredItems(from: items, filter: filter, now: now, calendar: calendar).count
    }
}

struct ClipboardSearchField: View {
    @Binding var text: String
    let placeholder: String
    let focusesOnAppear: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.jarvisTextSecondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)

            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.75))
                .foregroundStyle(Color.jarvisTextSecondary)
            }
        }
        .padding(.horizontal, 15)
        .frame(
            minHeight: HistoryGridMetrics.topControlHeight,
            maxHeight: HistoryGridMetrics.topControlHeight
        )
        .jarvisGlass(in: Capsule(), interactive: false)
        .contentShape(Capsule())
        .onTapGesture {
            isFocused = true
        }
        .onAppear {
            if focusesOnAppear {
                isFocused = true
            }
        }
    }
}

enum ClipboardFilterLogic {
    static func filteredItems(
        from items: [ClipboardItem],
        searchText: String,
        timeFilter: ClipboardTimeFilter,
        category: ClipboardViewFilter,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ClipboardItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            timeFilter.matches(item, now: now, calendar: calendar)
                && category.matches(item)
                && (query.isEmpty || item.preview.localizedCaseInsensitiveContains(query))
        }
    }

    static func filteredItems(
        from items: [ClipboardItem],
        searchText: String,
        filter: ClipboardViewFilter
    ) -> [ClipboardItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            filter.matches(item)
                && (query.isEmpty || item.preview.localizedCaseInsensitiveContains(query))
        }
    }

    static func count(for filter: ClipboardViewFilter, in items: [ClipboardItem]) -> Int {
        items.filter { filter.matches($0) }.count
    }

    static func counts(in items: [ClipboardItem]) -> [ClipboardViewFilter: Int] {
        var counts = Dictionary(
            uniqueKeysWithValues: ClipboardViewFilter.allCases.map { ($0, 0) }
        )
        for item in items {
            for filter in ClipboardViewFilter.allCases where filter.matches(item) {
                counts[filter, default: 0] += 1
            }
        }
        return counts
    }
}

struct ClipboardFilterBar: View {
    @Binding var searchText: String
    @Binding var selectedTimeFilter: ClipboardTimeFilter
    @Binding var selectedCategory: ClipboardViewFilter
    let placeholder: String
    let focusesOnAppear: Bool
    let selectedItem: ClipboardItem?
    let onClearSelection: (() -> Void)?

    init(
        searchText: Binding<String>,
        selectedTimeFilter: Binding<ClipboardTimeFilter>,
        selectedCategory: Binding<ClipboardViewFilter>,
        placeholder: String,
        focusesOnAppear: Bool,
        selectedItem: ClipboardItem? = nil,
        onClearSelection: (() -> Void)? = nil
    ) {
        _searchText = searchText
        _selectedTimeFilter = selectedTimeFilter
        _selectedCategory = selectedCategory
        self.placeholder = placeholder
        self.focusesOnAppear = focusesOnAppear
        self.selectedItem = selectedItem
        self.onClearSelection = onClearSelection
    }

    @ViewBuilder
    private var actionToolbar: some View {
        if let onClearSelection {
            ClipboardHistoryActionToolbar(
                selectedItem: selectedItem,
                onClearSelection: onClearSelection
            )
        }
    }

    private var regularLayout: some View {
        HStack(alignment: .center, spacing: 14) {
            ClipboardTimeFilterSelector(selection: $selectedTimeFilter)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)

            Spacer(minLength: 0)

            ClipboardCategoryFilterSelector(selection: $selectedCategory)
            actionToolbar

            ClipboardSearchField(
                text: $searchText,
                placeholder: placeholder,
                focusesOnAppear: focusesOnAppear
            )
            .frame(width: HistoryGridMetrics.clipboardSearchFieldWidth)
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: HistoryGridMetrics.filterChipSpacing) {
                ClipboardTimeFilterSelector(selection: $selectedTimeFilter)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                ClipboardCategoryFilterSelector(selection: $selectedCategory)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if onClearSelection != nil {
                HStack(alignment: .center, spacing: HistoryGridMetrics.filterChipSpacing) {
                    actionToolbar
                    Spacer(minLength: 0)
                }
            }

            ClipboardSearchField(
                text: $searchText,
                placeholder: placeholder,
                focusesOnAppear: focusesOnAppear
            )
            .frame(maxWidth: .infinity)
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            regularLayout
            compactLayout
        }
    }
}

struct ClipboardTimeFilterSelector: View {
    @Binding var selection: ClipboardTimeFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            JarvisSegmentedControl(
                items: Array(ClipboardTimeFilter.allCases),
                selection: $selection
            ) { filter, isSelected in
                Text(filter.title)
                    // Keep every tab's metrics stable while the selection pill
                    // moves, avoiding a width re-layout during the animation.
                    .font(JarvisTypography.control)
                    .foregroundStyle(isSelected ? Color.white : Color.jarvisTextSecondary)
                    .frame(height: HistoryGridMetrics.filterChipHeight)
                    .padding(.horizontal, 14)
                    .contentShape(Capsule())
            }
        }
        .scrollClipDisabled()
        .frame(height: HistoryGridMetrics.topControlHeight, alignment: .leading)
    }
}

struct ClipboardCategoryFilterSelector: View {
    @Binding var selection: ClipboardViewFilter

    private func categoryTitle(_ filter: ClipboardViewFilter) -> String {
        filter == .all ? "全部类型" : filter.title
    }

    var body: some View {
        Picker(
            "内容类型",
            selection: $selection
        ) {
            ForEach(ClipboardViewFilter.allCases) { filter in
                Text(categoryTitle(filter)).tag(filter)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .buttonStyle(.plain)
        .font(JarvisTypography.control)
        .padding(.horizontal, 14)
        .frame(height: HistoryGridMetrics.filterChipHeight)
        .padding(JarvisMetrics.segmentedControlPadding)
        .frame(height: HistoryGridMetrics.topControlHeight)
        .jarvisGlass(in: Capsule(), interactive: true)
        .contentShape(Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct ClipboardView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var selectedTimeFilter: ClipboardTimeFilter = .threeDays
    @State private var selectedCategory: ClipboardViewFilter = .all
    @State private var selectedItemID: UUID?
    @State private var currentPage = 1
    @State private var availableGridWidth: CGFloat = 0
    @State private var availableGridHeight: CGFloat = 0

    private var filteredItems: [ClipboardItem] {
        ClipboardFilterLogic.filteredItems(
            from: app.clipboardItems,
            searchText: searchText,
            timeFilter: selectedTimeFilter,
            category: selectedCategory
        )
    }

    private var pageSize: Int {
        HistoryGridMetrics.pageSize(
            for: availableGridWidth,
            availableHeight: availableGridHeight,
            itemCount: filteredItems.count,
            verticalInset: HistoryGridMetrics.clipboardGridVerticalInset
        )
    }

    private var totalPages: Int {
        max(1, (filteredItems.count + pageSize - 1) / pageSize)
    }

    private var pageItems: [ClipboardItem] {
        let page = min(max(currentPage, 1), totalPages)
        let startIndex = (page - 1) * pageSize
        return Array(filteredItems.dropFirst(startIndex).prefix(pageSize))
    }

    private var selectedItem: ClipboardItem? {
        guard let selectedItemID else { return nil }
        return app.clipboardItems.first { $0.id == selectedItemID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HistoryGridMetrics.clipboardFilterToGridSpacing) {
            ClipboardFilterBar(
                searchText: $searchText,
                selectedTimeFilter: $selectedTimeFilter,
                selectedCategory: $selectedCategory,
                placeholder: "搜索文本、文件名…",
                focusesOnAppear: false,
                selectedItem: selectedItem,
                onClearSelection: { selectedItemID = nil }
            )

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if filteredItems.isEmpty {
                            ClipboardEmptyState(
                                hasQuery: !searchText.isEmpty
                                    || selectedTimeFilter != .all
                                    || selectedCategory != .all
                            )
                            .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
                        } else {
                            VStack(spacing: 0) {
                                ClipboardGrid(
                                    items: pageItems,
                                    selectedItemID: selectedItemID,
                                    onSelect: { selectedItemID = $0.id },
                                    onDoubleClick: { item in
                                        guard item.kind == .image || item.kind == .video else { return }
                                        app.showClipboardMediaPreview(item)
                                    }
                                )

                                if totalPages > 1 {
                                    PaginationControl(currentPage: min(currentPage, totalPages), totalPages: totalPages) {
                                        currentPage = max(1, currentPage - 1)
                                    } onNext: {
                                        currentPage = min(totalPages, currentPage + 1)
                                    }
                                }
                            }
                            .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HistoryGridMetrics.historyPanelInset)
                    .padding(.vertical, HistoryGridMetrics.historyPanelInset)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .jarvisFloatingPanel(cornerRadius: 16)
                .onAppear {
                    availableGridWidth = max(0, proxy.size.width - HistoryGridMetrics.historyPanelInset * 2)
                    availableGridHeight = max(0, proxy.size.height)
                }
                .onChange(of: proxy.size) { _, size in
                    availableGridWidth = max(0, size.width - HistoryGridMetrics.historyPanelInset * 2)
                    availableGridHeight = max(0, size.height)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: pageSize) { _, _ in
            currentPage = min(currentPage, totalPages)
        }
        .onChange(of: searchText) { _, _ in
            currentPage = 1
        }
        .onChange(of: selectedTimeFilter) { _, _ in
            currentPage = 1
        }
        .onChange(of: selectedCategory) { _, _ in
            currentPage = 1
        }
        .onChange(of: app.clipboardItems.count) { _, _ in
            currentPage = min(currentPage, totalPages)
            if let selectedItemID,
               !app.clipboardItems.contains(where: { $0.id == selectedItemID })
            {
                self.selectedItemID = nil
            }
        }
    }
}

struct ClipboardHistoryActionToolbar: View {
    @EnvironmentObject private var app: AppModel
    let selectedItem: ClipboardItem?
    let onClearSelection: () -> Void
    @State private var showingDeleteConfirmation = false

    private var canPreview: Bool {
        guard let selectedItem else { return false }
        return selectedItem.kind == .image || selectedItem.kind == .video
    }

    var body: some View {
        HStack(spacing: 2) {
            actionButton(
                systemName: "eye",
                help: "查看",
                isEnabled: canPreview
            ) {
                guard let selectedItem else { return }
                app.showClipboardMediaPreview(selectedItem)
            }
            actionButton(
                systemName: "doc.on.doc",
                help: "复制",
                isEnabled: selectedItem != nil
            ) {
                guard let selectedItem else { return }
                app.copyClipboard(selectedItem)
            }
            actionButton(
                systemName: selectedItem?.isPinned == true ? "star.slash" : "star",
                help: selectedItem?.isPinned == true ? "取消收藏" : "收藏",
                tint: selectedItem?.isPinned == true ? .yellow : .secondary,
                isEnabled: selectedItem != nil
            ) {
                guard let selectedItem else { return }
                app.toggleClipboardPin(selectedItem)
            }
            actionButton(
                systemName: "trash",
                help: "删除",
                tint: .red.opacity(0.82),
                isEnabled: selectedItem != nil
            ) {
                showingDeleteConfirmation = true
            }
        }
        .padding(4)
        .frame(height: HistoryGridMetrics.topControlHeight)
        .jarvisGlass(in: Capsule(), interactive: true)
        .confirmationDialog(
            "删除这条剪贴板记录？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let selectedItem else { return }
                app.deleteClipboardItem(selectedItem)
                onClearSelection()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复。")
        }
    }

    private func actionButton(
        systemName: String,
        help: String,
        tint: Color = .secondary,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(
                    isEnabled
                        ? tint
                        : Color.secondary.opacity(0.30)
                )
                .frame(
                    width: HistoryGridMetrics.clipboardActionButtonSize,
                    height: HistoryGridMetrics.clipboardActionButtonSize
                )
                .contentShape(Circle())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.76))
        .disabled(!isEnabled)
        .jarvisHoverHighlight(in: Circle(), scale: 1.06)
        .help(help)
    }
}

struct ClipboardEmptyState: View {
    let hasQuery: Bool

    var body: some View {
        JarvisEmptyState(
            icon: hasQuery ? "line.3.horizontal.decrease.circle" : "clipboard",
            title: hasQuery ? "没有找到匹配内容" : "还没有剪贴板记录",
            message: hasQuery ? "换个关键词或切换内容类型试试" : "复制一些内容，历史会自动出现在这里"
        )
    }
}

struct ClipboardCard: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingDeleteConfirmation = false
    @State private var isHovered = false
    let item: ClipboardItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void

    init(
        item: ClipboardItem,
        isSelected: Bool = false,
        onSelect: @escaping () -> Void = {},
        onDoubleClick: @escaping () -> Void = {}
    ) {
        self.item = item
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onDoubleClick = onDoubleClick
    }

    private var previewContent: some View {
        ZStack {
            if item.kind == .text {
                Text(item.preview)
                    .font(JarvisTypography.body)
                    .lineLimit(6)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(HistoryGridMetrics.clipboardCardPadding)
            } else if item.kind == .file {
                VStack(spacing: 10) {
                    Image(systemName: item.kind.icon)
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Text(item.preview)
                        .font(JarvisTypography.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, HistoryGridMetrics.clipboardCardPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ClipboardItemPreview(item: item)
            }
        }
        .frame(
            width: HistoryGridMetrics.clipboardCardWidth,
            height: HistoryGridMetrics.clipboardCardHeight,
            alignment: .center
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: HistoryGridMetrics.clipboardCornerRadius,
                style: .continuous
            )
        )
        .contentShape(Rectangle())
        .help("拖到 Finder 或其他应用导出内容")
    }

    @ViewBuilder
    private var previewArea: some View {
        if ClipboardSharing.itemProvider(for: item) != nil {
            previewContent
                .onDrag {
                    ClipboardSharing.itemProvider(for: item) ?? NSItemProvider()
                }
        } else {
            previewContent
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 6) {
            Text(item.shortTimestamp)
                .font(JarvisTypography.caption)
                .foregroundStyle(Color.jarvisTextSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let size = item.sizeDescription {
                Text(size)
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .lineLimit(1)
            }
        }
        .frame(
            width: HistoryGridMetrics.clipboardCardWidth,
            height: HistoryGridMetrics.clipboardMetadataHeight
        )
    }

    private var cardBody: some View {
        ZStack {
            previewArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .scaleEffect(
                    isHovered && !reduceMotion
                        ? HistoryGridMetrics.clipboardPreviewHoverScale
                        : 1
                )
                .animation(
                    JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion),
                    value: isHovered
                )
        }
        .frame(
            width: HistoryGridMetrics.clipboardCardWidth,
            height: HistoryGridMetrics.clipboardCardHeight,
            alignment: .topLeading
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: HistoryGridMetrics.clipboardCornerRadius,
                style: .continuous
            )
        )
        .jarvisGlass(
            cornerRadius: HistoryGridMetrics.clipboardCornerRadius,
            interactive: false
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: HistoryGridMetrics.clipboardCornerRadius,
                style: .continuous
            )
            .stroke(
                isSelected ? Color.accentColor : .clear,
                lineWidth: isSelected ? 2 : 0
            )
            .allowsHitTesting(false)
        }
        .onHover { isHovered = $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HistoryGridMetrics.clipboardContentSpacing) {
            cardBody
            metadataRow
        }
        .contentShape(
            RoundedRectangle(
                cornerRadius: HistoryGridMetrics.clipboardCornerRadius,
                style: .continuous
            )
        )
        .onTapGesture(count: 2, perform: onDoubleClick)
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button(item.isPinned ? "取消收藏" : "收藏") { app.toggleClipboardPin(item) }
            Button("一键复制") { app.copyClipboard(item) }
            if item.kind != .text {
                Button("在 Finder 中显示") { app.revealClipboardItem(item) }
            }
            Divider()
            Button("删除", role: .destructive) { showingDeleteConfirmation = true }
        }
        .confirmationDialog(
            "删除这条剪贴板记录？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                app.deleteClipboardItem(item)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复。")
        }
    }
}

struct ClipboardGrid: View {
    let items: [ClipboardItem]
    let selectedItemID: UUID?
    let onSelect: (ClipboardItem) -> Void
    let onDoubleClick: (ClipboardItem) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        items: [ClipboardItem],
        selectedItemID: UUID? = nil,
        onSelect: @escaping (ClipboardItem) -> Void = { _ in },
        onDoubleClick: @escaping (ClipboardItem) -> Void = { _ in }
    ) {
        self.items = items
        self.selectedItemID = selectedItemID
        self.onSelect = onSelect
        self.onDoubleClick = onDoubleClick
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(
                .adaptive(
                    minimum: HistoryGridMetrics.clipboardCardWidth,
                    maximum: HistoryGridMetrics.clipboardCardWidth
                ),
                spacing: HistoryGridMetrics.clipboardGridSpacing
            )],
            alignment: .leading,
            spacing: HistoryGridMetrics.clipboardGridSpacing
        ) {
            ForEach(items) { item in
                ClipboardCard(
                    item: item,
                    isSelected: selectedItemID == item.id,
                    onSelect: { onSelect(item) },
                    onDoubleClick: { onDoubleClick(item) }
                )
                .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: items.map(\.id)
        )
    }
}

struct ClipboardPanelView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ClipboardView()
            .padding(.horizontal, JarvisMetrics.shellHorizontalPadding)
            .padding(.vertical, JarvisMetrics.shellVerticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.jarvisBackground)
            .jarvisTheme(
                app.themePreference,
                systemColorScheme: app.systemColorScheme
            )
    }
}
