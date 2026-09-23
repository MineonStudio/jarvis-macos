import AppKit
import SwiftUI

private enum WallpaperScrollSpace {
    static let name = "wallpaper-scroll"
}

private enum WallpaperScrollTarget {
    static let top = "wallpaper-scroll-top"
}

private enum WallpaperScrollBehavior {
    static let backToTopThreshold: CGFloat = 500
}

private struct WallpaperLoadMoreTriggerPreferenceKey: PreferenceKey {
    static let defaultValue = CGFloat.infinity

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct WallpaperView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = WallpaperViewModel()
    @StateObject private var previewController = WallpaperPreviewController()
    @State private var libraryMode: WallpaperLibraryMode = .online
    @State private var deleteItem: WallpaperItem?
    @State private var tagInput = ""
    @State private var shouldShowScrollToTop = false
    @State private var isLoadMoreScheduled = false

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                sourceFilterItem
                ToolbarSpacer(.fixed, placement: .automatic)
                if model.selectedSource == .qihoo {
                    qihooCategoryFilterItem
                    ToolbarSpacer(.fixed, placement: .automatic)
                    qihooResolutionFilterItem
                } else {
                    resolutionFilterItem
                    ToolbarSpacer(.fixed, placement: .automatic)
                    ratioFilterItem
                    ToolbarSpacer(.fixed, placement: .automatic)
                    sortingFilterItem
                }
            },
            trailingToolbar: {
                WallpaperLibraryToolbar(libraryMode: $libraryMode)
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(id: "wallpaper.tag-search", placement: .primaryAction) {
                    ClipboardSearchField(
                        text: $tagInput,
                        placeholder: model.selectedSource == .qihoo ? "搜索壁纸" : "搜索标签",
                        onSubmit: submitTag,
                        onClear: clearTag,
                        help: model.selectedSource == .qihoo
                            ? "按关键词搜索 360 壁纸"
                            : "按标签搜索 Wallhaven",
                        accessibilityTitle: model.selectedSource == .qihoo ? "搜索壁纸" : "搜索标签"
                    )
                }
            },
            content: {
                GeometryReader { viewport in
                    ScrollViewReader { scrollProxy in
                        galleryScrollView(viewport: viewport, scrollProxy: scrollProxy)
                    }
                }
                .jarvisModulePanel()
            }
        )
        .confirmationDialog(
            "删除这张已下载壁纸？",
            isPresented: deleteDialogPresented,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let deleteItem else { return }
                deleteWallpaper(deleteItem)
                self.deleteItem = nil
            }
            Button("取消", role: .cancel) {
                deleteItem = nil
            }
        } message: {
            Text("删除后无法恢复。")
        }
        .task {
            await model.refresh()
        }
        .onChange(of: libraryMode) { _, newMode in
            if newMode == .online {
                refreshOnline()
            } else {
                model.refreshLibrary()
            }
        }
        .onChange(of: model.selectedSource) { _, _ in
            tagInput = ""
            model.selectedTag = ""
            applyOnlineFilters()
        }
        .onDisappear {
            previewController.dismiss()
        }
    }

    // MARK: - 工具栏

    /// 三个筛选下拉的形状完全相同，只有取值和选项不同。
    private func filterItem(
        id: String,
        title: String,
        options: [JarvisDropdownOption],
        selectionID: String,
        accessibilityLabel: String,
        help: String,
        onSelect: @escaping (String) -> Void
    ) -> some ToolbarContent {
        ToolbarItem(id: id, placement: .automatic) {
            JarvisDropdownMenu(
                title: title,
                options: options,
                selectionID: selectionID,
                accessibilityLabel: accessibilityLabel,
                help: help,
                onSelect: onSelect
            )
            .id(selectionID)
        }
    }

    private var sourceFilterItem: some ToolbarContent {
        filterItem(
            id: "wallpaper.filter.source",
            title: model.selectedSource.title,
            options: WallpaperSource.onlineGalleryCases.map {
                JarvisDropdownOption(id: $0.rawValue, title: $0.title)
            },
            selectionID: model.selectedSource.rawValue,
            accessibilityLabel: "壁纸源",
            help: "选择在线壁纸源"
        ) { rawValue in
            guard let source = WallpaperSource(rawValue: rawValue),
                  WallpaperSource.onlineGalleryCases.contains(source)
            else {
                return
            }
            model.selectedSource = source
        }
    }

    private var qihooCategoryFilterItem: some ToolbarContent {
        filterItem(
            id: "wallpaper.filter.qihoo-category",
            title: model.selectedQihooCategory.title,
            options: WallpaperQihooCategory.allCases.map {
                JarvisDropdownOption(id: $0.rawValue, title: $0.title)
            },
            selectionID: model.selectedQihooCategory.rawValue,
            accessibilityLabel: "360 壁纸分类",
            help: "按 360 壁纸分类筛选"
        ) { rawValue in
            guard let category = WallpaperQihooCategory(rawValue: rawValue) else { return }
            model.selectedQihooCategory = category
            tagInput = ""
            model.selectedTag = ""
            applyOnlineFilters()
        }
    }

    private var qihooResolutionFilterItem: some ToolbarContent {
        filterItem(
            id: "wallpaper.filter.qihoo-resolution",
            title: model.selectedQihooResolution.title,
            options: WallpaperQihooResolution.allCases.map {
                JarvisDropdownOption(id: $0.rawValue, title: $0.title)
            },
            selectionID: model.selectedQihooResolution.rawValue,
            accessibilityLabel: "360 分辨率",
            help: "按 360 壁纸的实际像素尺寸筛选"
        ) { rawValue in
            guard let resolution = WallpaperQihooResolution(rawValue: rawValue) else { return }
            model.selectedQihooResolution = resolution
            applyOnlineFilters()
        }
    }

    private var resolutionFilterItem: some ToolbarContent {
        filterItem(
            id: "wallpaper.filter.resolution",
            title: model.selectedResolution.title,
            options: WallpaperResolution.allCases.map {
                JarvisDropdownOption(id: $0.rawValue, title: $0.title)
            },
            selectionID: model.selectedResolution.rawValue,
            accessibilityLabel: "分辨率筛选",
            help: "按最低分辨率筛选"
        ) { rawValue in
            guard let resolution = WallpaperResolution(rawValue: rawValue) else { return }
            model.selectedResolution = resolution
            applyOnlineFilters()
        }
    }

    private var ratioFilterItem: some ToolbarContent {
        filterItem(
            id: "wallpaper.filter.ratio",
            title: model.selectedRatio.title,
            options: WallpaperRatio.allCases.map {
                JarvisDropdownOption(id: $0.rawValue, title: $0.title)
            },
            selectionID: model.selectedRatio.rawValue,
            accessibilityLabel: "比例筛选",
            help: "按横竖屏或画面比例筛选"
        ) { rawValue in
            guard let ratio = WallpaperRatio(rawValue: rawValue) else { return }
            model.selectedRatio = ratio
            applyOnlineFilters()
        }
    }

    private var sortingFilterItem: some ToolbarContent {
        filterItem(
            id: "wallpaper.filter.sorting",
            title: model.selectedSorting.title,
            options: WallpaperSorting.allCases.map {
                JarvisDropdownOption(id: $0.rawValue, title: $0.title)
            },
            selectionID: model.selectedSorting.rawValue,
            accessibilityLabel: "排序方式",
            help: "选择 Wallhaven 排序方式"
        ) { rawValue in
            guard let sorting = WallpaperSorting(rawValue: rawValue) else { return }
            model.selectedSorting = sorting
            applyOnlineFilters()
        }
    }

    // MARK: - 画廊

    private func galleryScrollView(
        viewport: GeometryProxy,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        // macOS places the vertical scroll indicator over the trailing edge of
        // a scroll view. Keep a small gutter so the last thumbnail never sits
        // underneath it or against the module's clipping boundary.
        let availableWidth = max(
            1,
            viewport.size.width
                - (HistoryGridMetrics.historyPanelInset * 2)
                - WallpaperGalleryMetrics.trailingSafetyInset
        )

        return ScrollView {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 1)
                    .id(WallpaperScrollTarget.top)
                    .accessibilityHidden(true)

                galleryList(availableWidth: availableWidth)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, HistoryGridMetrics.historyPanelInset)
            .padding(.trailing, WallpaperGalleryMetrics.trailingSafetyInset)
            .padding(.vertical, HistoryGridMetrics.historyPanelInset)
        }
        .coordinateSpace(name: WallpaperScrollSpace.name)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.visibleRect.minY >= WallpaperScrollBehavior.backToTopThreshold
        } action: { _, shouldShow in
            shouldShowScrollToTop = shouldShow
        }
        .onPreferenceChange(WallpaperLoadMoreTriggerPreferenceKey.self) { triggerY in
            guard model.hasNextPage,
                  !model.isLoadingMore,
                  !isLoadMoreScheduled,
                  triggerY.isFinite,
                  triggerY <= viewport.size.height + 160
            else {
                return
            }
            loadMore()
        }
        .overlay(alignment: .bottomTrailing) {
            if shouldShowScrollToTop {
                scrollToTopButton(scrollProxy: scrollProxy)
            }
        }
    }

    @ViewBuilder
    private func galleryList(availableWidth: CGFloat) -> some View {
        switch libraryMode {
        case .online:
            onlineGallery(availableWidth: availableWidth)
        case .downloaded:
            gallery(
                items: model.library,
                availableWidth: availableWidth,
                emptyTitle: "还没有已下载壁纸",
                emptyMessage: "从在线图库下载壁纸后，会在这里长期保留。",
                showsDelete: true,
                onDelete: { deleteItem = $0 }
            )
        case .favorites:
            gallery(
                items: model.favorites,
                availableWidth: availableWidth,
                emptyTitle: "还没有收藏壁纸",
                emptyMessage: "在壁纸卡片上点击心形按钮，即可收藏壁纸。"
            )
        }
    }

    private func scrollToTopButton(scrollProxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(
                JarvisMotion.animation(
                    JarvisMotion.content,
                    reduceMotion: reduceMotion
                )
            ) {
                scrollProxy.scrollTo(WallpaperScrollTarget.top, anchor: .top)
            }
        } label: {
            Label("返回顶部", systemImage: "arrow.up")
        }
        .buttonStyle(JarvisSecondaryButtonStyle())
        .accessibilityLabel("返回壁纸列表顶部")
        .padding(.trailing, 18)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private func onlineGallery(availableWidth: CGFloat) -> some View {
        if model.isLoading, model.items.isEmpty {
            JarvisInlineLoadingState()
                .frame(maxWidth: .infinity, minHeight: 250)
        } else if let errorMessage = model.errorMessage, model.items.isEmpty {
            WallpaperErrorState(message: errorMessage, retry: refreshOnline)
        } else {
            gallery(
                items: model.items,
                availableWidth: availableWidth,
                emptyTitle: "没有找到壁纸",
                emptyMessage: "换一个分辨率、比例或标签试试。"
            )

            if model.hasNextPage {
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: WallpaperLoadMoreTriggerPreferenceKey.self,
                            value: proxy.frame(in: .named(WallpaperScrollSpace.name)).minY
                        )
                }
                .frame(height: 1)
                .padding(.bottom, 80)
                .id("wallpaper-load-more-trigger-\(model.items.count)")
                .accessibilityHidden(true)

                WallpaperLoadMoreButton(
                    isLoading: model.isLoadingMore,
                    errorMessage: model.loadMoreErrorMessage,
                    action: loadMore
                )
            }
        }
    }

    @ViewBuilder
    private func gallery(
        items: [WallpaperItem],
        availableWidth: CGFloat,
        emptyTitle: String,
        emptyMessage: String,
        showsDelete: Bool = false,
        onDelete: @escaping (WallpaperItem) -> Void = { _ in }
    ) -> some View {
        if items.isEmpty {
            JarvisEmptyState(
                icon: "photo.on.rectangle.angled",
                title: emptyTitle,
                message: emptyMessage
            )
        } else {
            WallpaperGrid(
                items: items,
                availableWidth: availableWidth,
                imageURL: { model.localURL(for: $0) ?? $0.previewURL },
                isDownloading: { model.isDownloading($0) },
                isPreviewLoading: { previewController.isLoading(itemID: $0.id) },
                onDoubleClick: { item in
                    previewController.show(
                        imageURL: model.localURL(for: item) ?? item.originalURL,
                        itemID: item.id,
                        onFailure: { app.showToast("原图加载失败") }
                    )
                },
                onSet: setWallpaper,
                isApplied: { model.isApplied($0) },
                onToggleFavorite: toggleFavorite,
                showsDelete: showsDelete,
                onDelete: onDelete
            )
        }
    }

    private var deleteDialogPresented: Binding<Bool> {
        Binding(
            get: { deleteItem != nil },
            set: { isPresented in
                if !isPresented {
                    deleteItem = nil
                }
            }
        )
    }

    private func refreshOnline() {
        guard libraryMode == .online else { return }
        Task {
            await model.refresh()
        }
    }

    private func loadMore() {
        guard libraryMode == .online,
              !model.isLoadingMore,
              !isLoadMoreScheduled
        else {
            return
        }
        isLoadMoreScheduled = true
        Task {
            await model.loadMore()
            isLoadMoreScheduled = false
        }
    }

    private func applyOnlineFilters() {
        guard libraryMode == .online else { return }
        refreshOnline()
    }

    private func submitTag() {
        let tag = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        tagInput = tag
        model.selectedTag = tag
        if libraryMode == .online {
            applyOnlineFilters()
        } else {
            libraryMode = .online
        }
    }

    private func clearTag() {
        tagInput = ""
        model.selectedTag = ""
        applyOnlineFilters()
    }

    private func setWallpaper(_ item: WallpaperItem) {
        Task {
            let message = await model.downloadAndApply(item, target: .both)
            app.showToast(message)
        }
    }

    private func toggleFavorite(_ item: WallpaperItem) {
        guard let updatedItem = model.toggleFavorite(item) else { return }
        app.showToast(updatedItem.isFavorite ? "收藏成功" : "已取消收藏")
    }

    private func deleteWallpaper(_ item: WallpaperItem) {
        guard model.delete(item) else { return }
        app.showToast("删除成功")
    }
}

