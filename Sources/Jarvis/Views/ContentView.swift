import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppModel
    @State private var navigationSelection: AppSection = .overview
    @State private var loadedSection: AppSection = .overview

    var body: some View {
        ZStack(alignment: .top) {
            Color.jarvisBackground

            VStack(spacing: 0) {
                // Preserve the original content position while allowing the
                // navbar to be composited above the body instead of behind it.
                Color.clear
                    .frame(height: 102)
                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .top) {
            ZStack {
                TopNavigationBar(selection: selectedSectionBinding)

                HStack {
                    Spacer()
                    Button {
                        navigationSelection = .settings
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .help("设置")
                }
                .padding(.horizontal, 28)
            }
            .frame(height: 70)
            // The window uses a full-size transparent title bar. Keep the
            // capsule below the native traffic lights instead of letting it
            // occupy the same top strip.
            .padding(.top, 32)
            .zIndex(1)
        }
        .tint(.accentColor)
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: app.selectedSection) { _, newSection in
            // Other entry points (quick actions, menu bar, screenshot flow)
            // still drive the app model. Reflect them in the navbar first;
            // the section task below will mount the page on the next turn.
            guard navigationSelection != newSection else { return }
            navigationSelection = newSection
        }
        .task(id: navigationSelection) {
            let nextSection = navigationSelection
            guard nextSection != loadedSection else {
                if app.selectedSection != nextSection {
                    app.selectedSection = nextSection
                }
                return
            }

            // Give SwiftUI one turn to commit the optimistic navbar state
            // before constructing the potentially heavier page hierarchy.
            await Task.yield()
            guard !Task.isCancelled, navigationSelection == nextSection else { return }
            loadedSection = nextSection
            app.selectedSection = nextSection
        }
    }

    private var selectedSectionBinding: Binding<AppSection?> {
        Binding(
            get: { navigationSelection },
            set: { newValue in
                guard let newValue else { return }
                // This is intentionally local and synchronous. The page
                // switch is deferred by the task above so the selected tab
                // responds before its destination is loaded.
                navigationSelection = newValue
            }
        )
    }

    @ViewBuilder
    private var detailView: some View {
        switch loadedSection {
        case .overview: DashboardView()
        case .skill(.screenshot): ScreenshotView()
        case .skill(.clipboard): ClipboardView()
        case .settings: SettingsView()
        }
    }
}

private struct TopNavigationBar: View {
    @Binding var selection: AppSection?

    private let sections: [AppSection] = [
        .overview,
        .skill(.screenshot),
        .skill(.clipboard)
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(sections) { section in
                Button {
                    selection = section
                } label: {
                    Text(section.navigationTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selection == section ? Color.white : Color.secondary)
                        .frame(minWidth: 64, minHeight: 34)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Capsule())
                        .background(
                            selection == section ? Color.accentColor.opacity(0.82) : .clear,
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
                .help(section.navigationTitle)
            }
        }
        .padding(3)
        .jarvisGlass(in: Capsule(), interactive: false)
        .shadow(color: Color.black.opacity(0.10), radius: 20, y: 9)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    SectionHeader(title: "你好，贾维斯", subtitle: "本地 macOS 工具人 · API 大脑可替换")
                    Spacer()
                    StatusPill(
                        text: app.hasAPIKey ? "API 已连接" : "未配置 API",
                        color: app.hasAPIKey ? .accentColor : .secondary,
                        usesTint: app.hasAPIKey
                    )
                }

                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("快捷操作")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(app.statusMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }

