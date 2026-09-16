import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ResumeContentView: View {
    @Environment(AppModel.self) private var app
    @EnvironmentObject private var workspace: ResumeWorkspace

    @State private var expandedSection: ResumeSection? = .basicInfo
    @State private var selectedProjectID: UUID?
    @State private var selectedBulletIndex = 0
    @State private var selectedTemplateCategory: ResumeTemplateCategory = .all
    @State private var previewScale: CGFloat = 1.0
    @State private var previewScaleInput = "100"
    @State private var isNewResumeConfirmationPresented = false
    @FocusState private var isFilenameFocused: Bool
    @FocusState private var isPreviewScaleInputFocused: Bool

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                if workspace.needsTemplateSelection {
                    ResumeTemplateCategorySelector(selection: $selectedTemplateCategory)
                } else {
                    resumeLeadingToolbar
                }
            },
            trailingToolbar: {
                if workspace.needsTemplateSelection {
                    ToolbarItem(placement: .automatic) {
                        EmptyView()
                    }
                } else {
                    resumeTrailingToolbar
                }
            },
            content: {
                Group {
                    if workspace.needsTemplateSelection {
                        ResumeTemplateSelectionView(category: selectedTemplateCategory) { template in
                            workspace.chooseTemplate(template)
                            expandedSection = .basicInfo
                        }
                    } else {
                        resumeEditorLayout
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.jarvisBackground)
            }
        )
        .onChange(of: workspace.document) { _, _ in
            normalizeSelection()
        }
        .onChange(of: isFilenameFocused) { _, isFocused in
            guard !isFocused else { return }
            normalizeFilename()
        }
        .onChange(of: expandedSection) { _, _ in
            DispatchQueue.main.async {
                finishFilenameEditing()
            }
        }
        .onChange(of: isPreviewScaleInputFocused) { _, isFocused in
            if !isFocused {
                commitPreviewScaleInput()
            }
        }
        .confirmationDialog(
            "当前简历尚未保存",
            isPresented: $isNewResumeConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("保存为 PDF 并新建") {
                saveResumeAndBeginNew()
            }
            Button("不保存，直接新建", role: .destructive) {
                beginNewResume()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("直接新建会丢弃当前未保存内容。")
        }
    }
}

struct ResumeTemplateCategorySelector: ToolbarContent {
    @Binding var selection: ResumeTemplateCategory

    var body: some ToolbarContent {
        ToolbarItem(id: "resume.category.all", placement: .navigation) {
            selectionButton(for: .all)
        }
        ToolbarItem(id: "resume.category.modern", placement: .navigation) {
            selectionButton(for: .modern)
        }
        ToolbarItem(id: "resume.category.creative", placement: .navigation) {
            selectionButton(for: .creative)
        }
        ToolbarItem(id: "resume.category.classic", placement: .navigation) {
            selectionButton(for: .classic)
        }
        ToolbarItem(id: "resume.category.professional", placement: .navigation) {
            selectionButton(for: .professional)
        }
    }

    private func selectionButton(for category: ResumeTemplateCategory) -> some View {
        JarvisToolbarSelectionButton(
            title: category.title,
            isSelected: selection == category
        ) {
            selection = category
        }
    }
}

struct ResumeAddButtonStyle: ButtonStyle {
    let tint: Color?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(tint: Color? = nil) {
        self.tint = tint
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(JarvisTypography.control)
            .foregroundStyle(tint ?? Color.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .contentShape(Capsule())
            .shadow(
                color: (tint ?? Color.primary).opacity(configuration.isPressed ? 0.18 : 0.08),
                radius: 4,
                y: 1
            )
            .opacity(configuration.isPressed ? 0.68 : 1)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.985)
            .animation(
                JarvisMotion.animation(JarvisMotion.buttonPress, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

enum ResumeZoomScale {
    static let minimumPercentage = 25
    static let maximumPercentage = 200

    static func clampedPercentage(_ percentage: Int) -> Int {
        min(max(percentage, minimumPercentage), maximumPercentage)
    }

    static func percentage(from input: String, fallback: Int) -> Int {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let percentage = Int(trimmedInput) else {
            return clampedPercentage(fallback)
        }
        return clampedPercentage(percentage)
    }
}

private struct ResumeZoomButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(
                JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion)
            ) {
                action()
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.92, pressedOpacity: 0.75))
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}

private extension ResumeContentView {
    var resumeEditorLayout: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                resumeEditorHeader

