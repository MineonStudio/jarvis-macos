import AppKit
import SwiftUI

struct ScreenshotView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenshotHistorySection()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, JarvisMetrics.pageInset)
            .padding(.vertical, JarvisMetrics.pageInset)
        }
    }
}

enum HistoryGridMetrics {
    static let pageSize = 12
    static let cardWidth: CGFloat = 220
    static let cardHeight: CGFloat = 294
    static let previewHeight: CGFloat = 200
    static let cardPadding: CGFloat = 10
    static let minimumCardWidth = cardWidth
    static let maximumCardWidth = cardWidth
    static let spacing: CGFloat = 12
}

struct ScreenshotHistorySection: View {
    @EnvironmentObject private var app: AppModel
    @State private var currentPage = 1

    private var totalPages: Int {
        max(1, (app.screenshotHistory.count + HistoryGridMetrics.pageSize - 1) / HistoryGridMetrics.pageSize)
    }

    private var pageItems: [ScreenshotHistoryItem] {
        let page = min(max(currentPage, 1), totalPages)
        let startIndex = (page - 1) * HistoryGridMetrics.pageSize
        return Array(app.screenshotHistory.dropFirst(startIndex).prefix(HistoryGridMetrics.pageSize))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if app.screenshotHistory.isEmpty {
                JarvisEmptyState(
                    icon: "photo.on.rectangle",
                    title: "还没有截图",
                    message: "框选截图后，历史记录会显示在这里"
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
                        ScreenshotHistoryCard(
                            item: item
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
        .onChange(of: app.screenshotHistory.count) { _, _ in
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
                .font(.system(size: 11, weight: .medium, design: .monospaced))
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
    let item: ScreenshotHistoryItem
    @State private var showingDeleteConfirmation = false

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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if FileManager.default.fileExists(atPath: app.screenshotHistoryFileURL(for: item).path) {
                    Button {
                        app.showScreenshotHistoryPreview(item)
                    } label: {
                        ScreenshotHistoryThumbnail(
                            fileURL: app.screenshotHistoryFileURL(for: item),
                            cacheKey: thumbnailCacheKey
                        )
                    }
                    .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.995, pressedOpacity: 0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .help("查看原图；拖到 Finder 或其他应用导出 PNG")
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
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
            }
            .frame(width: HistoryGridMetrics.cardWidth - (HistoryGridMetrics.cardPadding * 2))
            .frame(height: HistoryGridMetrics.previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .clipped()

            HStack(spacing: 7) {
                Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let fileSizeDescription {
                    Text(fileSizeDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .lineLimit(1)
                }
            }
            .frame(height: 18)

            HStack(spacing: 4) {
                Spacer(minLength: 0)
                Button {
                    app.editScreenshotHistory(item)
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.75))
                .help("二次编辑")
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.75))
                .foregroundStyle(.red.opacity(0.78))
                .help("删除")
            }
            .frame(height: 30)
        }
        .padding(HistoryGridMetrics.cardPadding)
        .frame(
            width: HistoryGridMetrics.cardWidth,
            height: HistoryGridMetrics.cardHeight,
            alignment: .topLeading
        )
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .jarvisHoverPanelFeedback(
            scale: 1.03
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
                    .scaledToFit()
                    .padding(HistoryGridMetrics.cardPadding)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.jarvisTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
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