                    HStack(spacing: 10) {
                        QuickActionButton(title: "框选截图", subtitle: "翻译 / 识别", icon: "viewfinder", tint: .accentColor) {
                            // This is an in-window action, so it may move the
                            // main window to the screenshot tab explicitly.
                            app.selectedSection = .skill(.screenshot)
                            app.captureScreenshot()
                        }
                        QuickActionButton(title: "打开剪贴板", subtitle: "搜索历史内容", icon: "clipboard", tint: .accentColor) {
                            app.selectedSection = .skill(.clipboard)
                        }
                        QuickActionButton(title: "模型设置", subtitle: "接入 API 大脑", icon: "brain.head.profile", tint: .accentColor) {
                            app.selectedSection = .settings
                        }
                    }
                }

                Divider()
                    .overlay(Color.primary.opacity(0.10))

                HStack(spacing: 0) {
                    DashboardMetric(title: "截图", value: "\(app.screenshotHistory.count)", detail: "历史记录", icon: "photo")
                    dashboardDivider
                    DashboardMetric(title: "剪贴板", value: "\(app.clipboardItems.count)", detail: "本地记录", icon: "clipboard")
                    dashboardDivider
                    DashboardMetric(title: "技能", value: "\(SkillID.allCases.count)", detail: "已启用", icon: "puzzlepiece.extension")
                }

                Divider()
                    .overlay(Color.primary.opacity(0.10))

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28, height: 28)
                        .jarvisIconGlass(in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("本机优先")
                            .font(.system(size: 13, weight: .semibold))
                        Text("剪贴板历史保存在本机；截图文字先由 macOS 在本地识别，只有识别出的文字会在你主动翻译时发送给配置的 API 服务商。")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.jarvisTextSecondary)
                            .lineSpacing(2)
                    }
                    Spacer(minLength: 12)
                    Text("隐私")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(JarvisMetrics.pageInset)
        }
    }

    private var dashboardDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(width: 1, height: 44)
            .padding(.horizontal, 22)
    }
}

