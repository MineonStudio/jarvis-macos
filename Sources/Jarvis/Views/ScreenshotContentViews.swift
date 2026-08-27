import AppKit
import SwiftUI

struct ScreenshotView: View {
    @State private var availableGridWidth: CGFloat = 0
    @State private var availableGridHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ScreenshotHistorySection(
                        availableGridWidth: availableGridWidth,
                        availableGridHeight: availableGridHeight
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, HistoryGridMetrics.historyPanelInset)
                .padding(.vertical, HistoryGridMetrics.historyPanelInset)
            }
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
}

enum HistoryGridMetrics {
    static let imageSpacing: CGFloat = 7
    static let historyPanelInset: CGFloat = 24
    static let historyFilterToGridSpacing: CGFloat = 14

    // Both history galleries use the same 16:9 landscape panel and controls.
    static let historyCardBaseWidth: CGFloat = 192
    static let historyCardBasePadding: CGFloat = 10
    static let clipboardCardWidth: CGFloat = historyCardBaseWidth * 1.1
    static let clipboardCardHeight: CGFloat = clipboardCardWidth * 9 / 16
    static let clipboardCardPadding: CGFloat = historyCardBasePadding * 0.6
    static let clipboardPreviewHeight: CGFloat = clipboardCardHeight
    static let clipboardSearchFieldHeight: CGFloat = 44
    static let clipboardContentSpacing: CGFloat = 4
    static let clipboardMetadataHeight: CGFloat = 16
    static let clipboardSearchFieldWidth: CGFloat = 320
    static let clipboardActionButtonSize: CGFloat = 32
    static let clipboardPreviewHoverScale: CGFloat = 1.08
    static let clipboardCornerRadius: CGFloat = 12
    static let clipboardGridSpacing: CGFloat = 14
    static let filterChipHeight: CGFloat = 36
    static let filterChipSpacing: CGFloat = 7
    static let filterChipHorizontalPadding: CGFloat = 10
    static let filterChipVerticalPadding: CGFloat = 8
    static let clipboardFilterToGridSpacing: CGFloat =
        historyFilterToGridSpacing - (clipboardSearchFieldHeight - filterChipHeight)
    static let paginationControlHeight: CGFloat = 34
    static let screenshotFilterBarHeight: CGFloat = filterChipHeight
    static let screenshotGridVerticalInset: CGFloat =
        historyPanelInset * 2 + screenshotFilterBarHeight + historyFilterToGridSpacing
    static let clipboardGridVerticalInset: CGFloat =
        historyPanelInset * 2 + JarvisWindowLayoutMetrics.clipboardCompactFilterBarHeight
            + historyFilterToGridSpacing

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
    @State private var currentPage = 1
    @State private var selectedTimeFilter: ScreenshotTimeFilter = .all
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
            ScreenshotTimeFilterBar(
                selectedFilter: $selectedTimeFilter,
                items: app.screenshotHistory
            )

