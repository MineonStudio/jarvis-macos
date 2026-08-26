import AppKit
import SwiftUI

enum ClipboardViewFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case text
    case image
    case file
    case video

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all: "全部"
        case .favorites: "收藏"
        case .text: "文本"
        case .image: "图片"
        case .file: "文件"
        case .video: "视频"
        }
    }

    var icon: String? {
        switch self {
        case .all: "square.grid.2x2"
        case .favorites: "star.fill"
        case .text: ClipboardKind.text.icon
        case .image: ClipboardKind.image.icon
        case .file: ClipboardKind.file.icon
        case .video: ClipboardKind.video.icon
        }
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: true
        case .favorites: item.isPinned
        case .text: item.kind == .text
        case .image: item.kind == .image
        case .file: item.kind == .file
        case .video: item.kind == .video
        }
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
        .frame(minHeight: 44)
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
    @Binding var selectedFilter: ClipboardViewFilter
    let placeholder: String
    let focusesOnAppear: Bool
    let items: [ClipboardItem]

    private var filterCounts: [ClipboardViewFilter: Int] {
        ClipboardFilterLogic.counts(in: items)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(ClipboardViewFilter.allCases) { filter in
                    ClipboardFilterChip(
                        filter: filter,
                        count: filterCounts[filter, default: 0],
                        isSelected: selectedFilter == filter
                    ) {
                        selectedFilter = filter
                    }
                }
            }
        }
        .frame(height: 36, alignment: .leading)
    }

    private var regularLayout: some View {
        HStack(alignment: .center, spacing: 14) {
            filterChips
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 0)

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
            filterChips
                .frame(maxWidth: .infinity, alignment: .leading)

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

struct ClipboardView: View {
    @EnvironmentObject private var app: AppModel
    @State private var searchText = ""
    @State private var selectedFilter: ClipboardViewFilter = .all
    @State private var currentPage = 1

    private var filteredItems: [ClipboardItem] {
        ClipboardFilterLogic.filteredItems(
            from: app.clipboardItems,
            searchText: searchText,
            filter: selectedFilter
        )
    }

    private var totalPages: Int {
        max(1, (filteredItems.count + HistoryGridMetrics.pageSize - 1) / HistoryGridMetrics.pageSize)
    }

    private var pageItems: [ClipboardItem] {
        let page = min(max(currentPage, 1), totalPages)
        let startIndex = (page - 1) * HistoryGridMetrics.pageSize
        return Array(filteredItems.dropFirst(startIndex).prefix(HistoryGridMetrics.pageSize))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HistoryGridMetrics.imageSpacing) {
                ClipboardFilterBar(
                    searchText: $searchText,
                    selectedFilter: $selectedFilter,
                    placeholder: "搜索文本、文件名…",
                    focusesOnAppear: false,
                    items: app.clipboardItems
                )
                if filteredItems.isEmpty {
                    ClipboardEmptyState(
                        hasQuery: !searchText.isEmpty || selectedFilter != .all
                    )
                } else {
                    ClipboardGrid(items: pageItems, presentation: .main)

                    if totalPages > 1 {
                        PaginationControl(currentPage: min(currentPage, totalPages), totalPages: totalPages) {
                            currentPage = max(1, currentPage - 1)
                        } onNext: {
                            currentPage = min(totalPages, currentPage + 1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, JarvisMetrics.pageInset)
            .padding(.vertical, JarvisMetrics.pageInset)
        }
        .onChange(of: searchText) { _, _ in
            currentPage = 1
        }
        .onChange(of: selectedFilter) { _, _ in
            currentPage = 1
        }
        .onChange(of: app.clipboardItems.count) { _, _ in
            currentPage = min(currentPage, totalPages)
        }
    }
}

struct ClipboardFilterChip: View {
    let filter: ClipboardViewFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon = filter.icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text("\(filter.title)（\(count)）")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isSelected ? Color.accentColor : Color.jarvisTextSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 36)
            .background(
                isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.045),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(isSelected ? 0.16 : 0.08), lineWidth: 0.75)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.82))
        .contentShape(Capsule())
        .jarvisHoverFeedback(in: Capsule(), scale: 1.02)
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

enum ClipboardCardPresentation {
    case main
    case panel
}