struct DashboardMetric: View {
    let title: String
    let value: String
    let detail: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .jarvisIconGlass(in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(value)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.jarvisTextSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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
                        Text("截图会保存在本机，可随时重新编辑或删除")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.jarvisTextSecondary)
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
                   let image = NSImage(data: data) {
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
            .jarvisGlass(cornerRadius: 10, interactive: false)
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

enum ClipboardViewFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case text
    case image
    case file
    case video

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .favorites: return "收藏"
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        case .video: return "视频"
        }
    }

    var icon: String? {
        switch self {
        case .all: return "square.grid.2x2"
        case .favorites: return "star.fill"
        case .text: return ClipboardKind.text.icon
        case .image: return ClipboardKind.image.icon
        case .file: return ClipboardKind.file.icon
        case .video: return ClipboardKind.video.icon
        }
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: return true
        case .favorites: return item.isPinned
        case .text: return item.kind == .text
        case .image: return item.kind == .image
        case .file: return item.kind == .file
        case .video: return item.kind == .video
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

struct ClipboardView: View {
    @EnvironmentObject private var app: AppModel
    @State private var searchText = ""
    @State private var selectedFilter: ClipboardViewFilter = .all
    @State private var currentPage = 1

    private var filteredItems: [ClipboardItem] {
        app.clipboardItems.filter { item in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return selectedFilter.matches(item)
                && (query.isEmpty || item.preview.localizedCaseInsensitiveContains(query))
        }
    }

    private func count(for filter: ClipboardViewFilter) -> Int {
        app.clipboardItems.filter { filter.matches($0) }.count
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
                VStack(alignment: .leading, spacing: 12) {
                    ClipboardSearchField(
                        text: $searchText,
                        placeholder: "搜索文本、文件名…",
                        focusesOnAppear: false
                    )

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(ClipboardViewFilter.allCases) { filter in
                                ClipboardFilterChip(
                                    filter: filter,
                                    count: count(for: filter),
                                    isSelected: selectedFilter == filter
                                ) {
                                    selectedFilter = filter
                                }
                            }
                        }
                    }
                }
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
                            ClipboardRow(item: item)
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

struct ClipboardRow: View {
    @EnvironmentObject private var app: AppModel
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                if item.kind == .image || item.kind == .video {
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
                    } else {
                        ClipboardItemPreview(item: item, size: 78)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: HistoryGridMetrics.previewHeight)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.kind == .image || item.kind == .video ? "查看大图" : "一键复制")

            HStack(spacing: 6) {
                Text(item.kind.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                if item.isPinned {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
                Text(item.shortTimestamp)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .lineLimit(1)
            }

            Text(item.preview)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(item.kind == .text ? 2 : 1)
                .textSelection(.enabled)
            ClipboardMetadata(item: item)

            HStack(spacing: 4) {
                Button {
                    app.copyClipboard(item)
                } label: {
                    Label("一键复制", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(JarvisSecondaryButtonStyle())
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.75)
        }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .contextMenu {
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

struct ClipboardMetadata: View {
    let item: ClipboardItem

    var body: some View {
        HStack(spacing: 6) {
            if let size = item.sizeDescription {
                Text(size)
            }
            if item.kind == .file || item.kind == .video {
                Text(item.hasLocalContent ? "本地副本" : "原文件引用")
            } else if item.kind == .image {
                Text(item.hasLocalContent ? "已保存到本机" : "文件不可用")
            } else {
                Text("本机记录")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(Color.jarvisTextSecondary)
    }
}

struct ClipboardItemPreview: View {
    private static let videoThumbnailCache = NSCache<NSString, NSImage>()

    let item: ClipboardItem
    let size: CGFloat
    @State private var videoThumbnail: NSImage?

    var body: some View {
        ZStack {
            if item.kind == .image,
               let path = item.imagePath,
               let image = NSImage(contentsOfFile: path) {
                mediaImage(image)
            } else if item.kind == .video,
                      let image = videoThumbnail {
                mediaImage(image)
                    .overlay(alignment: .bottomLeading) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.55), in: Circle())
                            .padding(7)
                    }
            } else {
                Image(systemName: item.kind.icon)
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
        .jarvisIconGlass(tint: .accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task(id: item.id) {
            guard item.kind == .video,
                  let videoPath = item.filePath else { return }

            let cacheKey = (item.thumbnailPath ?? videoPath) as NSString
            if let cached = Self.videoThumbnailCache.object(forKey: cacheKey) {
                videoThumbnail = cached
                return
            }

            if let thumbnailPath = item.thumbnailPath,
               let thumbnail = NSImage(contentsOfFile: thumbnailPath) {
                Self.videoThumbnailCache.setObject(thumbnail, forKey: cacheKey)
                videoThumbnail = thumbnail
                return
            }

            ClipboardVideoThumbnailGenerator.makeCGImageAsync(for: URL(fileURLWithPath: videoPath)) { image in
                guard let image else { return }
                let thumbnail = NSImage(
                    cgImage: image,
                    size: NSSize(width: image.width, height: image.height)
                )
                Self.videoThumbnailCache.setObject(thumbnail, forKey: cacheKey)
                videoThumbnail = thumbnail
            }
        }
    }

    private func mediaImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipped()
    }
}

struct ClipboardPanelView: View {
    @EnvironmentObject private var app: AppModel
    @State private var searchText = ""
    @State private var selectedFilter: ClipboardViewFilter = .all

    private var filteredItems: [ClipboardItem] {
        app.clipboardItems.filter { item in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return selectedFilter.matches(item)
                && (query.isEmpty || item.preview.localizedCaseInsensitiveContains(query))
        }
    }

    private func count(for filter: ClipboardViewFilter) -> Int {
        app.clipboardItems.filter { filter.matches($0) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ClipboardSearchField(
                text: $searchText,
                placeholder: "搜索文本或文件名…",
                focusesOnAppear: true
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(ClipboardViewFilter.allCases) { filter in
                        ClipboardFilterChip(
                            filter: filter,
                            count: count(for: filter),
                            isSelected: selectedFilter == filter
                        ) {
                            selectedFilter = filter
                        }
                    }
                }
            }
            .padding(.top, 2)

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
                            ClipboardPanelRow(
                                item: item,
                                preview: { app.showClipboardMediaPreview(item) },
                                copy: { app.copyClipboard(item) }
                            )
                        }
                    }
                }
            }

            HStack(spacing: 7) {
                Image(systemName: "info.circle")
                Text("手动点击一键复制")
                Spacer()
                Text("本机保存")
                    .foregroundStyle(Color.jarvisTextSecondary)
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

struct ClipboardPanelRow: View {
    let item: ClipboardItem
    let preview: () -> Void
    let copy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button(action: preview) {
                ZStack {
                    if item.kind == .text {
                        Text(item.preview)
                            .font(.system(size: 12))
                            .lineLimit(6)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(12)
                    } else {
                        ClipboardItemPreview(item: item, size: 78)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: HistoryGridMetrics.previewHeight)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(item.kind != .image && item.kind != .video)
            .help(item.kind == .image || item.kind == .video ? "查看大图" : "")

            HStack(spacing: 6) {
                Text(item.kind.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                if item.isPinned {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
                Text(item.shortTimestamp)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .lineLimit(1)
            }

            Text(item.preview)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(item.kind == .text ? 2 : 1)
            ClipboardMetadata(item: item)

            HStack(spacing: 4) {
                Button {
                    copy()
                } label: {
                    Label("一键复制", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(JarvisSecondaryButtonStyle())
                .disabled(!item.hasLocalContent)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.75)
        }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct ShortcutSettingsCard: View {
    @EnvironmentObject private var app: AppModel
    @State private var screenshotShortcut = ScreenshotShortcut.default
    @State private var clipboardShortcut = ScreenshotShortcut.clipboardDefault
    @State private var isRecordingScreenshotShortcut = false
    @State private var isRecordingClipboardShortcut = false

    var body: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 15) {
                Label("快捷键", systemImage: "keyboard")
                    .font(.system(size: 14, weight: .semibold))

                shortcutRow(
                    title: "截图",
                    subtitle: "框选屏幕或快速选中窗口",
                    shortcut: $screenshotShortcut,
                    isRecording: $isRecordingScreenshotShortcut,
                    conflictMessage: app.screenshotShortcutConflictMessage
                ) {
                    let previous = screenshotShortcut
                    if !app.updateScreenshotShortcut(.default) {
                        screenshotShortcut = previous
                    } else {
                        screenshotShortcut = .default
                    }
                }

                Divider().overlay(Color.primary.opacity(0.12))

                shortcutRow(
                    title: "剪贴板",
                    subtitle: "唤起独立剪贴板面板",
                    shortcut: $clipboardShortcut,
                    isRecording: $isRecordingClipboardShortcut,
                    conflictMessage: app.clipboardShortcutConflictMessage
                ) {
                    let previous = clipboardShortcut
                    if !app.updateClipboardShortcut(.clipboardDefault) {
                        clipboardShortcut = previous
                    } else {
                        clipboardShortcut = .clipboardDefault
                    }
                }
            }
        }
        .onAppear {
            screenshotShortcut = app.screenshotShortcut
            clipboardShortcut = app.clipboardShortcut
            _ = app.validateScreenshotShortcut(screenshotShortcut)
            _ = app.validateClipboardShortcut(clipboardShortcut)
        }
        .onChange(of: screenshotShortcut) { _, newValue in
            if app.validateScreenshotShortcut(newValue) {
                guard newValue != app.screenshotShortcut else { return }
                _ = app.updateScreenshotShortcut(newValue)
            }
        }
        .onChange(of: clipboardShortcut) { _, newValue in
            if app.validateClipboardShortcut(newValue) {
                guard newValue != app.clipboardShortcut else { return }
                _ = app.updateClipboardShortcut(newValue)
            }
        }
    }

    private func shortcutRow(
        title: String,
        subtitle: String,
        shortcut: Binding<ScreenshotShortcut>,
        isRecording: Binding<Bool>,
        conflictMessage: String,
        onRestore: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.jarvisTextSecondary)
            }
            Spacer(minLength: 8)
            ShortcutRecorderControl(
                shortcut: shortcut,
                isRecording: isRecording
            )
            .frame(width: 170, height: 32)
            if !conflictMessage.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help(conflictMessage)
            }
            Button("恢复默认", action: onRestore)
                .buttonStyle(JarvisSecondaryButtonStyle())
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var apiKey = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                versionAndUpdateCard

                themeSettingsCard

                screenshotTranslationSettingsCard

                JarvisCard {
                    VStack(alignment: .leading, spacing: 15) {
                        Label("模型 API", systemImage: "brain.head.profile")
                            .font(.system(size: 15, weight: .semibold))

                        LabeledSetting(title: "Provider") {
                            TextField("OpenAI Compatible", text: $app.modelConfiguration.providerName)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledSetting(title: "API Base URL") {
                            TextField("https://api.openai.com/v1", text: $app.modelConfiguration.baseURL)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledSetting(title: "模型名称") {
                            TextField("gpt-4o-mini", text: $app.modelConfiguration.modelName)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledSetting(title: "API Key") {
                            SecureField("sk-…", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text(app.apiKeyHint)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.jarvisTextSecondary)
                            Spacer()
                            Button("删除 Key") { app.clearAPIKey() }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red.opacity(0.8))
                                .disabled(!app.hasAPIKey)
                        }

                        Divider().overlay(Color.primary.opacity(0.12))

                        HStack(spacing: 10) {
                            Button("保存配置") {
                                app.saveModelSettings(apiKey: apiKey)
                                apiKey = ""
                            }
                            .buttonStyle(JarvisPrimaryButtonStyle())
                            Button("测试连接") {
                                app.testConnection(apiKeyOverride: apiKey)
                            }
                            .buttonStyle(JarvisSecondaryButtonStyle())
                            Text(app.connectionStatus)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.jarvisTextSecondary)
                        }
                    }
                }

                ShortcutSettingsCard()
            }
            .padding(JarvisMetrics.pageInset)
        }
        .onAppear {
            apiKey = ""
        }
    }

    private var themeSettingsCard: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 15) {
                Label("主题", systemImage: "circle.lefthalf.filled")
                    .font(.system(size: 15, weight: .semibold))

                LabeledSetting(title: "外观") {
                    Picker("外观", selection: Binding(
                        get: { app.themePreference },
                        set: { app.updateThemePreference($0) }
                    )) {
                        ForEach(JarvisTheme.allCases) { theme in
                            Label(theme.title, systemImage: theme.icon)
                                .tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Text("跟随系统会根据 macOS 当前的浅色或深色外观自动切换。")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.jarvisTextSecondary)
            }
        }
    }

    private var screenshotTranslationSettingsCard: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 15) {
                Label("截图翻译", systemImage: "character.bubble")
                    .font(.system(size: 15, weight: .semibold))

                LabeledSetting(title: "翻译为") {
                    Picker("翻译为", selection: Binding(
                        get: { app.targetLanguage },
                        set: { app.updateTranslationLanguage($0) }
                    )) {
                        ForEach(ScreenshotTranslationLanguage.allCases) { language in
                            Text(language.rawValue).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180, alignment: .leading)
                }

                Text("截图先由 macOS 在本地 OCR，只有识别出的文字会发送给模型服务商；原图和翻译结果不会自动保存到本地历史。")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var versionAndUpdateCard: some View {
        JarvisCard {
            HStack(spacing: 14) {
                Label("版本与更新", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("当前版本 \(JarvisAppVersion.displayName)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                    updateStatusLabel
                }
                switch app.updateState {
                case .available:
                    Button("下载并更新") {
                        app.downloadAndInstallUpdate()
                    }
                    .buttonStyle(JarvisPrimaryButtonStyle())
                case .downloading, .installing:
                    ProgressView()
                        .controlSize(.small)
                default:
                    EmptyView()
                }
                Button(app.updateState == .checking ? "检查中…" : "手动检查更新") {
                    app.checkForUpdates()
                }
                .buttonStyle(JarvisSecondaryButtonStyle())
                .disabled(app.updateState == .checking || isUpdating)
            }
        }
    }

    @ViewBuilder
    private var updateStatusLabel: some View {
        Group {
            switch app.updateState {
            case .idle:
                Text("尚未检查更新")
            case .checking:
                Text("正在检查更新…")
            case .upToDate:
                Text("已是最新版本")
            case .available(let release):
                Text("发现新版本 \(release.version)")
                    .foregroundStyle(Color.accentColor)
            case .downloading(let version):
                Text("正在下载 \(version)…")
            case .installing(let version):
                Text("正在安装 \(version)…")
            case .failed(let message):
                Text(message)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(Color.jarvisTextSecondary)
    }

    private var isUpdating: Bool {
        switch app.updateState {
        case .downloading, .installing: return true
        default: return false
        }
    }
}

struct FloatingTranslationView: View {
    @ObservedObject var model: TranslationOverlayModel
    let onClose: () -> Void
    let onRetry: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("贾维斯 · 截图翻译", systemImage: "character.bubble")
                    .font(.system(size: 13, weight: .semibold))
                Text("→ \\(model.targetLanguage)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.jarvisTextSecondary)
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.borderless)
            }
            Divider()
            if model.isTranslating {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在本地识别并翻译文字…")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else if !model.errorMessage.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("翻译失败", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(model.errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .textSelection(.enabled)
                    Button("重试", action: onRetry)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            } else {
                ScrollView {
                    Text(model.text)
                        .font(.system(size: 15))
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("重试", action: onRetry)
                        .buttonStyle(.borderless)
                    Spacer()
                    Button(copied ? "已复制" : "复制结果") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.text, forType: .string)
                        copied = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.jarvisCyan)
                }
            }
        }
        .padding(20)
        .jarvisGlass(cornerRadius: 18, interactive: false)
        .onChange(of: model.text) { _, _ in copied = false }
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        Button {
            app.captureScreenshot()
        } label: {
            Label("框选截图", systemImage: "viewfinder")
        }
        Button {
            NSApp.activate(ignoringOtherApps: true)
            app.selectedSection = .overview
        } label: {
            Label("打开贾维斯", systemImage: "rectangle.on.rectangle")
        }
        Button {
            app.showClipboardPanel()
        } label: {
            Label("打开剪贴板（\(app.clipboardShortcut.displayString)）", systemImage: "clipboard")
        }
        Divider()
        Text(app.statusMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
        Button {
            NSApp.terminate(nil)
        } label: {
            Label("退出贾维斯", systemImage: "power")
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .jarvisIconGlass(tint: tint, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Color.jarvisTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.jarvisTextSecondary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .jarvisGlass(cornerRadius: 13)
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let color: Color

    var body: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon).foregroundStyle(color)
                Text(value).font(.system(size: 26, weight: .bold, design: .rounded))
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(Color.jarvisTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StatusPill: View {
    let text: String
    let color: Color
    let usesTint: Bool

    private var label: some View {
        Label(text, systemImage: "circle.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
    }

    @ViewBuilder
    var body: some View {
        if usesTint {
            label.jarvisGlass(tint: color.opacity(0.18), in: Capsule(), interactive: false)
        } else {
            // Keep the unconfigured state neutral. A full secondary tint
            // makes the status badge look like a dark filled control.
            label.jarvisGlass(in: Capsule(), interactive: false)
        }
    }
}

struct LabeledSetting<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 100, alignment: .leading)
                .foregroundStyle(Color.jarvisTextSecondary)
            content
        }
    }
}
