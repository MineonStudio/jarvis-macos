import AppKit
import SwiftUI

struct ScreenshotView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedTimeFilter: ScreenshotTimeFilter = .threeDays
    @State private var selectedItemID: UUID?
    @State private var gridZoom: HistoryGridZoomLevel = .regular

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                ScreenshotTimeFilterBar(selectedFilter: $selectedTimeFilter)
            },
            trailingToolbar: {
                ToolbarSpacer(.fixed, placement: .automatic)
                ToolbarItem(id: "screenshot.grid-zoom", placement: .automatic) {
                    HistoryGridZoomControl(selection: $gridZoom)
                }
                ToolbarSpacer(.fixed, placement: .automatic)
                ToolbarItem(id: "screenshot.actions", placement: .automatic) {
                    ScreenshotHistoryActionToolbar(
                        selectedItem: selectedItem,
                        onClearSelection: { selectedItemID = nil }
                    )
                }
            },
            content: {
                ScrollView {
                    ScreenshotHistorySection(
                        selectedTimeFilter: $selectedTimeFilter,
                        selectedItemID: $selectedItemID,
                        gridZoom: gridZoom
                    )
                    .padding(.horizontal, HistoryGridMetrics.historyPanelInset)
                    .padding(.vertical, HistoryGridMetrics.historyPanelInset)
                }
                .jarvisModulePanel()
            }
        )
    }

    private var selectedItem: ScreenshotHistoryItem? {
        guard let selectedItemID else { return nil }
        return app.screenshotHistory.first { $0.id == selectedItemID }
    }
}

struct ScreenshotHistoryActionToolbar: View {
    @Environment(AppModel.self) private var app
    let selectedItem: ScreenshotHistoryItem?
    let onClearSelection: () -> Void
    @State private var showingDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 2) {
            JarvisToolbarIconButton(
                systemName: "eye",
                help: "查看",
                isEnabled: selectedItem != nil
            ) {
                guard let selectedItem else { return }
                app.showScreenshotHistoryPreview(selectedItem)
            }
            JarvisToolbarIconButton(
                systemName: "pencil",
                help: "编辑",
                isEnabled: selectedItem != nil
            ) {
                guard let selectedItem else { return }
                app.editScreenshotHistory(selectedItem)
            }
            JarvisToolbarIconButton(
                systemName: "doc.on.doc",
                help: "复制",
                isEnabled: selectedItem != nil
            ) {
                guard let selectedItem else { return }
                app.copyScreenshotHistory(selectedItem)
            }
            JarvisToolbarIconButton(
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
        .confirmationDialog(
            "删除这张截图？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let selectedItem else { return }
                app.deleteScreenshotHistory(selectedItem)
                onClearSelection()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复。")
        }
    }
}

enum HistoryGridZoomLevel: Int, CaseIterable, Sendable {
    case compact
    case small
    case regular
    case large
    case extraLarge

    private var widthScale: CGFloat {
        switch self {
        case .compact: 0.72
        case .small: 0.86
        case .regular: 1
        case .large: 1.16
        case .extraLarge: 1.34
        }
    }

    var cardWidth: CGFloat {
        HistoryGridMetrics.clipboardCardWidth * widthScale
    }

    var cardHeight: CGFloat {
        cardWidth * 9 / 16
    }

    /// 2× 屏上刚好盖住卡片；最小值一屏格子多，用更小的解码尺寸。
    var thumbnailPixelSize: Int {
        Int(min(512, max(160, (cardWidth * 2).rounded())))
    }

    var enablesHoverZoom: Bool {
        rawValue >= Self.regular.rawValue
    }

    var canZoomOut: Bool {
        rawValue > Self.compact.rawValue
    }

    var canZoomIn: Bool {
        rawValue < Self.extraLarge.rawValue
    }

    var zoomedOut: Self {
        Self(rawValue: rawValue - 1) ?? self
    }

    var zoomedIn: Self {
        Self(rawValue: rawValue + 1) ?? self
    }
}

struct HistoryGridZoomControl: View {
    @Binding var selection: HistoryGridZoomLevel

    var body: some View {
        JarvisToolbarZoomControl(
            canZoomOut: selection.canZoomOut,
            canZoomIn: selection.canZoomIn,
            zoomOutLabel: "缩小宫格",
            zoomInLabel: "放大宫格",
            onZoomOut: { selection = selection.zoomedOut },
            onZoomIn: { selection = selection.zoomedIn }
        )
    }
}

enum HistoryGridMetrics {
    static let imageSpacing: CGFloat = 7
    static let historyPanelInset: CGFloat = 10
    static let historyFilterToGridSpacing: CGFloat = 10