/// 图库来源（在线图库 / 已下载 / 我的收藏）：与截图模块同一枚分组容器。
private struct WallpaperLibraryToolbar: ToolbarContent {
    @Binding var libraryMode: WallpaperLibraryMode

    var body: some ToolbarContent {
        JarvisToolbarSurface(id: "wallpaper.library", placement: .primaryAction) {
            JarvisToolbarGroupedPicker(
                items: WallpaperLibraryMode.allCases,
                selection: $libraryMode,
                title: \.title
            )
        }
    }
}

private struct WallpaperLoadMoreButton: View {
    let isLoading: Bool
    let errorMessage: String?
    let action: () -> Void

    var body: some View {
        if isLoading {
            JarvisInlineLoadingState()
                .frame(maxWidth: .infinity)
                .padding(.top, HistoryGridMetrics.clipboardGridSpacing)
        } else {
            Button(action: action) {
                if errorMessage != nil {
                    Label("重试", systemImage: "arrow.clockwise")
                } else {
                    Label("加载更多", systemImage: "arrow.down.circle")
                }
            }
            .buttonStyle(JarvisSecondaryButtonStyle())
            .frame(maxWidth: .infinity)
            .padding(.top, HistoryGridMetrics.clipboardGridSpacing)
        }
    }
}

