import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ResumeContentView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var workspace: ResumeWorkspace

    @State private var expandedSection: ResumeSection? = .basicInfo
    @State private var selectedProjectID: UUID?
    @State private var selectedBulletIndex = 0
    @State private var previewScale: CGFloat = 1.0
    @State private var previewScaleInput = "100"
    @State private var isNewResumeConfirmationPresented = false
    @FocusState private var isFilenameFocused: Bool
    @FocusState private var isPreviewScaleInputFocused: Bool

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                if workspace.needsTemplateSelection {
                    ToolbarItem(placement: .navigation) {
                        EmptyView()
                    }
                } else {
                    ToolbarItem(placement: .navigation) {
                        resumeToolbarLeading
                    }
                }
            },
            trailingToolbar: {
                if workspace.needsTemplateSelection {
                    ToolbarItem(placement: .automatic) {
                        EmptyView()
                    }
                } else {
                    ToolbarItem(placement: .automatic) {
                        resumeToolbarTrailing
                    }
                }
            },
            content: {
                Group {
                    if workspace.needsTemplateSelection {
                        ResumeTemplateSelectionView { template in
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

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(.clear)

                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(width: 48, height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}

private extension ResumeContentView {
    var resumeEditorLayout: some View {
        HStack(spacing: 0) {
            documentCanvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            ResumeInspector(
                draft: $workspace.document,
                expandedSection: $expandedSection
            )
            .frame(width: 348)
        }
    }

    var resumeToolbarLeading: some View {
        HStack(spacing: JarvisToolbarMetrics.controlSpacing) {
            TextField("未命名简历", text: $workspace.document.title)
                .textFieldStyle(.plain)
                .font(JarvisTypography.cardTitle)
                .frame(width: filenameWidth, height: JarvisToolbarMetrics.controlSize)
                .padding(.horizontal, 12)
                .background(Color.primary.opacity(0.08), in: Capsule())
                .focused($isFilenameFocused)
                .onSubmit { finishFilenameEditing() }
                .help("点击修改文件名")

            HStack(spacing: 5) {
                Image(systemName: workspace.isSaved ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(workspace.isSaved ? .green : Color.jarvisTextSecondary)
                Text(saveStatusText)
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.jarvisTextSecondary)
            }
            .help("保存只会在你主动保存时发生；新建会先处理未保存内容")
        }
    }

    var resumeToolbarTrailing: some View {
        HStack(spacing: JarvisToolbarMetrics.controlSpacing) {
            Button {
                requestNewResume()
            } label: {
                Text("新建简历")
            }
            .buttonStyle(JarvisToolbarButtonStyle())
            .help("直接打开一份全新的空白简历")

            Button {
                finishFilenameEditing()
                importJSON()
            } label: {
                Text("导入简历")
            }
            .buttonStyle(JarvisToolbarButtonStyle())
            .help("打开一份 JSON 简历作为当前文档")

            Menu {
                ForEach(ResumeExportFormat.allCases) { format in
                    Button("保存为 \(format.title)") {
                        finishFilenameEditing()
                        export(format)
                    }
                }
            } label: {
                Text("保存简历")
            }
            .buttonStyle(JarvisToolbarButtonStyle(tint: .accentColor))
            .help("选择 PDF、RTF、Markdown 或 JSON 保存简历")
        }
    }

    var documentCanvas: some View {
        let pageCount = ResumePageLayout.pages(for: workspace.document).count
        let pageHeight = ResumePageLayout.pageSize.height * CGFloat(pageCount)
            + ResumePageLayout.pageSpacing * CGFloat(max(pageCount - 1, 0))

        return VStack(spacing: 0) {
            ScrollView([.vertical, .horizontal]) {
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
                    .shadow(color: .black.opacity(0.10), radius: 20, y: 8)
                }
                .padding(.top, 72)
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .background(Color.jarvisPanel.opacity(0.46))

            previewControls
        }
    }

    var previewControls: some View {
        HStack(spacing: 14) {
            Label("A4  210 × 297 mm", systemImage: "doc")
                .font(JarvisTypography.caption)
                .foregroundStyle(Color.jarvisTextSecondary)

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                ResumeZoomButton(systemName: "minus", accessibilityLabel: "缩小预览") {
                    adjustPreviewScale(by: -1)
                }

                HStack(spacing: 2) {
                    TextField("100", text: $previewScaleInput)
                        .textFieldStyle(.plain)
                        .font(JarvisTypography.monospaced)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 42, height: 42)
                        .focused($isPreviewScaleInputFocused)
                        .onSubmit { commitPreviewScaleInput() }
                        .accessibilityLabel("预览缩放百分比")
                        .help("输入 25 到 200 之间的百分比，按回车或点击其他位置应用")

                    Text("%")
                        .font(JarvisTypography.monospaced)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
                .frame(width: 72, height: 42)
                .contentShape(Rectangle())

                ResumeZoomButton(systemName: "plus", accessibilityLabel: "放大预览") {
                    adjustPreviewScale(by: 1)
                }
            }
            .padding(4)
            .frame(height: 52)
            .jarvisGlass(in: Capsule())
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 58)
        .background(Color.jarvisBackground)
    }

    var filenameWidth: CGFloat {
        let value = workspace.document.title.isEmpty ? "未命名简历" : workspace.document.title
        let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let measuredWidth = (value as NSString).size(withAttributes: [.font: font]).width + 24
        return min(max(measuredWidth, 92), 220)
    }

    var saveStatusText: String {
        guard workspace.isSaved, let lastSavedAt = workspace.lastSavedAt else {
            return "未保存"
        }
        return "已保存 · \(lastSavedAt.formatted(date: .omitted, time: .shortened))"
    }

    func finishFilenameEditing() {
        if workspace.document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            workspace.document.title = "未命名简历"
        }
        isFilenameFocused = false
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
            workspace.markSaved()
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

extension ResumeExportFormat {
    var contentType: UTType {
        switch self {
        case .pdf: .pdf
        case .rtf: .rtf
        case .markdown: .plainText
        case .json: .json
        }
    }
}