    // Both history galleries use the same 16:9 landscape panel and controls.
    //
    // 基准宽度（用户定的 200；壁纸模块那边一格约 282×190，这里比它小一档，
    // 一屏能多放一张）。想换大小改这一个数，缩放档位按它成比例走。
    static let historyCardBaseWidth: CGFloat = 200
    static let historyCardBasePadding: CGFloat = 10
    static let clipboardCardWidth: CGFloat = historyCardBaseWidth * 1.1
    static let clipboardCardHeight: CGFloat = clipboardCardWidth * 9 / 16
    static let clipboardCardPadding: CGFloat = historyCardBasePadding * 0.6
    static let clipboardPreviewHeight: CGFloat = clipboardCardHeight
    static let clipboardContentSpacing: CGFloat = 4
    static let clipboardMetadataHeight: CGFloat = 16
    static let clipboardSearchFieldWidth = JarvisToolbarMetrics.searchFieldWidth
    static let clipboardActionButtonSize = JarvisToolbarMetrics.controlSize
    static let clipboardPreviewHoverScale: CGFloat = 1.08
    static let clipboardCornerRadius: CGFloat = 12
    static let clipboardGridSpacing: CGFloat = 10
    static let topControlHeight = JarvisToolbarMetrics.controlSize
    static let clipboardSearchFieldHeight: CGFloat = topControlHeight
    static let clipboardFilterToGridSpacing: CGFloat = 10
    static let screenshotFilterBarHeight: CGFloat = topControlHeight
}

/// 宫格的列宽：先按目标宽度算这一行放几列（四舍五入到最接近的列数，卡片就不会
/// 比目标大太多），再把行内空间分满——右边不留参差的空档。
///
/// 壁纸模块是 justified 布局（行高随图的宽高比变），这里卡片比例恒为 16:9，所以改成
/// 让**列宽**承担"铺满"这件事：宽定下来，高就是宽 × 9/16，比例始终不变。
enum HistoryGridLayout {
    /// 卡片比例（恒为 16:9）。卡片视图用 `.aspectRatio` 直接挂这个值，
    /// 宽怎么变都走同一条约定。
    ///
    /// 「一行铺满」交给 `LazyVGrid` 的 `.adaptive(minimum:maximum: .infinity)`：
    /// 列数由最小宽度（缩放档位）决定，剩余空间由列自己撑开，卡片按比例跟着长高。
    /// 之前量宽度存 `@State` 再回算的写法在缩放时会滞后一帧（卡出空档），
    /// 而且每帧一次状态更新——闪烁和卡顿都是它带来的。
    static let aspectRatio: CGFloat = 16.0 / 9.0

    /// 卡片高度：比例恒为 16:9。
    static func cardHeight(forCardWidth width: CGFloat) -> CGFloat {
        width / aspectRatio
    }
}

/// 宫格的列几何：贴着一行铺满，卡片按比例跟着长。给测试用，也是这条约定的成文版本。
enum HistoryGridColumns {
    /// 按可用宽度算这一行放几列：取最接近目标宽度的那个列数。
    static func columns(availableWidth: CGFloat, targetWidth: CGFloat, spacing: CGFloat) -> Int {
        guard availableWidth > 0, targetWidth > 0 else { return 1 }
        return max(1, Int(((availableWidth + spacing) / (targetWidth + spacing)).rounded()))
    }

    /// 铺满后的列宽。
    static func cardWidth(availableWidth: CGFloat, targetWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        guard availableWidth > 0, targetWidth > 0 else { return targetWidth }
        let count = CGFloat(columns(
            availableWidth: availableWidth,
            targetWidth: targetWidth,
            spacing: spacing
        ))
        return max(1, (availableWidth - (count - 1) * spacing) / count)
    }
}