                ResumeInspector(
                    draft: $workspace.document,
                    expandedSection: $expandedSection,
                    onBackgroundTap: {
                        guard isFilenameFocused else { return }
                        finishFilenameEditing()
                    }
                )
            }
            .frame(width: 348)
            .frame(maxHeight: .infinity)

            documentCanvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .jarvisFloatingPanel(cornerRadius: 16)
    }

    @ToolbarContentBuilder
    var resumeLeadingToolbar: some ToolbarContent {
        ToolbarItem(id: "resume.new", placement: .automatic) {
            Button {
                requestNewResume()
            } label: {
                Text("新建简历")
            }
            .buttonStyle(JarvisToolbarButtonStyle.menu())
            .help("直接打开一份全新的空白简历")
        }
        ToolbarSpacer(.fixed, placement: .automatic)

        JarvisToolbarSurface(id: "resume.document-size", placement: .automatic) {
            resumeDocumentSizeToolbar
        }
    }

    @ToolbarContentBuilder
    var resumeTrailingToolbar: some ToolbarContent {
        ToolbarItem(id: "resume.zoom", placement: .automatic) {
            resumeZoomToolbar
        }
        ToolbarSpacer(.fixed, placement: .automatic)

        ToolbarItem(id: "resume.import", placement: .automatic) {
            Button {
                finishFilenameEditing()
                importJSON()
            } label: {
                Text("导入简历")
            }
            .buttonStyle(JarvisToolbarButtonStyle.menu())
            .help("打开一份 JSON 简历作为当前文档")
        }
        ToolbarSpacer(.fixed, placement: .automatic)

        ToolbarItem(id: "resume.export", placement: .automatic) {
            JarvisDropdownMenu(
                title: "导出简历",
                options: ResumeExportFormat.allCases.map {
                    JarvisDropdownOption(id: $0.rawValue, title: "导出为 \($0.title)")
                },
                accessibilityLabel: "导出简历",
                help: "选择 PDF、Markdown 或 JSON",
                showsChevron: false,
                usesLiquidGlass: false,
                onSelect: { rawValue in
                    guard let format = ResumeExportFormat(rawValue: rawValue) else { return }
                    finishFilenameEditing()
                    export(format)
                }
            )
        }
    }

    var resumeDocumentSizeToolbar: some View {
        Text("A4  210 × 297 mm")
            .font(JarvisTypography.caption)
            .foregroundStyle(Color.jarvisTextSecondary)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("文稿大小 A4，210 × 297 毫米")
            .help("文稿大小：A4（210 × 297 毫米）")
    }

    var resumeZoomToolbar: some View {
        HStack(spacing: 0) {
            ResumeZoomButton(systemName: "minus", accessibilityLabel: "缩小预览") {
                adjustPreviewScale(by: -1)
            }

            Divider()
                .frame(height: 16)
                .opacity(0.35)

            HStack(spacing: 1) {
                TextField("100", text: $previewScaleInput)
                    .textFieldStyle(.plain)
                    .font(JarvisTypography.monospaced)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 42, height: JarvisToolbarMetrics.controlSize)
                    .focused($isPreviewScaleInputFocused)
                    .onSubmit { commitPreviewScaleInput() }
                    .accessibilityLabel("预览缩放百分比")
                    .help("输入 25 到 200 之间的百分比，按回车或点击其他位置应用")

                Text("%")
                    .font(JarvisTypography.monospaced)
                    .foregroundStyle(Color.jarvisTextSecondary)
            }
            .frame(width: 72, height: JarvisToolbarMetrics.controlSize)
            .contentShape(Rectangle())

            Divider()
                .frame(height: 16)
                .opacity(0.35)

            ResumeZoomButton(systemName: "plus", accessibilityLabel: "放大预览") {
                adjustPreviewScale(by: 1)
            }
        }
        .padding(.horizontal, 2)
        .frame(height: JarvisToolbarMetrics.controlSize)
        .accessibilityElement(children: .contain)
    }

    var resumeEditorHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            resumeFilenameEditor

            HStack(spacing: 5) {
                Image(systemName: workspace.isSaved ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(workspace.isSaved ? .green : Color.jarvisTextSecondary)
                Text(saveStatusText)
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .help("保存只会在你主动保存时发生；新建会先处理未保存内容")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    var resumeFilenameEditor: some View {
        let displayTitle = workspace.document.title.isEmpty ? "未命名简历" : workspace.document.title

        return ZStack(alignment: .leading) {
            Text(displayTitle)
                .font(JarvisTypography.cardTitle)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, ResumeFilenameMetrics.horizontalPadding)
                .frame(height: JarvisToolbarMetrics.controlSize)
                .opacity(0)

            TextField("", text: $workspace.document.title)
                .textFieldStyle(.plain)
                .font(JarvisTypography.cardTitle)
                .lineLimit(1)
                .focused($isFilenameFocused)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, ResumeFilenameMetrics.horizontalPadding)
                .frame(height: JarvisToolbarMetrics.controlSize)
                .accessibilityLabel("简历名称")
        }
        .contentShape(Capsule())
        .onTapGesture {
            isFilenameFocused = true
        }
        .background(Color.primary.opacity(0.07), in: Capsule())
        .background(
            ResumeFilenameOutsideClickMonitor(
                isFocused: isFilenameFocused,
                onDismiss: { finishFilenameEditing() }
            )
        )
        .help("点击修改简历名称，按回车或点击其他区域提交")
    }

    var documentCanvas: some View {
        let pageCount = ResumePageLayout.pages(for: workspace.document).count
        let pageHeight = ResumePageLayout.pageSize.height * CGFloat(pageCount)
            + ResumePageLayout.pageSpacing * CGFloat(max(pageCount - 1, 0))

        return ScrollView([.vertical, .horizontal]) {
            VStack(spacing: 16) {
                ResumePagedView(
                    document: workspace.document,
                    selectedProjectID: selectedProjectID,
                    selectedBulletIndex: selectedBulletIndex,
                    showsEmptyState: true,
                    onSelectProject: { projectID in
                        expandedSection = .projects
                        selectedProjectID = projectID
                        selectedBulletIndex = 0
                    },
                    onSelectBullet: { projectID, bulletIndex in
                        expandedSection = .projects
                        selectedProjectID = projectID
                        selectedBulletIndex = bulletIndex
                    }
                )
                .frame(width: ResumePageLayout.pageSize.width, height: pageHeight, alignment: .top)
                .scaleEffect(previewScale, anchor: .top)
                .frame(
                    width: ResumePageLayout.pageSize.width * previewScale,
                    height: pageHeight * previewScale,
                    alignment: .top
                )
                .clipShape(Rectangle())
                .shadow(color: .black.opacity(0.10), radius: 20, y: 8)
            }
            .padding(.top, 72)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                guard isFilenameFocused else { return }
                finishFilenameEditing()
            }
        )
    }

    var saveStatusText: String {
        guard workspace.isSaved, let lastSavedAt = workspace.lastSavedAt else {
            return "未保存"
        }
        return "已保存 · \(lastSavedAt.formatted(date: .omitted, time: .shortened))"
    }

    func normalizeFilename() {
        if workspace.document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            workspace.document.title = "未命名简历"
        }
    }

    func finishFilenameEditing() {
        normalizeFilename()
        isFilenameFocused = false
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    var previewScalePercentage: Int {
        Int((previewScale * 100).rounded())
    }

    func setPreviewScalePercentage(_ percentage: Int) {
        let clampedPercentage = ResumeZoomScale.clampedPercentage(percentage)
        previewScale = CGFloat(clampedPercentage) / 100
        previewScaleInput = String(clampedPercentage)
    }

    func adjustPreviewScale(by delta: Int) {
        commitPreviewScaleInput()
        setPreviewScalePercentage(previewScalePercentage + delta)
    }

    func commitPreviewScaleInput() {
        let percentage = ResumeZoomScale.percentage(
            from: previewScaleInput,
            fallback: previewScalePercentage
        )
        setPreviewScalePercentage(percentage)
        isPreviewScaleInputFocused = false
    }

    func beginNewResume() {
        finishFilenameEditing()
        workspace.beginNewResume()
        selectedTemplateCategory = .all
        expandedSection = .basicInfo
        selectedProjectID = nil
        selectedBulletIndex = 0
        app.showToast("已新建空白简历")
    }

    func requestNewResume() {
        finishFilenameEditing()
        if workspace.requiresSaveBeforeNewResume {
            isNewResumeConfirmationPresented = true
        } else {
            beginNewResume()
        }
    }

    func saveResumeAndBeginNew() {
        export(.pdf) {
            beginNewResume()
        }
    }

    func normalizeSelection() {
        guard let selectedProjectID else { return }
        guard workspace.document.projects.contains(where: { $0.id == selectedProjectID }) else {
            self.selectedProjectID = workspace.document.projects.first?.id
            selectedBulletIndex = 0
            return
        }
        let count = workspace.document.projects.first(where: { $0.id == selectedProjectID })?.bullets.count ?? 0
        selectedBulletIndex = min(selectedBulletIndex, max(count - 1, 0))
    }

    func export(_ format: ResumeExportFormat, afterSave: (() -> Void)? = nil) {
        do {
            let data = try ResumeExportService.data(for: workspace.document, format: format)
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.allowedContentTypes = [format.contentType]
            let title = workspace.document.title.trimmingCharacters(in: .whitespacesAndNewlines)
            panel.nameFieldStringValue = "\(title.isEmpty ? "未命名简历" : title).\(format.fileExtension)"

            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            workspace.markSaved(to: url)
            app.showToast("已保存为 \(format.title)")
            afterSave?()
        } catch {
            app.showToast("保存失败：\(error.localizedDescription)")
        }
    }

    func importJSON() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let importedDocument = try ResumeDocumentCodec.decode(Data(contentsOf: url))
            workspace.replace(with: importedDocument)
            expandedSection = .basicInfo
            selectedProjectID = importedDocument.projects.first?.id
            selectedBulletIndex = 0
            app.showToast("已打开 JSON 简历：\(importedDocument.title)")
        } catch {
            app.showToast("打开失败：JSON 文件格式无效")
        }
    }
}

