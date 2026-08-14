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
                .buttonStyle(.borderless)
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
}

struct ClipboardFilterBar: View {
    @Binding var searchText: String
    @Binding var selectedFilter: ClipboardViewFilter
    let placeholder: String
    let focusesOnAppear: Bool
    let items: [ClipboardItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ClipboardSearchField(
                text: $searchText,
                placeholder: placeholder,
                focusesOnAppear: focusesOnAppear
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(ClipboardViewFilter.allCases) { filter in
                        ClipboardFilterChip(
                            filter: filter,
                            count: ClipboardFilterLogic.count(for: filter, in: items),
                            isSelected: selectedFilter == filter
                        ) {
                            selectedFilter = filter
                        }
                    }
                }
            }
        }
    }
}

struct ClipboardView: View {
    @EnvironmentObject private var app: AppModel
    @State private var searchText = ""
    @State private var selectedFilter: ClipboardViewFilter = .all
    @State private var currentPage = 1
    @AppStorage("jarvis.clipboardGridThumbnailMode") private var thumbnailModeRawValue = GridThumbnailDisplayMode.square.rawValue

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
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("剪贴板", systemImage: "clipboard")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(app.clipboardItems.count) 条")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.jarvisTextSecondary)
                    GridThumbnailModeMenu(rawValue: $thumbnailModeRawValue)
                }

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
                    LazyVGrid(
                        columns: [GridItem(
                            .adaptive(
                                minimum: HistoryGridMetrics.minimumCardWidth,
                                maximum: HistoryGridMetrics.maximumCardWidth
                            ),
                            spacing: HistoryGridMetrics.spacing
                        )],
                        spacing: HistoryGridMetrics.spacing
                    ) {
                        ForEach(pageItems) { item in
                            ClipboardCard(
                                item: item,
                                presentation: .main,
                                thumbnailDisplayMode: GridThumbnailDisplayMode(rawValue: thumbnailModeRawValue) ?? .square
                            )
                        }
                    }

                    if totalPages > 1 {
                        PaginationControl(currentPage: min(currentPage, totalPages), totalPages: totalPages) {
                            currentPage = max(1, currentPage - 1)
                        } onNext: {
                            currentPage = min(totalPages, currentPage + 1)
                        }
                    }
                }
            }
            .padding(JarvisMetrics.pageInset)
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
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }
}

struct ClipboardEmptyState: View {
    let hasQuery: Bool

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: hasQuery ? "line.3.horizontal.decrease.circle" : "clipboard")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text(hasQuery ? "没有找到匹配内容" : "复制一些内容，历史会自动出现在这里")
                .font(.system(size: 14, weight: .medium))
            Text(hasQuery ? "换个关键词或切换内容类型试试" : "可前往设置页自定义剪贴板快捷键")
                .font(.system(size: 11))
                .foregroundStyle(Color.jarvisTextSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .jarvisGlass(cornerRadius: JarvisMetrics.cardRadius, interactive: false)
    }
}

enum ClipboardCardPresentation {
    case main
    case panel
}

struct ClipboardCard: View {
    @EnvironmentObject private var app: AppModel
    let item: ClipboardItem
    let presentation: ClipboardCardPresentation
    let thumbnailDisplayMode: GridThumbnailDisplayMode
    let onPreview: (() -> Void)?

    init(
        item: ClipboardItem,
        presentation: ClipboardCardPresentation,
        thumbnailDisplayMode: GridThumbnailDisplayMode = .square,
        onPreview: (() -> Void)? = nil
    ) {
        self.item = item
        self.presentation = presentation
        self.thumbnailDisplayMode = thumbnailDisplayMode
        self.onPreview = onPreview
    }

