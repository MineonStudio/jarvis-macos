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
        .skill(.clipboard),
        .settings
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
                        Text("剪贴板历史保存在本机；截图只有在你主动翻译时才会发送给配置的 API 服务商。")
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

struct ScreenshotHistorySection: View {
    @EnvironmentObject private var app: AppModel
    @State private var currentPage = 1

    private let pageSize = 12

    private var totalPages: Int {
        max(1, (app.screenshotHistory.count + pageSize - 1) / pageSize)
    }

    private var pageItems: [ScreenshotHistoryItem] {
        let page = min(max(currentPage, 1), totalPages)
        let startIndex = (page - 1) * pageSize
        return Array(app.screenshotHistory.dropFirst(startIndex).prefix(pageSize))
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
                        columns: [GridItem(.adaptive(minimum: 180, maximum: 280), spacing: 12)],
                        spacing: 12
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

struct ClipboardView: View {
    @EnvironmentObject private var app: AppModel
    @State private var searchText = ""
    @State private var selectedFilter: ClipboardViewFilter = .all
    @State private var currentPage = 1

    private let pageSize = 20

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
        max(1, (filteredItems.count + pageSize - 1) / pageSize)
    }

    private var pageItems: [ClipboardItem] {
        let page = min(max(currentPage, 1), totalPages)
        let startIndex = (page - 1) * pageSize
        return Array(filteredItems.dropFirst(startIndex).prefix(pageSize))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Color.jarvisTextSecondary)
                        TextField("搜索文本、文件名…", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Color.jarvisTextSecondary)
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .jarvisGlass(cornerRadius: JarvisMetrics.controlRadius, interactive: false)

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
                    LazyVStack(spacing: 9) {
                        ForEach(pageItems) { item in
                            ClipboardRow(item: item)
                        }
                    }
                    .padding(.vertical, 2)

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

struct ClipboardShortcutSettingsCard: View {
    @EnvironmentObject private var app: AppModel
    @State private var clipboardShortcut = ScreenshotShortcut.clipboardDefault
    @State private var isRecordingShortcut = false

    var body: some View {
        JarvisCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("剪贴板快捷键", systemImage: "keyboard")
                        .font(.system(size: 14, weight: .semibold))
                    Text("唤起独立剪贴板面板")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
                Spacer()
                ShortcutRecorderControl(
                    shortcut: $clipboardShortcut,
                    isRecording: $isRecordingShortcut
                )
                .frame(width: 170, height: 32)
                if !app.clipboardShortcutConflictMessage.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .help(app.clipboardShortcutConflictMessage)
                }
                Button("恢复默认") {
                    let previous = clipboardShortcut
                    if !app.updateClipboardShortcut(.clipboardDefault) {
                        clipboardShortcut = previous
                    } else {
                        clipboardShortcut = .clipboardDefault
                    }
                }
                .buttonStyle(JarvisSecondaryButtonStyle())
            }
        }
        .onAppear {
            clipboardShortcut = app.clipboardShortcut
            _ = app.validateClipboardShortcut(clipboardShortcut)
        }
        .onChange(of: clipboardShortcut) { _, newValue in
            if app.validateClipboardShortcut(newValue) {
                guard newValue != app.clipboardShortcut else { return }
                _ = app.updateClipboardShortcut(newValue)
            }
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
            .padding(.vertical, 6)
            .jarvisGlass(tint: isSelected ? .accentColor : nil, in: Capsule(), interactive: false)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }
}