private enum WallpaperGalleryMetrics {
    // Keep the existing justified-gallery proportions while giving every
    // wallpaper tile a little more breathing room.
    static let heightScale: CGFloat = 1.20
    static let idealRowHeight: CGFloat = 158 * heightScale
    static let minimumRowHeight: CGFloat = 128 * heightScale
    static let maximumRowHeight: CGFloat = 220 * heightScale
    static let trailingSafetyInset: CGFloat = 14
    static let cardSpacing = HistoryGridMetrics.clipboardGridSpacing
    static let actionSpacing: CGFloat = 5
}

private struct WallpaperJustifiedRow: Identifiable {
    let id: Int
    let items: [WallpaperItem]
    let widths: [CGFloat]
    let height: CGFloat
}

private enum WallpaperJustifiedLayout {
    static func rows(
        for items: [WallpaperItem],
        availableWidth: CGFloat,
        spacing: CGFloat = WallpaperGalleryMetrics.cardSpacing
    ) -> [WallpaperJustifiedRow] {
        guard !items.isEmpty else { return [] }

        let width = max(1, availableWidth)
        var rows: [WallpaperJustifiedRow] = []
        var currentItems: [WallpaperItem] = []

        for item in items {
            currentItems.append(item)

            guard currentItems.count > 1 else { continue }
            if fittedHeight(
                for: currentItems,
                availableWidth: width,
                spacing: spacing
            ) < WallpaperGalleryMetrics.minimumRowHeight {
                currentItems.removeLast()
                rows.append(
                    makeRow(
                        id: rows.count,
                        items: currentItems,
                        availableWidth: width,
                        spacing: spacing,
                        isLastRow: false
                    )
                )
                currentItems = [item]
            }
        }

        if !currentItems.isEmpty {
            rows.append(
                makeRow(
                    id: rows.count,
                    items: currentItems,
                    availableWidth: width,
                    spacing: spacing,
                    isLastRow: true
                )
            )
        }
        return rows
    }

