import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ResumePageContent: Sendable {
    let includesHeader: Bool
    var education: [ResumeEducation]
    var experience: [ResumeExperience]
    var skills: [String]
    var projects: [ResumeProject]

    var hasContent: Bool {
        !education.isEmpty || !experience.isEmpty || !skills.isEmpty || !projects.isEmpty
    }

    static func fullDocument(_ document: ResumeDocument) -> Self {
        Self(
            includesHeader: true,
            education: document.education.filter(\.hasContent),
            experience: document.experience.filter(\.hasContent),
            skills: document.skills.filter(nonEmpty),
            projects: document.projects.filter(\.hasContent)
        )
    }

    private static func nonEmpty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum ResumePageLayout {
    static let pageSize = CGSize(width: 620, height: 876)
    static let pageSpacing: CGFloat = 16

    static func pages(for document: ResumeDocument) -> [ResumePageContent] {
        let fullContent = ResumePageContent.fullDocument(document)
        guard document.hasContent else { return [fullContent] }

        var pages: [ResumePageContent] = []
        var current = ResumePageAccumulator(
            includesHeader: true,
            usedHeight: estimatedHeaderHeight(for: document)
        )

        for item in fullContent.education {
            place(
                .education(item),
                height: estimatedEducationHeight(item),
                current: &current,
                pages: &pages
            )
        }
        for item in fullContent.experience {
            place(
                .experience(item),
                height: estimatedExperienceHeight(item),
                current: &current,
                pages: &pages
            )
        }
        if !fullContent.skills.isEmpty {
            place(
                .skills(fullContent.skills),
                height: estimatedSkillsHeight(fullContent.skills),
                current: &current,
                pages: &pages
            )
        }
        for item in fullContent.projects {
            place(
                .project(item),
                height: estimatedProjectHeight(item),
                current: &current,
                pages: &pages
            )
        }

        if current.hasSectionContent {
            pages.append(current.content)
        }
        return pages.isEmpty ? [fullContent] : pages
    }

    private static func place(
        _ item: ResumePageItem,
        height: CGFloat,
        current: inout ResumePageAccumulator,
        pages: inout [ResumePageContent]
    ) {
        let sectionHeaderHeight = current.contains(item) ? 0 : 35
        let totalHeight = height + CGFloat(sectionHeaderHeight)
        if current.hasSectionContent, current.usedHeight + totalHeight > 780 {
            pages.append(current.content)
            current = ResumePageAccumulator(includesHeader: false, usedHeight: 0)
        }
        current.append(item)
        current.usedHeight += totalHeight
    }

    private static func estimatedHeaderHeight(for document: ResumeDocument) -> CGFloat {
        var height: CGFloat = 18
        if nonEmpty(document.basicInfo.name) {
            height += 34
        }
        if nonEmpty(document.basicInfo.headline) {
            height += 20
        }
        let contact = [
            document.basicInfo.location,
            document.basicInfo.email,
            document.basicInfo.jobStatus,
            document.basicInfo.workYears
        ]
        if contact.contains(where: nonEmpty) {
            height += 18
        }
        return height
    }

    private static func estimatedEducationHeight(_ item: ResumeEducation) -> CGFloat {
        24 + estimatedTextHeight([item.school, item.degree, item.major, item.period])
    }

    private static func estimatedExperienceHeight(_ item: ResumeExperience) -> CGFloat {
        24 + estimatedTextHeight([item.company, item.role, item.period])
    }

    private static func estimatedSkillsHeight(_ skills: [String]) -> CGFloat {
        let lineCount = max(1, Int(ceil(Double(skills.count) / 5.0)))
        return CGFloat(lineCount) * 26
    }

    private static func estimatedProjectHeight(_ item: ResumeProject) -> CGFloat {
        25
            + (nonEmpty(item.summary) ? estimatedTextHeight([item.summary]) + 5 : 0)
            + item.bullets.reduce(CGFloat.zero) { height, bullet in
                height + estimatedTextHeight([bullet]) + 5
            }
    }

    private static func estimatedTextHeight(_ values: [String]) -> CGFloat {
        let longest = values.map(\.count).max() ?? 0
        let lineCount = max(1, Int(ceil(Double(longest) / 62)))
        return CGFloat(lineCount) * 16
    }

    private static func nonEmpty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private enum ResumePageItem {
    case education(ResumeEducation)
    case experience(ResumeExperience)
    case skills([String])
    case project(ResumeProject)
}

private struct ResumePageAccumulator {
    let includesHeader: Bool
    var usedHeight: CGFloat
    var education: [ResumeEducation] = []
    var experience: [ResumeExperience] = []
    var skills: [String] = []
    var projects: [ResumeProject] = []

    var hasSectionContent: Bool {
        !education.isEmpty || !experience.isEmpty || !skills.isEmpty || !projects.isEmpty
    }

    var content: ResumePageContent {
        ResumePageContent(
            includesHeader: includesHeader,
            education: education,
            experience: experience,
            skills: skills,
            projects: projects
        )
    }

    func contains(_ item: ResumePageItem) -> Bool {
        switch item {
        case .education:
            !education.isEmpty
        case .experience:
            !experience.isEmpty
        case .skills:
            !skills.isEmpty
        case .project:
            !projects.isEmpty
        }
    }

    mutating func append(_ item: ResumePageItem) {
        switch item {
        case let .education(value):
            education.append(value)
        case let .experience(value):
            experience.append(value)
        case let .skills(values):
            skills.append(contentsOf: values)
        case let .project(value):
            projects.append(value)
        }
    }
}

struct ResumePageView: View {
    let document: ResumeDocument
    let selectedProjectID: UUID?
    let selectedBulletIndex: Int?
    let showsEmptyState: Bool
    let onSelectProject: (UUID) -> Void
    let onSelectBullet: (UUID, Int) -> Void
    let pageContent: ResumePageContent?

    init(
        document: ResumeDocument,
        selectedProjectID: UUID?,
        selectedBulletIndex: Int?,
        showsEmptyState: Bool,
        onSelectProject: @escaping (UUID) -> Void,
        onSelectBullet: @escaping (UUID, Int) -> Void,
        pageContent: ResumePageContent? = nil
    ) {
        self.document = document
        self.selectedProjectID = selectedProjectID
        self.selectedBulletIndex = selectedBulletIndex
        self.showsEmptyState = showsEmptyState
        self.onSelectProject = onSelectProject
        self.onSelectBullet = onSelectBullet
        self.pageContent = pageContent
    }

    var body: some View {
        let content = pageContent ?? ResumePageContent.fullDocument(document)
        Group {
            if document.hasContent {
                templateLayout(content)
            } else if showsEmptyState {
                templatePlaceholderLayout
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(width: 620, height: 876, alignment: .topLeading)
        .background(ResumePaperPalette.paper)
        .foregroundStyle(ResumePaperPalette.ink)
        .clipShape(Rectangle())
        .overlay {
            Rectangle()
                .strokeBorder(ResumePaperPalette.softLine, lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private func templateLayout(_ content: ResumePageContent) -> some View {
        switch document.template {
        case .editorial:
            editorialLayout(content)
        case .minimal:
            minimalLayout(content)
        case .creative:
            creativeLayout(content)
        case .timeline:
            timelineLayout(content)
        }
    }

    private var templatePlaceholderLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch document.template {
            case .editorial:
                ResumePageHeader(
                    document: document,
                    template: .editorial,
                    showsPlaceholders: true
                )
                Rectangle()
                    .fill(ResumePaperPalette.ink)
                    .frame(height: 1)
                    .padding(.top, 20)
                    .padding(.bottom, 2)
                placeholderPageSections(template: .editorial)
            case .minimal:
                ResumePageHeader(
                    document: document,
                    template: .minimal,
                    showsPlaceholders: true
                )
                Rectangle()
                    .fill(ResumePaperPalette.ink)
                    .frame(height: 2)
                    .padding(.top, 25)
                    .padding(.bottom, 1)
                placeholderPageSections(template: .minimal)
            case .creative:
                ResumePageHeader(
                    document: document,
                    template: .creative,
                    showsPlaceholders: true
                )
                Rectangle()
                    .fill(ResumePaperPalette.coral)
                    .frame(height: 2)
                    .padding(.top, 18)
                    .padding(.bottom, 1)
                placeholderPageSections(template: .creative)
            case .timeline:
                ResumePageHeader(
                    document: document,
                    template: .timeline,
                    showsPlaceholders: true
                )
                Rectangle()
                    .fill(ResumePaperPalette.teal)
                    .frame(height: 2)
                    .padding(.top, 20)
                placeholderPageSections(template: .timeline)
            }
            Spacer(minLength: 0)
        }
        .padding(
            .horizontal,
            document.template == .timeline
                ? 48
                : (document.template == .creative ? 52 : 58)
        )
        .padding(
            .vertical,
            document.template == .timeline
                ? 43
                : (document.template == .minimal ? 48 : (document.template == .creative ? 40 : 46))
        )
    }

    @ViewBuilder
    private func placeholderPageSections(template: ResumeTemplate) -> some View {
        ResumePageSection(title: "教育经历", template: template) {
            ResumePagePlaceholderRow(
                fields: ["学校", "学历 · 专业", "时间"],
                template: template
            )
        }
        ResumePageSection(title: "工作经历", template: template) {
            ResumePagePlaceholderRow(
                fields: ["公司 · 职位", "时间"],
                template: template
            )
        }
        ResumePageSection(title: "掌握技能", template: template) {
            HStack(spacing: 8) {
                ForEach(Array(["技能", "技能", "技能"].enumerated()), id: \.offset) { _, field in
                    ResumePagePlaceholderField(
                        title: field,
                        template: template
                    )
                }
            }
        }
        ResumePageSection(title: "项目经历", template: template) {
            VStack(alignment: .leading, spacing: 7) {
                ResumePagePlaceholderRow(
                    fields: ["项目名称", "时间"],
                    template: template
                )
                ResumePagePlaceholderField(title: "项目简介", template: template)
                ResumePagePlaceholderField(title: "项目要点", template: template)
            }
        }
    }

    private func editorialLayout(_ content: ResumePageContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if content.includesHeader {
                ResumePageHeader(document: document, template: .editorial)
                Rectangle()
                    .fill(ResumePaperPalette.ink)
                    .frame(height: 1)
                    .padding(.top, 20)
                    .padding(.bottom, 2)
            }
            pageSections(content, template: .editorial)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 58)
        .padding(.vertical, 46)
    }

    private func minimalLayout(_ content: ResumePageContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if content.includesHeader {
                ResumePageHeader(document: document, template: .minimal)
                Rectangle()
                    .fill(ResumePaperPalette.ink)
                    .frame(height: 2)
                    .padding(.top, 25)
                    .padding(.bottom, 1)
            }
            pageSections(content, template: .minimal)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 58)
        .padding(.vertical, 48)
    }

    private func creativeLayout(_ content: ResumePageContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if content.includesHeader {
                ResumePageHeader(document: document, template: .creative)
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(ResumePaperPalette.coral)
                        .frame(width: 36, height: 3)
                    Rectangle()
                        .fill(ResumePaperPalette.violet.opacity(0.28))
                        .frame(height: 1)
                }
                .padding(.top, 18)
                .padding(.bottom, 1)
            }
            pageSections(content, template: .creative)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 52)
        .padding(.vertical, 40)
    }

    private func timelineLayout(_ content: ResumePageContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if content.includesHeader {
                ResumePageHeader(document: document, template: .timeline)
                Rectangle()
                    .fill(ResumePaperPalette.teal)
                    .frame(height: 2)
                    .padding(.top, 20)
            }
            pageSections(content, template: .timeline)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 43)
    }

    @ViewBuilder
    private func pageSections(_ content: ResumePageContent, template: ResumeTemplate) -> some View {
        if !content.education.isEmpty {
            ResumePageSection(title: "教育经历", template: template) {
                ForEach(content.education) { item in
                    ResumePageEducation(item: item, template: template)
                }
            }
        }

        if !content.experience.isEmpty {
            ResumePageSection(title: "工作经历", template: template) {
                ForEach(content.experience) { item in
                    ResumePageExperience(item: item, template: template)
                }
            }
        }

        if !content.skills.isEmpty {
            ResumePageSection(title: "掌握技能", template: template) {
                ResumePageSkills(skills: content.skills, template: template)
            }
        }

        if !content.projects.isEmpty {
            ResumePageSection(title: "项目经历", template: template) {
                ForEach(content.projects) { project in
                    ResumePageProject(
                        project: project,
                        template: template,
                        selectedProjectID: selectedProjectID,
                        selectedBulletIndex: selectedBulletIndex,
                        onSelectProject: onSelectProject,
                        onSelectBullet: onSelectBullet
                    )
                }
            }
        }
    }

    private func nonEmpty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct ResumePagePlaceholderRow: View {
    let fields: [String]
    let template: ResumeTemplate

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            ForEach(Array(fields.dropLast().enumerated()), id: \.offset) { _, field in
                ResumePagePlaceholderField(title: field, template: template)
            }
            Spacer(minLength: 8)
            if let lastField = fields.last {
                ResumePagePlaceholderField(title: lastField, template: template)
            }
        }
    }
}

