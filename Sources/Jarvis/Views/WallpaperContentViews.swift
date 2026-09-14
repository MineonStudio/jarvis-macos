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
                WallpaperFilterToolbar(
                    selectedResolution: $model.selectedResolution,
                    selectedRatio: $model.selectedRatio,
                    selectedSorting: $model.selectedSorting,
                    onFilterChange: applyOnlineFilters
                )
            },
            trailingToolbar: {
                WallpaperLibraryToolbar(libraryMode: $libraryMode)
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(id: "wallpaper.tag-search", placement: .primaryAction) {
                    ClipboardSearchField(
                        text: $tagInput,
                        placeholder: "搜索标签",
                        onSubmit: submitTag,
                        onClear: clearTag,
                        help: "按标签搜索 Wallhaven",
                        accessibilityTitle: "搜索标签"
                    )
                }
            },
            content: {
                GeometryReader { viewport in
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                Color.clear
                                    .frame(height: 1)
                                    .id(WallpaperScrollTarget.top)
                                    .accessibilityHidden(true)

                                switch libraryMode {
                                case .online:
                                    onlineGallery
                                case .downloaded:
                                    gallery(
                                        items: model.library,
                                        emptyTitle: "还没有已下载壁纸",
                                        emptyMessage: "从 Wallhaven 下载壁纸后，会在这里长期保留。",
                                        showsDelete: true,
                                        onDelete: { deleteItem = $0 }
                                    )
                                case .favorites:
                                    gallery(
                                        items: model.favorites,
                                        emptyTitle: "还没有收藏壁纸",
                                        emptyMessage: "在壁纸卡片上点击心形按钮，即可收藏壁纸。"
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, HistoryGridMetrics.historyPanelInset)
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
                                .help("返回壁纸列表顶部")
                                .padding(.trailing, 18)
                                .padding(.bottom, 18)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .jarvisFloatingPanel(cornerRadius: 16)
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
        .onDisappear {
            previewController.dismiss()
        }
    }

    @ViewBuilder
    private var onlineGallery: some View {
        if model.isLoading, model.items.isEmpty {
            JarvisInlineLoadingState()
                .frame(maxWidth: .infinity, minHeight: 250)
        } else if let errorMessage = model.errorMessage, model.items.isEmpty {
            WallpaperErrorState(message: errorMessage, retry: refreshOnline)
        } else {
            gallery(
                items: model.items,
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

private struct WallpaperLibraryToolbar: ToolbarContent {
    @Binding var libraryMode: WallpaperLibraryMode

    var body: some ToolbarContent {
        ToolbarItem(id: "wallpaper.library.online", placement: .primaryAction) {
            JarvisToolbarSelectionButton(
                title: WallpaperLibraryMode.online.title,
                isSelected: libraryMode == .online
            ) {
                libraryMode = .online
            }
            .help("查看 Wallhaven 在线图库")
        }
        ToolbarItem(id: "wallpaper.library.downloaded", placement: .primaryAction) {
            JarvisToolbarSelectionButton(
                title: WallpaperLibraryMode.downloaded.title,
                isSelected: libraryMode == .downloaded
            ) {
                libraryMode = .downloaded
            }
            .help("查看已下载壁纸")
        }
        ToolbarItem(id: "wallpaper.library.favorites", placement: .primaryAction) {
            JarvisToolbarSelectionButton(
                title: WallpaperLibraryMode.favorites.title,
                isSelected: libraryMode == .favorites
            ) {
                libraryMode = .favorites
            }
            .help("查看我的收藏")
        }
    }
}

private struct WallpaperFilterToolbar: ToolbarContent {
    @Binding var selectedResolution: WallpaperResolution
    @Binding var selectedRatio: WallpaperRatio
    @Binding var selectedSorting: WallpaperSorting
    let onFilterChange: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(id: "wallpaper.filter.resolution", placement: .navigation) {
            Menu {
                ForEach(WallpaperResolution.allCases) { resolution in
                    Button {
                        selectedResolution = resolution
                        onFilterChange()
                    } label: {
                        jarvisToolbarMenuItemLabel(
                            resolution.title,
                            isSelected: selectedResolution == resolution
                        )
                    }
                }
            } label: {
                JarvisToolbarMenuLabel(title: selectedResolution.title)
            }
            .help("按最低分辨率筛选")
        }
        ToolbarItem(id: "wallpaper.filter.ratio", placement: .navigation) {
            Menu {
                ForEach(WallpaperRatio.allCases) { ratio in
                    Button {
                        selectedRatio = ratio
                        onFilterChange()
                    } label: {
                        jarvisToolbarMenuItemLabel(
                            ratio.title,
                            isSelected: selectedRatio == ratio
                        )
                    }
                }
            } label: {
                JarvisToolbarMenuLabel(title: selectedRatio.title)
            }
            .help("按横竖屏或画面比例筛选")
        }
        ToolbarItem(id: "wallpaper.filter.sorting", placement: .navigation) {
            Menu {
                ForEach(WallpaperSorting.allCases) { sorting in
                    Button {
                        selectedSorting = sorting
                        onFilterChange()
                    } label: {
                        jarvisToolbarMenuItemLabel(
                            sorting.title,
                            isSelected: selectedSorting == sorting
                        )
                    }
                }
            } label: {
                JarvisToolbarMenuLabel(title: selectedSorting.title)
            }
            .help("选择 Wallhaven 排序方式")
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
            .help(errorMessage ?? "加载下一批壁纸")
        }
    }
}

private struct WallpaperGrid: View {
    let items: [WallpaperItem]
    let imageURL: (WallpaperItem) -> URL
    let isDownloading: (WallpaperItem) -> Bool
    let isPreviewLoading: (WallpaperItem) -> Bool
    let onDoubleClick: (WallpaperItem) -> Void
    let onSet: (WallpaperItem) -> Void
    let isApplied: (WallpaperItem) -> Bool
    let onToggleFavorite: (WallpaperItem) -> Void
    let showsDelete: Bool
    let onDelete: (WallpaperItem) -> Void

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
                WallpaperCard(
                    item: item,
                    imageURL: imageURL(item),
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WallpaperCard: View {
    let item: WallpaperItem
    let imageURL: URL
    let isDownloading: Bool
    let isPreviewLoading: Bool
    let onDoubleClick: () -> Void
    let onSet: () -> Void
    let isApplied: Bool
    let onToggleFavorite: () -> Void
    let showsDelete: Bool
    let onDelete: () -> Void
    @State private var isHovered = false

    private var previewContent: some View {
        ZStack {
            WallpaperThumbnail(url: imageURL)
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
        .overlay {
            RoundedRectangle(
                cornerRadius: HistoryGridMetrics.clipboardCornerRadius,
                style: .continuous
            )
            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
            .allowsHitTesting(false)
        }
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
                HStack(spacing: 6) {
                    Button(action: onToggleFavorite) {
                        Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: JarvisToolbarMetrics.iconSize, weight: .semibold))
                            .foregroundStyle(item.isFavorite ? Color.pink : Color.white)
                    }
                    .buttonStyle(JarvisToolbarIconButtonStyle())
                    .background(
                        Color.black.opacity(0.46),
                        in: Circle()
                    )
                    .accessibilityLabel(item.isFavorite ? "取消收藏" : "收藏")
                    .help(item.isFavorite ? "取消收藏" : "收藏")

                    if showsDelete {
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
                        .accessibilityLabel("删除")
                        .help("从已下载壁纸中删除")
                    }

                    Spacer(minLength: 0)

                    Button(
                        isApplied
                            ? "当前壁纸"
                            : (isDownloading ? "正在设置…" : "设为壁纸"),
                        action: onSet
                    )
                    .buttonStyle(WallpaperCardPrimaryButtonStyle())
                    .disabled(isDownloading || isApplied)
                    .accessibilityLabel(
                        isApplied
                            ? "当前壁纸"
                            : (isDownloading ? "正在设置壁纸" : "设为壁纸")
                    )
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.identity)
            }
        }
    }

    var body: some View {
        previewContent
            .onTapGesture(count: 2, perform: onDoubleClick)
            .onHover { hovering in
                guard hovering != isHovered else { return }
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    isHovered = hovering
                }
            }
    }
}

private struct WallpaperCardPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(JarvisTypography.controlEmphasis)
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .background(
                isEnabled ? Color.accentColor : Color.primary.opacity(0.16),
                in: RoundedRectangle(cornerRadius: JarvisMetrics.controlRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: JarvisMetrics.controlRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(isEnabled ? 0.18 : 0.08), lineWidth: 0.75)
            }
            .opacity(configuration.isPressed ? 0.78 : (isEnabled ? 1 : 0.78))
    }
}

private struct WallpaperThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.primary.opacity(0.045)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
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
