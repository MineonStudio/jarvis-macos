import AppKit
import SwiftUI

struct ScreenshotView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenshotHistorySection()
            }
            .padding(JarvisMetrics.pageInset)
        }
    }
}

enum HistoryGridMetrics {
    static let pageSize = 12
    static let minimumCardWidth: CGFloat = 180
    static let maximumCardWidth: CGFloat = 280
    static let previewHeight: CGFloat = 132
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
        JarvisCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("截图历史", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Spacer()
                    Text("\(app.screenshotHistory.count) 张")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.jarvisTextSecondary)
                }

                if app.screenshotHistory.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Color.jarvisTextSecondary)
                        Text("完成一张截图后会显示在这里")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
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
                            ScreenshotHistoryCard(item: item)
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
            .buttonStyle(.borderless)
            .disabled(currentPage <= 1)
            .help("上一页")
            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack {
                if let data = app.screenshotHistoryData(for: item),
                   let image = NSImage(data: data)
                {
                    Button {
                        app.showScreenshotHistoryPreview(item)
                    } label: {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .help("查看原图")
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 132)
            .clipped()

            HStack(spacing: 7) {
                Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    app.editScreenshotHistory(item)
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("二次编辑")
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red.opacity(0.78))
                .help("删除")
            }
        }
        .padding(10)
        .jarvisGlass(cornerRadius: 13, interactive: false)
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
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

struct ScreenshotHistoryPreview: View {
    let image: NSImage
    let imageDisplaySize: CGSize
    let imageViewportSize: CGSize
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
    static let preferredWidth: CGFloat = 420
    static let preferredHeight: CGFloat = 70

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
            .buttonStyle(.plain)
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
        .buttonStyle(.plain)
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