    private var previewButton: some View {
        Button {
            if presentation == .panel {
                onPreview?()
            } else if item.kind == .image || item.kind == .video {
                app.showClipboardMediaPreview(item)
            } else {
                app.copyClipboard(item)
            }
        } label: {
            ZStack {
                if item.kind == .text {
                    Text(item.preview)
                        .font(.system(size: 12, weight: .regular))
                        .lineLimit(6)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(12)
                } else if item.kind == .file {
                    VStack(spacing: 10) {
                        Image(systemName: item.kind.icon)
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                        Text(item.preview)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ClipboardItemPreview(item: item, displayMode: thumbnailDisplayMode)
                }
            }
            .frame(
                width: HistoryGridMetrics.cardWidth - (HistoryGridMetrics.cardPadding * 2),
                height: HistoryGridMetrics.previewHeight
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(presentation == .panel && item.kind != .image && item.kind != .video)
        .help(item.kind == .image || item.kind == .video ? "查看大图" : "一键复制")
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
        .frame(height: 18)
    }

    private var actionBar: some View {
        HStack(spacing: 4) {
            Button {
                app.copyClipboard(item)
            } label: {
                Label("一键复制", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(JarvisSecondaryButtonStyle())
            .disabled(presentation == .panel && !item.hasLocalContent)

            if presentation == .main {
                Button {
                    app.toggleClipboardPin(item)
                } label: {
                    Image(systemName: item.isPinned ? "star.slash" : "star")
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(item.isPinned ? .yellow : Color.jarvisTextSecondary)
                .help(item.isPinned ? "取消收藏" : "收藏")
                Button {
                    app.deleteClipboardItem(item)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red.opacity(0.72))
                .help("删除")
            }
        }
        .frame(height: 30)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            previewButton
            metadataRow
            actionBar
        }
        .padding(HistoryGridMetrics.cardPadding)
        .frame(
            width: HistoryGridMetrics.cardWidth,
            height: HistoryGridMetrics.cardHeight,
            alignment: .topLeading
        )
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .contextMenu {
            if presentation == .main {
                Button(item.isPinned ? "取消收藏" : "收藏") { app.toggleClipboardPin(item) }
                Button("一键复制") { app.copyClipboard(item) }
                if item.kind != .text {
                    Button("在 Finder 中显示") { app.revealClipboardItem(item) }
                }
                Divider()
                Button("删除", role: .destructive) { app.deleteClipboardItem(item) }
            }
        }
    }
}

struct ClipboardPanelView: View {
    @EnvironmentObject private var app: AppModel
    @State private var searchText = ""
    @State private var selectedFilter: ClipboardViewFilter = .all
    @AppStorage("jarvis.clipboardGridThumbnailMode") private var thumbnailModeRawValue = GridThumbnailDisplayMode.square.rawValue

    private var filteredItems: [ClipboardItem] {
        ClipboardFilterLogic.filteredItems(
            from: app.clipboardItems,
            searchText: searchText,
            filter: selectedFilter
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("剪贴板", systemImage: "clipboard")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                GridThumbnailModeMenu(rawValue: $thumbnailModeRawValue)
            }

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
                    LazyVGrid(
                        columns: [GridItem(
                            .adaptive(
                                minimum: HistoryGridMetrics.minimumCardWidth,
                                maximum: HistoryGridMetrics.maximumCardWidth
                            ),
                            spacing: HistoryGridMetrics.spacing
                        )],
                        spacing: HistoryGridMetrics.spacing
                    ) {
                        ForEach(filteredItems) { item in
                            ClipboardCard(
                                item: item,
                                presentation: .panel,
                                thumbnailDisplayMode: GridThumbnailDisplayMode(rawValue: thumbnailModeRawValue) ?? .square,
                                onPreview: { app.showClipboardMediaPreview(item) }
                            )
                        }
                    }
                }
            }

            HStack(spacing: 7) {
                Image(systemName: "info.circle")
                Text("手动点击一键复制")
                Spacer()
            }
            .font(.system(size: 10))
            .foregroundStyle(Color.jarvisTextSecondary)
        }
        .padding(20)
        .background(Color.jarvisBackground)
        .onAppear {
            selectedFilter = .all
        }
    }
}