    private static func makeRow(
        id: Int,
        items: [WallpaperItem],
        availableWidth: CGFloat,
        spacing: CGFloat,
        isLastRow: Bool
    ) -> WallpaperJustifiedRow {
        let fittedHeight = fittedHeight(
            for: items,
            availableWidth: availableWidth,
            spacing: spacing
        )
        let minimumHeight = items.count == 1
            ? 1
            : WallpaperGalleryMetrics.minimumRowHeight
        let requestedHeight = isLastRow
            ? min(WallpaperGalleryMetrics.idealRowHeight, fittedHeight)
            : min(
                WallpaperGalleryMetrics.maximumRowHeight,
                max(minimumHeight, fittedHeight)
            )

        // A minimum row height can make a single ultra-wide wallpaper exceed
        // the available width. Scale the whole row down as a final guard so
        // the aspect ratios stay intact while the row can never overflow.
        let totalAspectRatio = items
            .map(aspectRatio(for:))
            .reduce(0, +)
        let totalSpacing = spacing * CGFloat(max(0, items.count - 1))
        let requestedWidth = totalAspectRatio * requestedHeight + totalSpacing
        let widthScale = min(1, availableWidth / max(1, requestedWidth))
        let height = requestedHeight * widthScale
        let widths = items.map { aspectRatio(for: $0) * height }
        return WallpaperJustifiedRow(
            id: id,
            items: items,
            widths: widths,
            height: height
        )
    }

