import AppKit
import SwiftUI

struct ScreenshotView: View {
    @EnvironmentObject private var app: AppModel
    @State private var selectedTimeFilter: ScreenshotTimeFilter = .threeDays
    @State private var selectedItemID: UUID?

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                ScreenshotTimeFilterBar(selectedFilter: $selectedTimeFilter)
            },
            trailingToolbar: {
                ToolbarItem(id: "screenshot.actions", placement: .automatic) {
                    ScreenshotHistoryActionToolbar(
                        selectedItem: selectedItem,
                        onClearSelection: { selectedItemID = nil }
                    )
                }
            },
            content: {
                GeometryReader { proxy in
                    ScrollView {
                        ScreenshotHistorySection(
                            selectedTimeFilter: $selectedTimeFilter,
                            selectedItemID: $selectedItemID,
                            availableGridWidth: max(
                                0,
                                proxy.size.width - HistoryGridMetrics.historyPanelInset * 2
                            ),
                            availableGridHeight: max(0, proxy.size.height)
                        )
                        .padding(.horizontal, HistoryGridMetrics.historyPanelInset)
                        .padding(.vertical, HistoryGridMetrics.historyPanelInset)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .jarvisFloatingPanel(cornerRadius: 16)
                }
            }
        )
    }

    private var selectedItem: ScreenshotHistoryItem? {
        guard let selectedItemID else { return nil }
        return app.screenshotHistory.first { $0.id == selectedItemID }
    }
}

struct ScreenshotHistoryActionToolbar: View {
    @EnvironmentObject private var app: AppModel
    let selectedItem: ScreenshotHistoryItem?
    let onClearSelection: () -> Void
    @State private var showingDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 2) {
            actionButton(
                systemName: "eye",
                help: "查看",
                isEnabled: selectedItem != nil
            ) {
                guard let selectedItem else { return }
                app.showScreenshotHistoryPreview(selectedItem)
            }
            actionButton(
                systemName: "pencil",
                help: "编辑",
                isEnabled: selectedItem != nil
            ) {
                guard let selectedItem else { return }
                app.editScreenshotHistory(selectedItem)
            }
            actionButton(
                systemName: "doc.on.doc",
                help: "复制",
                isEnabled: selectedItem != nil
            ) {
                guard let selectedItem else { return }
                app.copyScreenshotHistory(selectedItem)
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
        .jarvisHoverFeedback(
            in: Circle(),
            scale: 1.06
        )
        .help(help)
    }
}

enum HistoryGridMetrics {
    static let imageSpacing: CGFloat = 7
    static let historyPanelInset: CGFloat = 10
    static let historyFilterToGridSpacing: CGFloat = 10

    // Both history galleries use the same 16:9 landscape panel and controls.
    static let historyCardBaseWidth: CGFloat = 192
    static let historyCardBasePadding: CGFloat = 10
    static let clipboardCardWidth: CGFloat = historyCardBaseWidth * 1.1
    static let clipboardCardHeight: CGFloat = clipboardCardWidth * 9 / 16
    static let clipboardCardPadding: CGFloat = historyCardBasePadding * 0.6
    static let clipboardPreviewHeight: CGFloat = clipboardCardHeight
    static let clipboardContentSpacing: CGFloat = 4
    static let clipboardMetadataHeight: CGFloat = 16
    static let clipboardSearchFieldWidth: CGFloat = 320
    static let clipboardActionButtonSize = JarvisToolbarMetrics.controlSize
    static let clipboardPreviewHoverScale: CGFloat = 1.08
    static let clipboardCornerRadius: CGFloat = 12
    static let clipboardGridSpacing: CGFloat = 10
    static let filterChipHeight = JarvisMetrics.segmentedItemHeight
    static let filterChipSpacing: CGFloat = 7
    static let filterChipHorizontalPadding: CGFloat = 10
    static let filterChipVerticalPadding: CGFloat = 8
    static let topControlHeight = JarvisToolbarMetrics.controlSize
    static let clipboardSearchFieldHeight: CGFloat = topControlHeight
    static let clipboardFilterToGridSpacing: CGFloat = 10
    static let paginationControlHeight: CGFloat = 34
    static let screenshotFilterBarHeight: CGFloat = topControlHeight
    static let screenshotGridVerticalInset: CGFloat = historyPanelInset * 2
    static let clipboardGridVerticalInset: CGFloat = historyPanelInset * 2

    static func clipboardGridWidth(for columnCount: Int) -> CGFloat {
        guard columnCount > 0 else { return 0 }
        let cardWidth = clipboardCardWidth * CGFloat(columnCount)
        let spacing = clipboardGridSpacing * CGFloat(max(0, columnCount - 1))
        return cardWidth + spacing
    }

    static func columnCount(for availableWidth: CGFloat) -> Int {
        guard availableWidth > 0 else { return 1 }
        let columnUnit = clipboardCardWidth + clipboardGridSpacing
        return max(1, Int(floor((availableWidth + clipboardGridSpacing) / columnUnit)))
    }

    static func rowCount(for availableHeight: CGFloat) -> Int {
        guard availableHeight > 0 else { return 1 }
        let rowUnit = clipboardCardHeight + clipboardGridSpacing
        return max(1, Int(floor((availableHeight + clipboardGridSpacing) / rowUnit)))
    }