struct ScreenshotHistorySection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedTimeFilter: ScreenshotTimeFilter
    @Binding var selectedItemID: UUID?
    let gridZoom: HistoryGridZoomLevel

    private var filteredItems: [ScreenshotHistoryItem] {
        ScreenshotTimeFilterLogic.filteredItems(
            from: app.screenshotHistory,
            filter: selectedTimeFilter
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HistoryGridMetrics.historyFilterToGridSpacing) {
            if filteredItems.isEmpty {
                JarvisEmptyState(
                    icon: "photo.on.rectangle",
                    title: app.screenshotHistory.isEmpty ? "还没有截图" : "该时间范围暂无截图",
                    message: app.screenshotHistory.isEmpty
                        ? "框选截图后，历史记录会显示在这里"
                        : "切换其他时间范围查看截图"
                )
                .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
            } else {
                LazyVGrid(
                    columns: [GridItem(
                        // 列数由最小宽度决定，剩下的一点点空间让列自己撑满——
                        // 这就是"一行铺满"：不量宽度、不存状态，缩放时也就没有
                        // 滞后一帧的空档，更没有每帧状态更新带来的闪烁和卡顿。
                        .adaptive(
                            minimum: gridZoom.cardWidth,
                            maximum: .infinity
                        ),
                        spacing: HistoryGridMetrics.clipboardGridSpacing
                    )],
                    alignment: .leading,
                    spacing: HistoryGridMetrics.clipboardGridSpacing
                ) {
                    ForEach(filteredItems) { item in
                        ScreenshotHistoryCard(
                            item: item,
                            fileURL: app.screenshotHistoryFileURL(for: item),
                            isSelected: selectedItemID == item.id,
                            maxPixelSize: gridZoom.thumbnailPixelSize,
                            enablesHoverZoom: gridZoom.enablesHoverZoom,
                            onSelect: { selectedItemID = item.id },
                            onDoubleClick: { app.showScreenshotHistoryPreview(item) },
                            onCopy: { app.copyScreenshotHistory(item) },
                            onPreview: { app.showScreenshotHistoryPreview(item) },
                            onEdit: { app.editScreenshotHistory(item) },
                            onDelete: { app.deleteScreenshotHistory(item) },
                            onDragData: { app.screenshotHistoryData(for: item) },
                            onClearSelection: { selectedItemID = nil }
                        )
                        .equatable()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: selectedTimeFilter
        )
    }
}

struct ScreenshotHistoryCard: View, Equatable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingDeleteConfirmation = false
    @State private var isHovered = false
    let item: ScreenshotHistoryItem
    let fileURL: URL
    let isSelected: Bool
    let maxPixelSize: Int
    let enablesHoverZoom: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onCopy: () -> Void
    let onPreview: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDragData: () -> Data?
    let onClearSelection: () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item
            && lhs.fileURL == rhs.fileURL
            && lhs.isSelected == rhs.isSelected
            && lhs.maxPixelSize == rhs.maxPixelSize
            && lhs.enablesHoverZoom == rhs.enablesHoverZoom
    }

    private var thumbnailCacheKey: String {
        "\(item.id.uuidString)|\(item.updatedAt.timeIntervalSince1970)|\(maxPixelSize)"
    }

    /// 预览区：比例锁在**占位**这一层。
    ///
    /// `Color.clear` 是弹性的，`.aspectRatio` 才能真的按列宽定出高度；把它直接挂在
    /// 图片上不行——图片自带固有尺寸（一张竖图就能把卡片撑成 227×680），比例会被带跑。
    /// 内容盖在占位上面，溢出的部分裁掉。
    private var previewContent: some View {
        Color.clear
            .aspectRatio(HistoryGridLayout.aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { previewLayer }
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: HistoryGridMetrics.clipboardCornerRadius,
                    style: .continuous
                )
            )
            .contentShape(Rectangle())
    }

    private var previewLayer: some View {
        ScreenshotHistoryThumbnail(
            fileURL: fileURL,
            cacheKey: thumbnailCacheKey,
            maxPixelSize: maxPixelSize
        )
    }

    private var previewArea: some View {
        previewContent
            .onDrag {
                guard let data = onDragData() else {
                    return NSItemProvider()
                }
                return ScreenshotSharing.itemProvider(for: item, data: data)
            }
    }

    private var metadataRow: some View {
        HStack(spacing: 6) {
            Label("PNG", systemImage: "photo")
                .font(JarvisTypography.captionEmphasis)
                .foregroundStyle(Color.jarvisTextSecondary)
            Spacer(minLength: 4)
            Text(JarvisHistoryDateFormatting.string(from: item.updatedAt))
                .font(JarvisTypography.caption)
                .foregroundStyle(Color.jarvisTextSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: HistoryGridMetrics.clipboardMetadataHeight)
    }

    private var copyButton: some View {
        Button {
            onCopy()
        } label: {
            Text("复制")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(JarvisCardActionPillButtonStyle())
        .accessibilityLabel("复制截图")
    }

    @ViewBuilder
    private var copyActionOverlay: some View {
        if isHovered {
            HStack {
                Spacer(minLength: 0)
                copyButton
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .transition(
                reduceMotion
                    ? .identity
                    : .opacity.combined(with: .offset(y: 8))
            )
        }
    }

    private var cardBody: some View {
        HistoryCardChrome(
            preview: previewArea,
            isSelected: isSelected,
            enablesHoverZoom: enablesHoverZoom
        )
        .overlay(alignment: .bottom) {
            copyActionOverlay
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: HistoryGridMetrics.clipboardCornerRadius,
                style: .continuous
            )
        )
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("截图，PNG，\(JarvisHistoryDateFormatting.string(from: item.updatedAt))")
        .accessibilityValue(isSelected ? "已选中" : "未选中")
        .accessibilityHint("点击选择，双击预览；可以拖到 Finder 或其他应用导出 PNG")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "复制") {
            onCopy()
        }
        .contextMenu {
            Button {
                onPreview()
            } label: {
                Label("查看", systemImage: "eye")
            }
            Button {
                onEdit()
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button {
                onCopy()
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "删除这张截图？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                onDelete()
                if isSelected {
                    onClearSelection()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复。")
        }
    }
}

struct ScreenshotHistoryThumbnail: View {
    let fileURL: URL
    let cacheKey: String
    let maxPixelSize: Int
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .interpolation(.medium)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.jarvisTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: cacheKey) {
            if image == nil {
                image = JarvisThumbnailCache.cached(
                    fileURL: fileURL,
                    maxPixelSize: maxPixelSize,
                    token: cacheKey
                )
            }
            let loaded = await JarvisThumbnailCache.loadAsync(
                fileURL: fileURL,
                maxPixelSize: maxPixelSize,
                token: cacheKey
            )
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