    private static func fittedHeight(
        for items: [WallpaperItem],
        availableWidth: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        let totalAspectRatio = items
            .map(aspectRatio(for:))
            .reduce(0, +)
        guard totalAspectRatio > 0 else {
            return WallpaperGalleryMetrics.idealRowHeight
        }

        let totalSpacing = spacing * CGFloat(max(0, items.count - 1))
        return max(1, (availableWidth - totalSpacing) / totalAspectRatio)
    }

    private static func aspectRatio(for item: WallpaperItem) -> CGFloat {
        guard item.width > 0, item.height > 0 else { return 16 / 9 }
        return max(0.1, CGFloat(item.width) / CGFloat(item.height))
    }
}

private struct WallpaperGrid: View {
    let items: [WallpaperItem]
    let availableWidth: CGFloat
    let imageURL: (WallpaperItem) -> URL
    let isDownloading: (WallpaperItem) -> Bool
    let isPreviewLoading: (WallpaperItem) -> Bool
    let onDoubleClick: (WallpaperItem) -> Void
    let onSet: (WallpaperItem) -> Void
    let isApplied: (WallpaperItem) -> Bool
    let onToggleFavorite: (WallpaperItem) -> Void
    let showsDelete: Bool
    let onDelete: (WallpaperItem) -> Void