private enum ResumeFilenameMetrics {
    static let horizontalPadding: CGFloat = 10
}

private struct ResumeFilenameOutsideClickMonitor: NSViewRepresentable {
    let isFocused: Bool
    let onDismiss: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView(frame: .zero)
        context.coordinator.update(view: view, isFocused: isFocused, dismiss: onDismiss)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(view: nsView, isFocused: isFocused, dismiss: onDismiss)
    }

    static func dismantleNSView(_: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private final class PassthroughView: NSView {
        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    }

    @MainActor
    final class Coordinator {
        weak var view: NSView?
        private var monitor: Any?
        private var dismiss: (() -> Void)?

        func update(view: NSView, isFocused: Bool, dismiss: @escaping () -> Void) {
            self.view = view
            self.dismiss = dismiss
            if isFocused {
                startIfNeeded()
            } else {
                stop()
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func startIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                guard let self, let view = self.view, let contentWindow = view.window else { return event }
                guard event.window === contentWindow else { return event }
                let pointInView = view.convert(event.locationInWindow, from: nil)
                if !view.bounds.contains(pointInView) {
                    self.dismiss?()
                }
                return event
            }
        }
    }
}

extension ResumeExportFormat {
    var contentType: UTType {
        switch self {
        case .pdf: .pdf
        case .markdown: .plainText
        case .json: .json
        }
    }
}
