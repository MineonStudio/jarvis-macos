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
                emptyState
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(width: 620, height: 876, alignment: .topLeading)
        .background(ResumePaperPalette.paper)
        .foregroundStyle(ResumePaperPalette.ink)
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
        case .timeline:
            timelineLayout(content)
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

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: "doc.text")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(ResumePaperPalette.accent(for: document.template))
            Text("新简历")
                .font(.system(size: 25, weight: .bold, design: .rounded))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
    }

    private func nonEmpty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            return try pdfData(for: document)
        case .rtf:
            let attributed = NSAttributedString(
                string: ResumeTextFormatter.plainText(for: document),
                attributes: [.font: NSFont.systemFont(ofSize: 12)]
            )
            return try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        case .markdown:
            return Data(ResumeTextFormatter.markdown(for: document).utf8)
        case .json:
            return try ResumeDocumentCodec.encodedData(for: document)
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
