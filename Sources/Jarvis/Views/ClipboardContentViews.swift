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
    var placeholder: String
    var focusesOnAppear = false
    var onSubmit: (() -> Void)?
    var onClear: (() -> Void)?
    var help: String?
    var accessibilityTitle: String?

    var body: some View {
        JarvisToolbarSearchField(
            text: $text,
            placeholder: placeholder,
            help: help,
            accessibilityTitle: accessibilityTitle,
            focusesOnAppear: focusesOnAppear,
            onSubmit: onSubmit,
            onClear: onClear
        )
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

struct ClipboardTimeFilterSelector: ToolbarContent {
    @Binding var selection: ClipboardTimeFilter

    var body: some ToolbarContent {
        ToolbarItem(id: "clipboard.time.three-days", placement: .navigation) {
            selectionButton(for: .threeDays)
        }
        ToolbarItem(id: "clipboard.time.seven-days", placement: .navigation) {
            selectionButton(for: .sevenDays)
        }
        ToolbarItem(id: "clipboard.time.one-month", placement: .navigation) {
            selectionButton(for: .oneMonth)
        }
        ToolbarItem(id: "clipboard.time.all", placement: .navigation) {
            selectionButton(for: .all)
        }
    }

    private func selectionButton(for filter: ClipboardTimeFilter) -> some View {
        JarvisToolbarSelectionButton(
            title: filter.title,
            isSelected: selection == filter
        ) {
            selection = filter
        }
    }
}

struct ClipboardCategoryFilterSelector: View {
    @Binding var selection: ClipboardViewFilter

    private func categoryTitle(_ filter: ClipboardViewFilter) -> String {
        filter == .all ? "全部类型" : filter.title
    }

    var body: some View {
        JarvisDropdownMenu(
            title: categoryTitle(selection),
            options: ClipboardViewFilter.allCases.map {
                JarvisDropdownOption(id: $0.id, title: categoryTitle($0))
            },
            selectionID: selection.id,
            accessibilityLabel: "内容类型筛选",
            help: "按内容类型筛选",
            controlWidth: 96,
            onSelect: { rawValue in
                guard let category = ClipboardViewFilter(rawValue: rawValue) else { return }
                selection = category
            }
        )
    }
}

struct ClipboardView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var selectedTimeFilter: ClipboardTimeFilter = .threeDays
    @State private var selectedCategory: ClipboardViewFilter = .all
    @State private var selectedItemID: UUID?
    @State private var gridZoom: HistoryGridZoomLevel = .regular

    private var filteredItems: [ClipboardItem] {
        ClipboardFilterLogic.filteredItems(
            from: app.clipboardItems,
            searchText: searchText,
            timeFilter: selectedTimeFilter,
            category: selectedCategory
        )
    }

    private var selectedItem: ClipboardItem? {
        guard let selectedItemID else { return nil }
        return app.clipboardItems.first { $0.id == selectedItemID }
    }

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                ClipboardTimeFilterSelector(selection: $selectedTimeFilter)
            },
            trailingToolbar: {
                ToolbarItem(id: "clipboard.category", placement: .automatic) {
                    ClipboardCategoryFilterSelector(selection: $selectedCategory)
                }
                ToolbarSpacer(.fixed, placement: .automatic)
                ToolbarItem(id: "clipboard.grid-zoom", placement: .automatic) {
                    HistoryGridZoomControl(selection: $gridZoom)
                }
                ToolbarSpacer(.fixed, placement: .automatic)
                ToolbarItem(id: "clipboard.actions", placement: .automatic) {
                    ClipboardHistoryActionToolbar(
                        selectedItem: selectedItem,
                        onClearSelection: { selectedItemID = nil }
                    )
                }
                ToolbarSpacer(.fixed, placement: .automatic)
                ToolbarItem(id: "clipboard.search", placement: .automatic) {
                    ClipboardSearchField(
                        text: $searchText,
                        placeholder: "搜索文本、文件名…",
                        focusesOnAppear: false
                    )
                }
            },
            content: {
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
                            ClipboardGrid(
                                items: filteredItems,
                                gridZoom: gridZoom,
                                selectedItemID: selectedItemID,
                                onSelect: { selectedItemID = $0.id },
                                onDoubleClick: { item in
                                    guard item.canFullscreenPreview else { return }
                                    app.showClipboardMediaPreview(item)
                                }
                            )
                            .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HistoryGridMetrics.historyPanelInset)
                    .padding(.vertical, HistoryGridMetrics.historyPanelInset)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .jarvisFloatingPanel(cornerRadius: 16)
            }
        )
        .onChange(of: app.clipboardItems.count) { _, _ in
            if let selectedItemID,
               !app.clipboardItems.contains(where: { $0.id == selectedItemID })
            {
                self.selectedItemID = nil
            }
        }
    }
}

