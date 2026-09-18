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
    // 基准宽度对齐壁纸模块的观感：那边一格约 282×190，换算成 16:9 就是 280×158。
    // 原来 192 明显偏小（同一块面板里比壁纸那边小一圈半），宫格看着碎。
    static let historyCardBaseWidth: CGFloat = 280
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
    static func cardWidth(
        availableWidth: CGFloat,
        targetWidth: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        guard availableWidth > 0, targetWidth > 0 else { return targetWidth }
        let columns = max(1, Int(((availableWidth + spacing) / (targetWidth + spacing)).rounded()))
        let filled = (availableWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        // 窗口窄到一列都放不满时按可用宽度收；上界防极端情况撑出一张巨卡。
        return max(1, min(filled, targetWidth * 1.5))
    }

    /// 卡片高度：比例恒为 16:9。
    static func cardHeight(forCardWidth width: CGFloat) -> CGFloat {
        width * 9 / 16
    }
}

struct ScreenshotHistorySection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedTimeFilter: ScreenshotTimeFilter
    @Binding var selectedItemID: UUID?
    let gridZoom: HistoryGridZoomLevel
    /// 宫格可用宽度（量出来才能把这一行铺满）。
    @State private var availableWidth: CGFloat = 0

    /// 实际列宽：由可用宽度和目标宽度算出来，卡片按它等比例缩放，比例恒为 16:9。
    private var cardWidth: CGFloat {
        HistoryGridLayout.cardWidth(
            availableWidth: availableWidth,
            targetWidth: gridZoom.cardWidth,
            spacing: HistoryGridMetrics.clipboardGridSpacing
        )
    }

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
                        // 列宽由 `HistoryGridLayout` 按可用宽度算好，正好铺满一行；
                        // 这里仍用 adaptive（min == max）：实测 .fixed 在滚动视图里
                        // 只排得下一列，adaptive 才是可靠的那条路。
                        .adaptive(minimum: cardWidth, maximum: cardWidth),
                        spacing: HistoryGridMetrics.clipboardGridSpacing
                    )],
                    alignment: .leading,
                    spacing: HistoryGridMetrics.clipboardGridSpacing
                ) {
                    ForEach(filteredItems) { item in
                        ScreenshotHistoryCard(
                            item: item,
                            cardWidth: cardWidth,
                            isSelected: selectedItemID == item.id,
                            onSelect: { selectedItemID = item.id },
                            onDoubleClick: { app.showScreenshotHistoryPreview(item) },
                            onClearSelection: { selectedItemID = nil }
                        )
                        .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(
                    JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
                    value: filteredItems.map(\.id)
                )
                .animation(
                    JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
                    value: gridZoom
                )
            }
        }
        // 量的是**外框**而不是宫格自己：宫格是定宽列，量它会量到"一张卡那么宽"，
        // 算出来的列数永远是 1（自己把自己锁死）。
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { availableWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in
                        availableWidth = width
                    }
            }
        }
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: selectedTimeFilter
        )
    }
}

struct ScreenshotHistoryCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingDeleteConfirmation = false
    @State private var isHovered = false
    let item: ScreenshotHistoryItem
    /// 这一列的宽度（由宫格算出，比例恒为 16:9）。
    let cardWidth: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onClearSelection: () -> Void

    private var thumbnailCacheKey: String {
        "\(item.id.uuidString)|\(item.updatedAt.timeIntervalSince1970)"
    }

    private var previewContent: some View {
        Group {
            if FileManager.default.fileExists(atPath: app.screenshotHistoryFileURL(for: item).path) {
                ScreenshotHistoryThumbnail(
                    fileURL: app.screenshotHistoryFileURL(for: item),
                    cacheKey: thumbnailCacheKey,
                    cardWidth: cardWidth
                )
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.jarvisTextSecondary)
            }
        }
        .frame(
            width: cardWidth,
            height: HistoryGridLayout.cardHeight(forCardWidth: cardWidth),
            alignment: .center
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: HistoryGridMetrics.clipboardCornerRadius,
                style: .continuous
            )
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var previewArea: some View {
        if FileManager.default.fileExists(atPath: app.screenshotHistoryFileURL(for: item).path) {
            previewContent
                .onDrag {
                    guard let data = app.screenshotHistoryData(for: item) else {
                        return NSItemProvider()
                    }
                    return ScreenshotSharing.itemProvider(for: item, data: data)
                }
        } else {
            previewContent
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
        .frame(
            width: cardWidth,
            height: HistoryGridMetrics.clipboardMetadataHeight
        )
    }

    private var copyButton: some View {
        Button {
            app.copyScreenshotHistory(item)
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
            width: cardWidth,
            height: HistoryGridLayout.cardHeight(forCardWidth: cardWidth),
            isSelected: isSelected
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
            app.copyScreenshotHistory(item)
        }
        .contextMenu {
            Button {
                app.showScreenshotHistoryPreview(item)
            } label: {
                Label("查看", systemImage: "eye")
            }
            Button {
                app.editScreenshotHistory(item)
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button {
                app.copyScreenshotHistory(item)
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
                app.deleteScreenshotHistory(item)
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
    let cardWidth: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.jarvisTextSecondary)
            }
        }
        .frame(
            width: cardWidth,
            height: HistoryGridLayout.cardHeight(forCardWidth: cardWidth)
        )
        .clipped()
        .task(id: cacheKey) {
            image = await JarvisThumbnailCache.loadAsync(fileURL: fileURL, maxPixelSize: 640)
        }
    }
}