    static func pageSize(
        for availableWidth: CGFloat,
        availableHeight: CGFloat,
        itemCount: Int,
        verticalInset: CGFloat
    ) -> Int {
        let columns = columnCount(for: availableWidth)
        let gridHeight = max(0, availableHeight - verticalInset)
        let rowsWithoutPagination = rowCount(for: gridHeight)
        let rowsWithPagination = rowCount(
            for: gridHeight - paginationControlHeight - imageSpacing
        )
        let rows = itemCount > columns * rowsWithoutPagination
            ? rowsWithPagination
            : rowsWithoutPagination
        return columns * rows
    }
}

struct ScreenshotHistorySection: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentPage = 1
    @Binding var selectedTimeFilter: ScreenshotTimeFilter
    @Binding var selectedItemID: UUID?
    let availableGridWidth: CGFloat
    let availableGridHeight: CGFloat

    private var filteredItems: [ScreenshotHistoryItem] {
        ScreenshotTimeFilterLogic.filteredItems(
            from: app.screenshotHistory,
            filter: selectedTimeFilter
        )
    }

    private var pageSize: Int {
        HistoryGridMetrics.pageSize(
            for: availableGridWidth,
            availableHeight: availableGridHeight,
            itemCount: filteredItems.count,
            verticalInset: HistoryGridMetrics.screenshotGridVerticalInset
        )
    }

    private var totalPages: Int {
        max(1, (filteredItems.count + pageSize - 1) / pageSize)
    }

    private var pageItems: [ScreenshotHistoryItem] {
        let page = min(max(currentPage, 1), totalPages)
        let startIndex = (page - 1) * pageSize
        return Array(filteredItems.dropFirst(startIndex).prefix(pageSize))
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
                        .adaptive(
                            minimum: HistoryGridMetrics.clipboardCardWidth,
                            maximum: HistoryGridMetrics.clipboardCardWidth
                        ),
                        spacing: HistoryGridMetrics.clipboardGridSpacing
                    )],
                    alignment: .leading,
                    spacing: HistoryGridMetrics.clipboardGridSpacing
                ) {
                    ForEach(pageItems) { item in
                        ScreenshotHistoryCard(
                            item: item,
                            isSelected: selectedItemID == item.id,
                            onSelect: { selectedItemID = item.id },
                            onDoubleClick: { app.showScreenshotHistoryPreview(item) }
                        )
                        .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(
                    JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
                    value: pageItems.map(\.id)
                )

                if totalPages > 1 {
                    PaginationControl(currentPage: min(currentPage, totalPages), totalPages: totalPages) {
                        currentPage = max(1, currentPage - 1)
                    } onNext: {
                        currentPage = min(totalPages, currentPage + 1)
                    }
                }
            }
        }
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: selectedTimeFilter
        )
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: currentPage
        )
        .onChange(of: pageSize) { _, _ in
            currentPage = min(currentPage, totalPages)
        }
        .onChange(of: selectedTimeFilter) { _, _ in
            currentPage = 1
        }
        .onChange(of: filteredItems.count) { _, _ in
            currentPage = min(currentPage, totalPages)
        }
    }
}

struct PaginationControl: View {
    let currentPage: Int
    let totalPages: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("第 \(currentPage) / \(totalPages) 页")
                .font(JarvisTypography.monospaced)
                .foregroundStyle(Color.jarvisTextSecondary)
            Spacer()
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.75))
            .disabled(currentPage <= 1)
            .help("上一页")
            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.75))
            .disabled(currentPage >= totalPages)
            .help("下一页")
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
}

struct ScreenshotHistoryCard: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: ScreenshotHistoryItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    @State private var isHovered = false

    private var fileSizeDescription: String? {
        guard let fileSize = app.screenshotHistoryFileSize(for: item) else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter.string(fromByteCount: fileSize)
    }

    private var thumbnailCacheKey: String {
        "\(item.id.uuidString)|\(item.updatedAt.timeIntervalSince1970)"
    }

    private var previewContent: some View {
        Group {
            if FileManager.default.fileExists(atPath: app.screenshotHistoryFileURL(for: item).path) {
                ScreenshotHistoryThumbnail(
                    fileURL: app.screenshotHistoryFileURL(for: item),
                    cacheKey: thumbnailCacheKey
                )
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.jarvisTextSecondary)
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
        .help("拖到 Finder 或其他应用导出 PNG")
    }

    @ViewBuilder
    private var previewArea: some View {
        if FileManager.default.fileExists(atPath: app.screenshotHistoryFileURL(for: item).path) {
            previewContent
                .onDrag {
                    guard let data = app.screenshotHistoryData(for: item) else {
                        return NSItemProvider()
                    }
                    return ScreenshotSharing.itemProvider(
                        data: data,
                        suggestedName: item.fileName
                    )
                }
        } else {
            previewContent
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 6) {
            Text(JarvisHistoryDateFormatting.string(from: item.updatedAt))
                .font(JarvisTypography.caption)
                .foregroundStyle(Color.jarvisTextSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let fileSizeDescription {
                Text(fileSizeDescription)
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
            alignment: .center
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
    }
}

struct ScreenshotHistoryThumbnail: View {
    let fileURL: URL
    let cacheKey: String
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
            width: HistoryGridMetrics.clipboardCardWidth,
            height: HistoryGridMetrics.clipboardCardHeight
        )
        .clipped()
        .task(id: cacheKey) {
            image = await JarvisThumbnailCache.loadAsync(fileURL: fileURL, maxPixelSize: 640)
        }
    }
}
