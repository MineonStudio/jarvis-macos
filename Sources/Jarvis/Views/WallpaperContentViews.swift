import AppKit
import SwiftUI

private enum WallpaperScrollSpace {
    static let name = "wallpaper-scroll"
}

private struct WallpaperLoadMoreTriggerPreferenceKey: PreferenceKey {
    static let defaultValue = CGFloat.infinity

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct WallpaperView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = WallpaperViewModel()
    @StateObject private var previewController = WallpaperPreviewController()
    @State private var libraryMode: WallpaperLibraryMode = .online
    @State private var deleteItem: WallpaperItem?
    @State private var tagInput = ""

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                WallpaperFilterToolbar(
                    selectedResolution: $model.selectedResolution,
                    selectedCategory: $model.selectedCategory,
                    selectedRatio: $model.selectedRatio,
                    selectedSorting: $model.selectedSorting,
                    onFilterChange: applyOnlineFilters
                )
            },
            trailingToolbar: {
                WallpaperLibraryToolbar(libraryMode: $libraryMode)
            },
            content: {
                GeometryReader { viewport in
                    ScrollView {
                        VStack(spacing: 0) {
                            if libraryMode == .online {
                                WallpaperFilterBar(
                                    tagInput: $tagInput,
                                    onSubmitTag: submitTag,
                                    onSelectTag: selectTag,
                                    onClearTag: clearTag
                                )
                            }

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
                    .onPreferenceChange(WallpaperLoadMoreTriggerPreferenceKey.self) { triggerY in
                        guard model.hasNextPage,
                              triggerY.isFinite,
                              triggerY <= viewport.size.height + 160
                        else {
                            return
                        }
                        loadMore()
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
                model.delete(deleteItem)
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
        .animation(
            JarvisMotion.animation(JarvisMotion.feedback, reduceMotion: reduceMotion),
            value: model.isLoading
        )
    }

    @ViewBuilder
    private var onlineGallery: some View {
        if model.isLoading, model.items.isEmpty {
            ProgressView("正在加载壁纸…")
                .frame(maxWidth: .infinity, minHeight: 250)
        } else if let errorMessage = model.errorMessage, model.items.isEmpty {
            WallpaperErrorState(message: errorMessage, retry: refreshOnline)
        } else {
            gallery(
                items: model.items,
                emptyTitle: "没有找到壁纸",
                emptyMessage: "换一个分辨率、分类、比例或标签试试。"
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
                onToggleFavorite: model.toggleFavorite,
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
        guard libraryMode == .online else { return }
        Task {
            await model.loadMore()
        }
    }

    private func applyOnlineFilters() {
        guard libraryMode == .online else { return }
        refreshOnline()
    }

    private func submitTag() {
        tagInput = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        model.selectedTag = tagInput
        applyOnlineFilters()
    }

    private func selectTag(_ suggestion: WallpaperTagSuggestion) {
        tagInput = suggestion.query
        model.selectedTag = suggestion.query
        applyOnlineFilters()
    }

    private func clearTag() {
        tagInput = ""
        model.selectedTag = ""
        applyOnlineFilters()
    }

    private func setWallpaper(_ item: WallpaperItem) {
        Task {
            let message = await model.downloadAndApply(item, target: .desktop)
            app.showToast(message)
        }
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
    @Binding var selectedCategory: WallpaperCategory
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
                        wallpaperMenuItemLabel(
                            resolution.title,
                            isSelected: selectedResolution == resolution
                        )
                    }
                }
            } label: {
                wallpaperFilterMenuLabel(selectedResolution.title)
            }
            .help("按最低分辨率筛选")
        }
        ToolbarItem(id: "wallpaper.filter.category", placement: .navigation) {
            Menu {
                ForEach(WallpaperCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                        onFilterChange()
                    } label: {
                        wallpaperMenuItemLabel(
                            category.title,
                            isSelected: selectedCategory == category
                        )
                    }
                }
            } label: {
                wallpaperFilterMenuLabel(selectedCategory.title)
            }
            .help("按 Wallhaven 分类组合筛选")
        }
        ToolbarItem(id: "wallpaper.filter.ratio", placement: .navigation) {
            Menu {
                ForEach(WallpaperRatio.allCases) { ratio in
                    Button {
                        selectedRatio = ratio
                        onFilterChange()
                    } label: {
                        wallpaperMenuItemLabel(
                            ratio.title,
                            isSelected: selectedRatio == ratio
                        )
                    }
                }
            } label: {
                wallpaperFilterMenuLabel(selectedRatio.title)
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
                        wallpaperMenuItemLabel(
                            sorting.title,
                            isSelected: selectedSorting == sorting
                        )
                    }
                }
            } label: {
                wallpaperFilterMenuLabel(selectedSorting.title)
            }
            .help("选择 Wallhaven 排序方式")
        }
    }
}