            if filteredItems.isEmpty {
                JarvisEmptyState(
                    icon: "photo.on.rectangle",
                    title: app.screenshotHistory.isEmpty ? "还没有截图" : "该时间范围暂无截图",
                    message: app.screenshotHistory.isEmpty
                        ? "框选截图后，历史记录会显示在这里"
                        : "切换其他时间范围查看截图"
                )
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
                            item: item
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if totalPages > 1 {
                    PaginationControl(currentPage: min(currentPage, totalPages), totalPages: totalPages) {
                        currentPage = max(1, currentPage - 1)
                    } onNext: {
                        currentPage = min(totalPages, currentPage + 1)
                    }
                }
            }
        }
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
    @State private var showingDeleteConfirmation = false
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

    private var actionOverlay: some View {
        HStack(spacing: 5) {
            screenshotActionButton(
                systemName: "eye",
                help: "查看大图",
                action: { app.showScreenshotHistoryPreview(item) }
            )
            screenshotActionButton(
                systemName: "doc.on.doc",
                help: "复制",
                action: { app.copyScreenshotHistory(item) }
            )
            screenshotActionButton(
                systemName: "pencil",
                help: "二次编辑",
                action: { app.editScreenshotHistory(item) }
            )
            screenshotActionButton(
                systemName: "trash",
                help: "删除",
                tint: .red.opacity(0.72),
                action: { showingDeleteConfirmation = true }
            )
        }
        .font(.system(size: 14, weight: .semibold))
        .opacity(isHovered ? 1 : 0)
        .allowsHitTesting(isHovered)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private func screenshotActionButton(
        systemName: String,
        help: String,
        tint: Color = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(
                    width: HistoryGridMetrics.clipboardActionButtonSize,
                    height: HistoryGridMetrics.clipboardActionButtonSize
                )
                .contentShape(Circle())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.90, pressedOpacity: 0.76))
        .foregroundStyle(tint)
        .font(.system(size: 13, weight: .medium))
        .jarvisGlass(in: Circle(), interactive: true)
        .jarvisHoverFeedback(in: Circle(), scale: 1.06)
        .help(help)
    }

    private var cardBody: some View {
        ZStack(alignment: .bottom) {
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
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
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
        .confirmationDialog(
            "删除这张截图？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                app.deleteScreenshotHistory(item)
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

struct ScreenshotHistoryPreview: View {
    let data: Data
    let image: NSImage
    let imageDisplaySize: CGSize
    let imageViewportSize: CGSize
    @ObservedObject var app: AppModel
    @ObservedObject var model: ScreenshotHistoryPreviewModel
    let onClose: () -> Void
    let onEdit: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void
    @State private var gestureZoomStart: CGFloat?
    @State private var gestureOffsetStart: CGSize?
    @State private var toolbarOffset: CGSize = .zero
    @State private var toolbarDragStartOffset: CGSize?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image(nsImage: image)
                    .interpolation(.high)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageDisplaySize.width, height: imageDisplaySize.height)
                    .scaleEffect(model.zoom)
                    .offset(model.offset)
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .simultaneousGesture(magnificationGesture)
                    .onTapGesture(count: 2) {
                        setZoom(model.zoom > 1 ? 1 : 2)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .clipped()
            .overlay(alignment: .bottom) {
                ScreenshotHistoryPreviewToolbar(
                    data: data,
                    onEdit: onEdit,
                    onCopy: onCopy,
                    onSave: onSave,
                    onDelete: onDelete,
                    onClose: onClose,
                    model: model
                )
                .padding(.bottom, 18)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .highPriorityGesture(toolbarDragGesture(in: geometry.size))
                .offset(toolbarOffset)
            }
            .coordinateSpace(name: "screenshotPreview")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .overlay(alignment: .top) {
            JarvisToastHost(message: app.toastMessage)
                .padding(.top, 18)
        }
        .onExitCommand(perform: onClose)
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if gestureZoomStart == nil {
                    gestureZoomStart = model.zoom
                }
                model.setZoom((gestureZoomStart ?? model.zoom) * value)
            }
            .onEnded { _ in
                gestureZoomStart = nil
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard model.zoom > 1 else { return }
                if gestureOffsetStart == nil {
                    gestureOffsetStart = model.offset
                }
                model.offset = CGSize(
                    width: (gestureOffsetStart ?? model.offset).width + value.translation.width,
                    height: (gestureOffsetStart ?? model.offset).height + value.translation.height
                )
            }
            .onEnded { _ in
                gestureOffsetStart = nil
            }
    }

    private func setZoom(_ value: CGFloat) {
        model.setZoom(value)
    }

    private func toolbarDragGesture(in containerSize: CGSize) -> some Gesture {
        DragGesture(
            minimumDistance: 6,
            coordinateSpace: .named("screenshotPreview")
        )
        .onChanged { value in
            if toolbarDragStartOffset == nil {
                toolbarDragStartOffset = toolbarOffset
            }
            let start = toolbarDragStartOffset ?? .zero
            toolbarOffset = clampedToolbarOffset(
                CGSize(
                    width: start.width + value.translation.width,
                    height: start.height + value.translation.height
                ),
                in: containerSize
            )
        }
        .onEnded { _ in
            toolbarDragStartOffset = nil
        }
    }

    private func clampedToolbarOffset(_ offset: CGSize, in containerSize: CGSize) -> CGSize {
        let toolbarWidth = ScreenshotHistoryPreviewToolbar.preferredWidth
        let toolbarHeight = ScreenshotHistoryPreviewToolbar.preferredHeight
        let horizontalLimit = max(0, (containerSize.width - toolbarWidth) / 2)
        let baseTop = max(0, containerSize.height - 18 - toolbarHeight)
        return CGSize(
            width: min(max(offset.width, -horizontalLimit), horizontalLimit),
            height: min(max(offset.height, -baseTop), 18)
        )
    }
}

struct ScreenshotHistoryPreviewToolbar: View {
    static let preferredWidth: CGFloat = 462
    static let preferredHeight: CGFloat = 70

    let data: Data
    let onEdit: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void
    @ObservedObject var model: ScreenshotHistoryPreviewModel
    @State private var showingDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            actionButton(icon: "pencil", help: "二次编辑", action: onEdit)
            toolbarDivider
            actionButton(icon: "minus.magnifyingglass", help: "缩小", enabled: model.zoom > 0.25) {
                model.setZoom(model.zoom - 0.25)
            }
            Button {
                model.setZoom(1)
            } label: {
                Text("\(Int(model.zoom * 100))%")
                    .font(JarvisTypography.monospaced)
                    .foregroundStyle(Color.secondary)
                    .frame(minWidth: 42, minHeight: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.84))
            .help("重置缩放")
            actionButton(icon: "plus.magnifyingglass", help: "放大", enabled: model.zoom < 4) {
                model.setZoom(model.zoom + 0.25)
            }
            toolbarDivider
            actionButton(icon: "doc.on.doc", help: "复制到剪贴板", action: onCopy)
            actionButton(icon: "square.and.arrow.down", help: "保存", action: onSave)
            toolbarDivider
            actionButton(icon: "trash", help: "删除", destructive: true, action: onDelete)
            actionButton(icon: "xmark", help: "关闭", action: onClose)
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 6)
        .frame(width: Self.preferredWidth, height: Self.preferredHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .jarvisGlass(cornerRadius: 16)
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 8)
        .confirmationDialog(
            "删除这张截图？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                onDelete()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复。")
        }
    }

    private func actionButton(
        icon: String,
        help: String,
        destructive: Bool = false,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(
                    enabled
                        ? (destructive ? Color.red.opacity(0.82) : Color.secondary)
                        : Color.secondary.opacity(0.35)
                )
                .frame(width: 24, height: 24)
                .frame(width: 42, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.76))
        .disabled(!enabled)
        .help(help)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.22))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 8)
    }
}