    private var rows: [WallpaperJustifiedRow] {
        WallpaperJustifiedLayout.rows(
            for: items,
            availableWidth: availableWidth
        )
    }

    var body: some View {
        LazyVStack(
            alignment: .leading,
            spacing: WallpaperGalleryMetrics.cardSpacing
        ) {
            ForEach(rows) { row in
                HStack(
                    alignment: .top,
                    spacing: WallpaperGalleryMetrics.cardSpacing
                ) {
                    ForEach(row.items.indices, id: \.self) { index in
                        let item = row.items[index]
                        WallpaperCard(
                            item: item,
                            imageURL: imageURL(item),
                            cardWidth: row.widths[index],
                            cardHeight: row.height,
                            isDownloading: isDownloading(item),
                            isPreviewLoading: isPreviewLoading(item),
                            onDoubleClick: { onDoubleClick(item) },
                            onSet: { onSet(item) },
                            isApplied: isApplied(item),
                            onToggleFavorite: { onToggleFavorite(item) },
                            showsDelete: showsDelete,
                            onDelete: { onDelete(item) }
                        )
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WallpaperCircleButtonStyle: ButtonStyle {
    let tint: Color?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: JarvisToolbarMetrics.iconSize, weight: .semibold))
            .foregroundStyle(tint ?? .primary)
            .frame(
                width: JarvisToolbarMetrics.controlSize,
                height: JarvisToolbarMetrics.controlSize
            )
            .opacity(configuration.isPressed ? 0.68 : 1)
            .jarvisGlass(in: Circle())
            .contentShape(Circle())
            .shadow(
                color: Color.black.opacity(0.24),
                radius: 6,
                y: 2
            )
            .scaleEffect(
                reduceMotion ? 1 : (configuration.isPressed ? 0.94 : 1)
            )
            .animation(
                JarvisMotion.animation(JarvisMotion.buttonPress, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

private struct WallpaperCard: View {
    let item: WallpaperItem
    let imageURL: URL
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let isDownloading: Bool
    let isPreviewLoading: Bool
    let onDoubleClick: () -> Void
    let onSet: () -> Void
    let isApplied: Bool
    let onToggleFavorite: () -> Void
    let showsDelete: Bool
    let onDelete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var cardShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: HistoryGridMetrics.clipboardCornerRadius,
            style: .continuous
        )
    }

    private var setWallpaperAccessibilityLabel: String {
        isApplied
            ? "当前壁纸"
            : (isDownloading ? "正在设置壁纸" : "设为壁纸")
    }

    @ViewBuilder
    private var setWallpaperButton: some View {
        if cardWidth < 160 {
            Button(action: onSet) {
                Image(systemName: "checkmark")
            }
            .buttonStyle(WallpaperCircleButtonStyle(tint: nil))
            .disabled(isDownloading || isApplied)
            .accessibilityLabel(setWallpaperAccessibilityLabel)
        } else {
            Button(action: onSet) {
                Text(
                    isApplied
                        ? "当前壁纸"
                        : (isDownloading ? "正在设置…" : "设为壁纸")
                )
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(JarvisCardActionPillButtonStyle())
            .disabled(isDownloading || isApplied)
            .accessibilityLabel(setWallpaperAccessibilityLabel)
        }
    }

    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: item.isFavorite ? "heart.fill" : "heart")
        }
        .buttonStyle(WallpaperCircleButtonStyle(tint: item.isFavorite ? .pink : nil))
        .accessibilityLabel(item.isFavorite ? "取消收藏" : "收藏")
    }

    private var deleteButton: some View {
        Button(role: .destructive, action: onDelete) {
            Image(systemName: "trash")
                .font(.system(size: JarvisToolbarMetrics.iconSize, weight: .semibold))
                .foregroundStyle(Color.red)
        }
        .buttonStyle(JarvisToolbarIconButtonStyle())
        .background(
            Color.black.opacity(0.46),
            in: Circle()
        )
        .shadow(
            color: Color.black.opacity(0.24),
            radius: 6,
            y: 2
        )
        .accessibilityLabel("删除")
    }

    @ViewBuilder
    private var hoverActions: some View {
        if cardWidth < 160 {
            HStack(alignment: .center, spacing: WallpaperGalleryMetrics.actionSpacing) {
                favoriteButton
                if showsDelete {
                    deleteButton
                }
                Spacer(minLength: 0)
                setWallpaperButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 6) {
                favoriteButton
                if showsDelete {
                    deleteButton
                }
                Spacer(minLength: 0)
                setWallpaperButton
            }
        }
    }

    private var previewContent: some View {
        ZStack {
            WallpaperThumbnail(url: imageURL)
        }
        .frame(
            width: cardWidth,
            height: cardHeight,
            alignment: .center
        )
        .contentShape(cardShape)
        .accessibilityLabel("\(item.title)，\(item.resolutionDescription)")
        .overlay {
            if isPreviewLoading {
                ZStack {
                    Color.black.opacity(0.5)
                    ProgressView()
                        .controlSize(.large)
                        .scaleEffect(1.35)
                        .tint(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: HistoryGridMetrics.clipboardCornerRadius,
                        style: .continuous
                    )
                )
                .allowsHitTesting(false)
                .accessibilityLabel("正在加载原图")
            }
        }
        .overlay(alignment: .bottom) {
            if isHovered {
                hoverActions
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(
                        reduceMotion
                            ? .identity
                            : .opacity.combined(with: .offset(y: 8))
                    )
            }
        }
        .clipShape(cardShape)
        .overlay {
            cardShape
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }

    var body: some View {
        previewContent
            .onTapGesture(count: 2, perform: onDoubleClick)
            .onHover { hovering in
                guard hovering != isHovered else { return }
                withAnimation(
                    JarvisMotion.animation(
                        JarvisMotion.content,
                        reduceMotion: reduceMotion
                    )
                ) {
                    isHovered = hovering
                }
            }
    }
}

private struct WallpaperThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.jarvisInsetSurface
            if let image {
                Image(nsImage: image)
                    .resizable()
                    // The row layout already derives the card width from the
                    // wallpaper's aspect ratio. Fit the bitmap inside that
                    // exact frame so the thumbnail never crops its edges.
                    .scaledToFit()
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: url, priority: .utility) {
            image = await WallpaperImageLoader.load(url: url)
        }
    }
}

private struct WallpaperErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.orange)
            Text(message)
                .font(JarvisTypography.secondary)
                .foregroundStyle(Color.jarvisTextSecondary)
                .multilineTextAlignment(.center)
            Button("重试", action: retry)
                .buttonStyle(JarvisSecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 250)
    }
}