private func wallpaperMenuItemLabel(_ title: String, isSelected: Bool) -> some View {
    HStack(spacing: 8) {
        if isSelected {
            Image(systemName: "checkmark")
                .frame(width: 12)
        } else {
            Color.clear
                .frame(width: 12, height: 1)
        }
        Text(title)
    }
}

private func wallpaperFilterMenuLabel(_ title: String) -> some View {
    Text(title)
        .font(JarvisTypography.control)
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 12)
        .frame(height: JarvisToolbarMetrics.controlSize)
        .contentShape(Capsule())
        .fixedSize(horizontal: true, vertical: false)
        .jarvisGlass(in: Capsule(), interactive: true)
}

private struct WallpaperLoadMoreButton: View {
    let isLoading: Bool
    let errorMessage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                Text("正在加载…")
            } else if errorMessage != nil {
                Label("重试", systemImage: "arrow.clockwise")
            } else {
                Label("加载更多", systemImage: "arrow.down.circle")
            }
        }
        .buttonStyle(JarvisSecondaryButtonStyle())
        .disabled(isLoading)
        .frame(maxWidth: .infinity)
        .padding(.top, HistoryGridMetrics.clipboardGridSpacing)
        .help(errorMessage ?? "加载下一批壁纸")
    }
}

private struct WallpaperFilterBar: View {
    @Binding var tagInput: String
    let onSubmitTag: () -> Void
    let onSelectTag: (WallpaperTagSuggestion) -> Void
    let onClearTag: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                popularTags
                    .frame(maxWidth: .infinity)
                tagSearch
                    .frame(minWidth: 190, maxWidth: 250)
            }

            VStack(alignment: .leading, spacing: 8) {
                tagSearch
                    .frame(maxWidth: .infinity)
                popularTags
            }
        }
        .padding(.bottom, 12)
    }

    private var tagSearch: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag")
                .foregroundStyle(Color.jarvisTextSecondary)

            TextField("输入标签", text: $tagInput)
                .textFieldStyle(.plain)
                .onSubmit(onSubmitTag)

            if !tagInput.isEmpty {
                Button(action: onClearTag) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.jarvisTextSecondary)
                .help("清除标签")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: JarvisToolbarMetrics.controlSize)
        .jarvisGlass(in: Capsule(), interactive: false)
        .help("按标签搜索 Wallhaven")
    }

    private var popularTags: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Text("常用标签")
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .padding(.trailing, 4)

                ForEach(WallpaperTags.popular) { suggestion in
                    JarvisToolbarSelectionButton(
                        title: suggestion.title,
                        isSelected: tagInput == suggestion.query
                    ) {
                        onSelectTag(suggestion)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var previewContent: some View {
        ZStack {
            WallpaperThumbnail(url: imageURL)

            LinearGradient(
                colors: [.clear, .black.opacity(0.66)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
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
        .jarvisGlass(
            cornerRadius: HistoryGridMetrics.clipboardCornerRadius,
            interactive: false
        )
        .overlay {
            if isPreviewLoading {
                ZStack {
                    Color.black.opacity(0.28)
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
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
        .overlay(alignment: .top) {
            if isHovered {
                HStack(spacing: 6) {
                    Button(action: onToggleFavorite) {
                        Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: JarvisToolbarMetrics.iconSize, weight: .semibold))
                            .foregroundStyle(item.isFavorite ? Color.pink : Color.white)
                    }
                    .buttonStyle(JarvisToolbarIconButtonStyle())
                    .jarvisIconGlass(
                        tint: item.isFavorite ? .pink : .white,
                        in: Circle(),
                        interactive: true
                    )
                    .help(item.isFavorite ? "取消收藏" : "收藏")

                    if showsDelete {
                        Button(role: .destructive, action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: JarvisToolbarMetrics.iconSize, weight: .semibold))
                                .foregroundStyle(Color.red)
                        }
                        .buttonStyle(JarvisToolbarIconButtonStyle())
                        .jarvisIconGlass(tint: .red, in: Circle(), interactive: true)
                        .accessibilityLabel("删除")
                        .help("从已下载壁纸中删除")
                    }

                    Spacer(minLength: 0)

                    Button(
                        isApplied
                            ? "已设为壁纸"
                            : (isDownloading ? "正在设置…" : "设为壁纸"),
                        action: onSet
                    )
                    .buttonStyle(JarvisPrimaryButtonStyle())
                    .disabled(isDownloading || isApplied)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .top)
                .transition(.opacity)
            }
        }
        .onHover { isHovered = $0 }
        .animation(
            JarvisMotion.animation(JarvisMotion.feedback, reduceMotion: reduceMotion),
            value: isHovered
        )
    }

    var body: some View {
        previewContent
            .onTapGesture(count: 2, perform: onDoubleClick)
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
        .task(id: url) {
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