struct ClipboardCard: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingDeleteConfirmation = false
    @State private var isHovered = false
    let item: ClipboardItem
    let presentation: ClipboardCardPresentation

    init(
        item: ClipboardItem,
        presentation: ClipboardCardPresentation
    ) {
        self.item = item
        self.presentation = presentation
    }

    private var previewContent: some View {
        ZStack {
            if item.kind == .text {
                Text(item.preview)
                    .font(.system(size: 12, weight: .regular))
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
                        .font(.system(size: 10, weight: .medium))
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
                .font(.system(size: 9))
                .foregroundStyle(Color.jarvisTextSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let size = item.sizeDescription {
                Text(size)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .lineLimit(1)
            }
        }
        .frame(
            width: HistoryGridMetrics.clipboardCardWidth,
            height: HistoryGridMetrics.clipboardMetadataHeight
        )
    }

    private var actionOverlay: some View {
        HStack(spacing: 5) {
            if item.kind == .image || item.kind == .video {
                Button {
                    app.showClipboardMediaPreview(item)
                } label: {
                    Image(systemName: "eye")
                        .frame(
                            width: HistoryGridMetrics.clipboardActionButtonSize,
                            height: HistoryGridMetrics.clipboardActionButtonSize
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.90, pressedOpacity: 0.76))
                .foregroundStyle(Color.secondary)
                .font(.system(size: 13, weight: .medium))
                .jarvisGlass(in: Circle(), interactive: true)
                .jarvisHoverFeedback(in: Circle(), scale: 1.06)
                .help("查看大图")
            }

            Button {
                app.copyClipboard(item)
            } label: {
                Image(systemName: "doc.on.doc")
                    .frame(
                        width: HistoryGridMetrics.clipboardActionButtonSize,
                        height: HistoryGridMetrics.clipboardActionButtonSize
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.90, pressedOpacity: 0.76))
            .foregroundStyle(Color.secondary)
            .font(.system(size: 13, weight: .medium))
            .disabled(presentation == .panel && !item.hasLocalContent)
            .jarvisGlass(in: Circle(), interactive: true)
            .jarvisHoverFeedback(in: Circle(), scale: 1.06)
            .help("复制")

            Button {
                app.toggleClipboardPin(item)
            } label: {
                Image(systemName: item.isPinned ? "star.slash" : "star")
                    .frame(
                        width: HistoryGridMetrics.clipboardActionButtonSize,
                        height: HistoryGridMetrics.clipboardActionButtonSize
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.90, pressedOpacity: 0.76))
            .foregroundStyle(item.isPinned ? .yellow : Color.jarvisTextSecondary)
            .font(.system(size: 13, weight: .medium))
            .jarvisGlass(in: Circle(), interactive: true)
            .jarvisHoverFeedback(in: Circle(), scale: 1.06)
            .help(item.isPinned ? "取消收藏" : "收藏")

            Button {
                showingDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .frame(
                        width: HistoryGridMetrics.clipboardActionButtonSize,
                        height: HistoryGridMetrics.clipboardActionButtonSize
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.90, pressedOpacity: 0.76))
            .foregroundStyle(.red.opacity(0.72))
            .font(.system(size: 13, weight: .medium))
            .jarvisGlass(in: Circle(), interactive: true)
            .jarvisHoverFeedback(in: Circle(), scale: 1.06)
            .help("删除")
        }
        .font(.system(size: 14, weight: .semibold))
        .opacity(isHovered ? 1 : 0)
        .allowsHitTesting(isHovered)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var cardBody: some View {
        ZStack(alignment: .center) {
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

            actionOverlay
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
        .contextMenu {
            if presentation == .main {
                Button(item.isPinned ? "取消收藏" : "收藏") { app.toggleClipboardPin(item) }
                Button("一键复制") { app.copyClipboard(item) }
                if item.kind != .text {
                    Button("在 Finder 中显示") { app.revealClipboardItem(item) }
                }
                Divider()
                Button("删除", role: .destructive) { showingDeleteConfirmation = true }
            }
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
    let presentation: ClipboardCardPresentation

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
                    presentation: presentation
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ClipboardPanelView: View {
    @EnvironmentObject private var app: AppModel
    @State private var searchText = ""
    @State private var selectedFilter: ClipboardViewFilter = .all

    private var filteredItems: [ClipboardItem] {
        ClipboardFilterLogic.filteredItems(
            from: app.clipboardItems,
            searchText: searchText,
            filter: selectedFilter
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HistoryGridMetrics.imageSpacing) {
            ClipboardFilterBar(
                searchText: $searchText,
                selectedFilter: $selectedFilter,
                placeholder: "搜索文本或文件名…",
                focusesOnAppear: true,
                items: app.clipboardItems
            )

            Divider()
                .overlay(Color.primary.opacity(0.10))
                .padding(.vertical, 2)

            if filteredItems.isEmpty {
                ClipboardEmptyState(
                    hasQuery: !searchText.isEmpty || selectedFilter != .all
                )
            } else {
                ScrollView {
                    ClipboardGrid(
                        items: filteredItems,
                        presentation: .panel
                    )
                }
            }

            HStack(spacing: 7) {
                Image(systemName: "info.circle")
                Text("拖动卡片主体导出内容 · 拖动标题栏移动窗口")
                Spacer()
            }
            .font(.system(size: 10))
            .foregroundStyle(Color.jarvisTextSecondary)
        }
        .padding(.top, 32)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.jarvisBackground)
        .overlay(alignment: .bottom) {
            JarvisToastHost(message: app.toastMessage)
                .padding(.bottom, 20)
        }
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            selectedFilter = .all
        }
    }
}