struct ClipboardKeyCap: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .jarvisGlass(cornerRadius: 5, interactive: false)
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
        HStack(alignment: .center, spacing: 13) {
            HStack(alignment: .center, spacing: 13) {
                    ClipboardItemPreview(item: item, size: 46)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(item.kind.title)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                            if item.isPinned {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.orange)
                            }
                            Text(item.shortTimestamp)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.jarvisTextSecondary)
                        }
                        Text(item.preview)
                            .font(.system(size: 13, weight: .regular))
                            .lineLimit(item.kind == .text ? 2 : 1)
                            .textSelection(.enabled)
                        ClipboardMetadata(item: item)
                    }
                    Spacer(minLength: 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    app.restoreClipboard(item)
                }

            Button {
                app.restoreClipboard(item)
            } label: {
                Label("放回", systemImage: "arrow.down.doc")
            }
            .buttonStyle(JarvisSecondaryButtonStyle())
            .help("放回剪贴板")
            Button {
                app.toggleClipboardPin(item)
            } label: {
                Image(systemName: item.isPinned ? "star.slash" : "star")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(item.isPinned ? .yellow : Color.jarvisTextSecondary)
            .help(item.isPinned ? "取消收藏" : "收藏")
            Button {
                app.deleteClipboardItem(item)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red.opacity(0.72))
            .help("删除")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .jarvisGlass(cornerRadius: 12, interactive: false)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            Button(item.isPinned ? "取消收藏" : "收藏") { app.toggleClipboardPin(item) }
            Button("放回剪贴板") { app.restoreClipboard(item) }
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
    let item: ClipboardItem
    let size: CGFloat

    var body: some View {
        ZStack {
            if item.kind == .image,
               let path = item.imagePath,
               let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                Image(systemName: item.kind.icon)
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: size, height: size)
        .jarvisIconGlass(tint: .accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ClipboardPanelView: View {
    @EnvironmentObject private var app: AppModel
    @State private var searchText = ""
    @State private var selectedFilter: ClipboardViewFilter = .all
    @State private var selectedID: UUID?
    @FocusState private var searchFocused: Bool

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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "clipboard.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                    .jarvisIconGlass(tint: .accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("剪贴板")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("选择内容后按回车，或使用 ⌘1–9 快速粘贴")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
                Spacer()
                Button { app.closeClipboardPanel() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("关闭面板")
            }

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.jarvisTextSecondary)
                TextField("搜索文本或文件名…", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.jarvisTextSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .jarvisGlass(cornerRadius: JarvisMetrics.controlRadius, interactive: false)

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

            Divider().overlay(Color.primary.opacity(0.10))

            if filteredItems.isEmpty {
                ClipboardEmptyState(
                    hasQuery: !searchText.isEmpty || selectedFilter != .all
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            ClipboardPanelRow(
                                item: item,
                                rank: index < 9 ? index + 1 : nil,
                                isSelected: selectedID == item.id,
                                select: {
                                    selectedID = item.id
                                    app.clipboardPanelSelectionID = item.id
                                },
                                paste: { app.quickPasteClipboard(item) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack(spacing: 7) {
                Image(systemName: "info.circle")
                Text("回车粘贴到上一个应用")
                Text("·")
                Text("⌘1–9 选择最近记录")
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
            selectedID = filteredItems.first?.id
            app.clipboardPanelSelectionID = selectedID
            searchFocused = true
        }
        .onChange(of: filteredItems.map(\.id)) { _, newIDs in
            if let selectedID, newIDs.contains(selectedID) { return }
            selectedID = newIDs.first
            app.clipboardPanelSelectionID = selectedID
        }
    }
}

struct ClipboardPanelRow: View {
    let item: ClipboardItem
    let rank: Int?
    let isSelected: Bool
    let select: () -> Void
    let paste: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            ClipboardItemPreview(item: item, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.kind.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    if item.isPinned {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    Text(item.shortTimestamp)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
                Text(item.preview)
                    .font(.system(size: 12))
                    .lineLimit(item.kind == .text ? 2 : 1)
                ClipboardMetadata(item: item)
            }
            Spacer(minLength: 8)
            if let rank {
                ClipboardKeyCap(title: "⌘\(rank)")
            }
            if let rank {
                Button("粘贴", action: paste)
                    .buttonStyle(JarvisSecondaryButtonStyle())
                    .keyboardShortcut(KeyEquivalent(Character("\(rank)")), modifiers: .command)
                    .disabled(!item.hasLocalContent)
            } else {
                Button("粘贴", action: paste)
                    .buttonStyle(JarvisSecondaryButtonStyle())
                    .disabled(!item.hasLocalContent)
            }
        }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .jarvisGlass(tint: isSelected ? .accentColor : nil, cornerRadius: 11, interactive: false)
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onTapGesture(perform: select)
    }
}

struct ScreenshotSkillSettingsCard: View {
    @EnvironmentObject private var app: AppModel
    @State private var screenshotShortcut = ScreenshotShortcut.default
    @State private var isRecordingShortcut = false

    var body: some View {
        JarvisCard {
            HStack(spacing: 14) {
                Label("截图快捷键", systemImage: "keyboard")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                ShortcutRecorderControl(
                    shortcut: $screenshotShortcut,
                    isRecording: $isRecordingShortcut
                )
                .frame(width: 170, height: 32)
                if !app.screenshotShortcutConflictMessage.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .help(app.screenshotShortcutConflictMessage)
                }
                Button("恢复默认") {
                    let previous = screenshotShortcut
                    if !app.updateScreenshotShortcut(.default) {
                        screenshotShortcut = previous
                    } else {
                        screenshotShortcut = .default
                    }
                }
                .buttonStyle(JarvisSecondaryButtonStyle())
            }
        }
        .onAppear {
            screenshotShortcut = app.screenshotShortcut
            _ = app.validateScreenshotShortcut(screenshotShortcut)
        }
        .onChange(of: screenshotShortcut) { _, newValue in
            if app.validateScreenshotShortcut(newValue) {
                guard newValue != app.screenshotShortcut else { return }
                _ = app.updateScreenshotShortcut(newValue)
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var apiKey = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(title: "设置", subtitle: "给贾维斯接入一个可替换的大脑")

                versionAndUpdateCard

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

                SectionHeader(title: "快捷键", subtitle: "自定义截图与剪贴板快捷键")

                ScreenshotSkillSettingsCard()
                ClipboardShortcutSettingsCard()
            }
            .padding(JarvisMetrics.pageInset)
        }
        .onAppear {
            apiKey = ""
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
                if case .available = app.updateState {
                    Button("打开更新") {
                        app.openLatestRelease()
                    }
                    .buttonStyle(JarvisPrimaryButtonStyle())
                }
                Button(app.updateState == .checking ? "检查中…" : "手动检查更新") {
                    app.checkForUpdates()
                }
                .buttonStyle(JarvisSecondaryButtonStyle())
                .disabled(app.updateState == .checking)
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
            case .available(let version, _):
                Text("发现新版本 \(version)")
                    .foregroundStyle(Color.accentColor)
            case .failed:
                Text("检查失败，请稍后重试")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(Color.jarvisTextSecondary)
    }
}

struct FloatingTranslationView: View {
    let text: String
    let onClose: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("贾维斯 · 翻译结果", systemImage: "character.bubble")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.borderless)
            }
            Divider()
            ScrollView {
                Text(text)
                    .font(.system(size: 15))
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button(copied ? "已复制" : "复制结果") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.jarvisCyan)
            }
        }
        .padding(20)
        .jarvisGlass(cornerRadius: 18, interactive: false)
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