private struct ResumePagePlaceholderField: View {
    let title: String
    let template: ResumeTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(
                    size: template == .editorial ? 10 : 9.5,
                    weight: .regular,
                    design: template == .editorial ? .serif : .default
                ))
                .foregroundStyle(ResumePaperPalette.muted.opacity(0.78))
                .lineLimit(1)
            Rectangle()
                .fill(ResumePaperPalette.softLine)
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ResumePagedView: View {
    let document: ResumeDocument
    let selectedProjectID: UUID?
    let selectedBulletIndex: Int?
    let showsEmptyState: Bool
    let onSelectProject: (UUID) -> Void
    let onSelectBullet: (UUID, Int) -> Void

    var body: some View {
        let pages = ResumePageLayout.pages(for: document)
        VStack(spacing: ResumePageLayout.pageSpacing) {
            ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                ResumePageView(
                    document: document,
                    selectedProjectID: selectedProjectID,
                    selectedBulletIndex: selectedBulletIndex,
                    showsEmptyState: showsEmptyState,
                    onSelectProject: onSelectProject,
                    onSelectBullet: onSelectBullet,
                    pageContent: page
                )
            }
        }
    }
}

enum ResumeExportService {
    @MainActor
    static func data(for document: ResumeDocument, format: ResumeExportFormat) throws -> Data {
        switch format {
        case .pdf:
            try pdfData(for: document)
        case .markdown:
            Data(ResumeTextFormatter.markdown(for: document).utf8)
        case .json:
            try ResumeDocumentCodec.encodedData(for: document)
        }
    }

    @MainActor
    private static func pdfData(for document: ResumeDocument) throws -> Data {
        let pages = ResumePageLayout.pages(for: document)
        let pageRect = CGRect(
            origin: .zero,
            size: ResumePageLayout.pageSize
        )
        let data = NSMutableData()
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw ResumeExportError.renderingFailed
        }

        for page in pages {
            let printablePage = ResumePageView(
                document: document,
                selectedProjectID: nil,
                selectedBulletIndex: nil,
                showsEmptyState: false,
                onSelectProject: { _ in },
                onSelectBullet: { _, _ in },
                pageContent: page
            )
            let renderer = ImageRenderer(content: printablePage)
            renderer.proposedSize = ProposedViewSize(
                width: ResumePageLayout.pageSize.width,
                height: ResumePageLayout.pageSize.height
            )
            renderer.scale = 2

            guard let image = renderer.nsImage,
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else {
                throw ResumeExportError.renderingFailed
            }

            context.beginPDFPage(nil)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(pageRect)
            context.draw(cgImage, in: pageRect)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}

private enum ResumeExportError: Error {
    case renderingFailed
}