struct ClipboardHistoryActionToolbar: View {
    @Environment(AppModel.self) private var app
    let selectedItem: ClipboardItem?
    let onClearSelection: () -> Void
    @State private var showingDeleteConfirmation = false
    @State private var showingSensitiveCopyConfirmation = false
    @State private var showingSensitivePreviewConfirmation = false

    private var canPreview: Bool {
        selectedItem?.canFullscreenPreview == true
    }

    var body: some View {
        HStack(spacing: 2) {
            actionButton(
                systemName: "eye",
                help: "查看",
                isEnabled: canPreview
            ) {
                guard let selectedItem else { return }
                if selectedItem.isSensitive {
                    showingSensitivePreviewConfirmation = true
                } else {
                    app.showClipboardMediaPreview(selectedItem)
                }
            }
            actionButton(
                systemName: "doc.on.doc",
                help: "复制",
                isEnabled: selectedItem != nil
            ) {
                guard let selectedItem else { return }
                if selectedItem.isSensitive {
                    showingSensitiveCopyConfirmation = true
                } else {
                    app.copyClipboard(selectedItem)
                }
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
        // The enclosing ToolbarItem supplies the native toolbar group surface.
        // Do not add a second custom glass capsule inside it.
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
        .confirmationDialog(
            "这段内容疑似包含敏感信息",
            isPresented: $showingSensitiveCopyConfirmation,
            titleVisibility: .visible
        ) {
            Button("显示并复制") {
                guard let selectedItem else { return }
                app.copyClipboard(selectedItem)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只有在你主动确认后，才会显示并复制原始内容。")
        }
        .confirmationDialog(
            "这段内容疑似包含敏感信息",
            isPresented: $showingSensitivePreviewConfirmation,
            titleVisibility: .visible
        ) {
            Button("显示并查看") {
                guard let selectedItem else { return }
                app.showClipboardMediaPreview(selectedItem)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只有在你主动确认后，才会打开原始内容预览。")
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
                .font(.system(size: JarvisToolbarMetrics.iconSize, weight: .medium))
                .foregroundStyle(tint)
        }
        .buttonStyle(JarvisToolbarIconButtonStyle())
        .opacity(isEnabled ? 1 : 0.38)
        .disabled(!isEnabled)
        .jarvisHoverFeedback(in: Circle(), scale: 1.06)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var isSensitiveRevealed = false
    @State private var isTextExpanded = false
    let item: ClipboardItem
    let gridZoom: HistoryGridZoomLevel
    let isSelected: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void

    init(
        item: ClipboardItem,
        gridZoom: HistoryGridZoomLevel = .regular,
        isSelected: Bool = false,
        onSelect: @escaping () -> Void = {},
        onDoubleClick: @escaping () -> Void = {}
    ) {
        self.item = item
        self.gridZoom = gridZoom
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onDoubleClick = onDoubleClick
    }

    private var previewContent: some View {
        ZStack {
            if item.kind == .text {
                VStack(spacing: 8) {
                    if let presentation = item.sensitivePresentation(revealed: isSensitiveRevealed) {
                        Text(presentation.displayText)
                            .font(
                                presentation.requiresReveal
                                    ? JarvisTypography.secondary
                                    : JarvisTypography.body
                            )
                            .foregroundStyle(
                                presentation.requiresReveal
                                    ? Color.jarvisTextSecondary
                                    : Color.primary
                            )
                            .lineLimit(
                                presentation.requiresReveal
                                    ? 2
                                    : (isTextExpanded ? nil : 6)
                            )
                            .multilineTextAlignment(.center)
                            .accessibilityLabel(presentation.accessibilityText)

                        if presentation.requiresReveal {
                            Button("显示一次") {
                                withAnimation(
                                    JarvisMotion.animation(
                                        JarvisMotion.feedback,
                                        reduceMotion: reduceMotion
                                    )
                                ) {
                                    isSensitiveRevealed = true
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityHint("仅临时显示，离开卡片后会重新隐藏")
                        } else if presentation.sensitivity != nil {
                            Label("已临时显示", systemImage: "eye")
                                .font(JarvisTypography.caption)
                                .foregroundStyle(Color.jarvisTextSecondary)
                        }

                        if shouldOfferTextExpansion {
                            textExpansionButton
                        }
                    } else {
                        Text(item.preview)
                            .font(JarvisTypography.body)
                            .lineLimit(isTextExpanded ? nil : 6)
                            .multilineTextAlignment(.center)

                        if shouldOfferTextExpansion {
                            textExpansionButton
                        }
                    }
                }
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
            width: gridZoom.cardWidth,
            height: gridZoom.cardHeight,
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

    private var shouldOfferTextExpansion: Bool {
        guard item.kind == .text, let text = item.resolvedText else { return false }
        return text.count > 240 || text.split(separator: "\n").count > 6
    }

    private var textExpansionButton: some View {
        Button(isTextExpanded ? "收起" : "展开") {
            withAnimation(
                JarvisMotion.animation(
                    JarvisMotion.feedback,
                    reduceMotion: reduceMotion
                )
            ) {
                isTextExpanded.toggle()
            }
        }
        .buttonStyle(.borderless)
        .font(JarvisTypography.captionEmphasis)
        .foregroundStyle(Color.accentColor)
        .accessibilityLabel(isTextExpanded ? "收起长文本" : "展开长文本")
    }

    @ViewBuilder
    private var previewArea: some View {
        if ClipboardSharing.itemProvider(for: item) != nil,
           !item.isSensitive || isSensitiveRevealed
        {
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
            Label(item.kind.title, systemImage: item.kind.icon)
                .font(JarvisTypography.captionEmphasis)
                .foregroundStyle(Color.jarvisTextSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if item.isPinned {
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("已收藏")
            }
            Text(item.shortTimestamp)
                .font(JarvisTypography.caption)
                .foregroundStyle(Color.jarvisTextSecondary)
                .lineLimit(1)
        }
        .frame(
            width: gridZoom.cardWidth,
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
            width: gridZoom.cardWidth,
            height: gridZoom.cardHeight,
            alignment: .topLeading
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: HistoryGridMetrics.clipboardCornerRadius,
                style: .continuous
            )
        )
        .jarvisContentSurface(cornerRadius: HistoryGridMetrics.clipboardCornerRadius)
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
        .overlay(alignment: .topLeading) {
            if isSelected {
                Label("已选中", systemImage: "checkmark.circle.fill")
                    .font(JarvisTypography.captionEmphasis)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.92), in: Capsule())
                    .padding(8)
                    .accessibilityHidden(true)
            }
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
        .onTapGesture(count: 2) {
            if item.isSensitive, !isSensitiveRevealed {
                isSensitiveRevealed = true
            } else {
                onDoubleClick()
            }
        }
        .onTapGesture(perform: onSelect)
        .onChange(of: item.id) { _, _ in
            isSensitiveRevealed = false
            isTextExpanded = false
        }
        .onChange(of: item) { _, _ in
            isSensitiveRevealed = false
            isTextExpanded = false
        }
        .onAppear {
            isSensitiveRevealed = false
            isTextExpanded = false
        }
        .onDisappear {
            isSensitiveRevealed = false
            isTextExpanded = false
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            item.isSensitive
                ? "\(item.kind.title)，敏感内容"
                : "\(item.kind.title)，剪贴板内容"
        )
        .accessibilityValue("\(item.shortTimestamp)，\(isSelected ? "已选中" : "未选中")")
        .accessibilityHint("点击选择，双击打开预览")
        .accessibilityAddTraits(.isButton)
    }
}

struct ClipboardGrid: View {
    let items: [ClipboardItem]
    let gridZoom: HistoryGridZoomLevel
    let selectedItemID: UUID?
    let onSelect: (ClipboardItem) -> Void
    let onDoubleClick: (ClipboardItem) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        items: [ClipboardItem],
        gridZoom: HistoryGridZoomLevel = .regular,
        selectedItemID: UUID? = nil,
        onSelect: @escaping (ClipboardItem) -> Void = { _ in },
        onDoubleClick: @escaping (ClipboardItem) -> Void = { _ in }
    ) {
        self.items = items
        self.gridZoom = gridZoom
        self.selectedItemID = selectedItemID
        self.onSelect = onSelect
        self.onDoubleClick = onDoubleClick
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(
                .adaptive(
                    minimum: gridZoom.cardWidth,
                    maximum: gridZoom.cardWidth
                ),
                spacing: HistoryGridMetrics.clipboardGridSpacing
            )],
            alignment: .leading,
            spacing: HistoryGridMetrics.clipboardGridSpacing
        ) {
            ForEach(items) { item in
                ClipboardCard(
                    item: item,
                    gridZoom: gridZoom,
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
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: gridZoom
        )
    }
}

struct ClipboardPanelView: View {
    @Environment(AppModel.self) private var app

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
