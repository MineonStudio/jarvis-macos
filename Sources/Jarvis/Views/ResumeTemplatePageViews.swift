import SwiftUI

enum ResumePaperPalette {
    static let paper = Color.white
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let body = Color(red: 0.18, green: 0.19, blue: 0.22)
    static let muted = Color(red: 0.38, green: 0.40, blue: 0.44)
    static let softLine = Color(red: 0.89, green: 0.90, blue: 0.92)
    static let blue = Color(red: 0.16, green: 0.38, blue: 0.86)
    static let teal = Color(red: 0.04, green: 0.43, blue: 0.43)
    static let coral = Color(red: 0.90, green: 0.30, blue: 0.22)
    static let violet = Color(red: 0.42, green: 0.27, blue: 0.78)

    static func accent(for template: ResumeTemplate) -> Color {
        switch template {
        case .minimal:
            blue
        case .creative:
            coral
        case .editorial:
            ink
        case .timeline:
            teal
        }
    }
}

struct ResumePageHeader: View {
    let document: ResumeDocument
    let template: ResumeTemplate
    let showsPlaceholders: Bool

    init(
        document: ResumeDocument,
        template: ResumeTemplate,
        showsPlaceholders: Bool = false
    ) {
        self.document = document
        self.template = template
        self.showsPlaceholders = showsPlaceholders
    }

    private var contact: [String] {
        let values = [
            document.basicInfo.location,
            document.basicInfo.email,
            document.basicInfo.jobStatus,
            document.basicInfo.workYears
        ]
        if showsPlaceholders {
            return zip(values, ["所在地", "联系方式", "岗位状态", "工作年限"])
                .map { value, placeholder in nonEmpty(value) ? value : placeholder }
        }
        return values.filter(nonEmpty)
    }

    var body: some View {
        switch template {
        case .minimal:
            VStack(alignment: .leading, spacing: 10) {
                name
                    .font(.system(size: 36, weight: .light, design: .rounded))
                HStack(spacing: 12) {
                    headline(accent: ResumePaperPalette.blue)
                    contactRow
                }
            }
        case .creative:
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CREATIVE PROFILE")
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(ResumePaperPalette.coral)
                    name
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                    headline(accent: ResumePaperPalette.coral)
                    contactRow
                }
                Spacer(minLength: 8)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ResumePaperPalette.violet.opacity(0.13))
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(ResumePaperPalette.coral)
                    }
            }
        case .editorial:
            VStack(alignment: .center, spacing: 8) {
                Text("CURRICULUM VITAE")
                    .font(.system(size: 7.5, weight: .semibold, design: .serif))
                    .kerning(2.2)
                    .foregroundStyle(ResumePaperPalette.muted)
                name
                    .font(.system(size: 29, weight: .medium, design: .serif))
                headline(accent: ResumePaperPalette.muted)
                    .font(.system(size: 11, weight: .medium, design: .serif))
                contactRow
            }
            .frame(maxWidth: .infinity)
        case .timeline:
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("CAREER PROFILE")
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(ResumePaperPalette.teal)
                    name
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    headline(accent: ResumePaperPalette.teal)
                }
                Spacer(minLength: 8)
                contactColumn
            }
        }
    }

    @ViewBuilder
    private var name: some View {
        if nonEmpty(document.basicInfo.name) {
            Text(document.basicInfo.name)
                .foregroundStyle(ResumePaperPalette.ink)
        } else if showsPlaceholders {
            Text("姓名")
                .foregroundStyle(ResumePaperPalette.muted.opacity(0.78))
        }
    }

    @ViewBuilder
    private func headline(accent: Color) -> some View {
        if nonEmpty(document.basicInfo.headline) {
            Text(document.basicInfo.headline)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
        } else if showsPlaceholders {
            Text("职位标题")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ResumePaperPalette.muted.opacity(0.78))
        }
    }

    @ViewBuilder
    private var contactRow: some View {
        if !contact.isEmpty {
            HStack(spacing: 12) {
                ForEach(contact, id: \.self) { item in
                    Text(item)
                }
            }
            .font(.system(size: 9.5))
            .foregroundStyle(ResumePaperPalette.muted)
        }
    }

    private var contactColumn: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(contact, id: \.self) { item in
                Text(item)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(ResumePaperPalette.muted)
            }
        }
    }

    private func nonEmpty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ResumePageSection<Content: View>: View {
    let title: String
    let template: ResumeTemplate
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionHeader
            content
        }
    }

    @ViewBuilder
    private var sectionHeader: some View {
        switch template {
        case .minimal:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(ResumePaperPalette.muted)
                Rectangle()
                    .fill(ResumePaperPalette.softLine)
                    .frame(height: 1)
            }
            .padding(.top, 24)
        case .creative:
            HStack(spacing: 8) {
                Circle()
                    .fill(ResumePaperPalette.coral)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(ResumePaperPalette.ink)
                Capsule()
                    .fill(ResumePaperPalette.coral.opacity(0.30))
                    .frame(height: 1.2)
            }
            .padding(.top, 18)
        case .editorial:
            HStack(spacing: 10) {
                Rectangle()
                    .fill(ResumePaperPalette.muted)
                    .frame(height: 0.6)
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .serif))
                    .foregroundStyle(ResumePaperPalette.ink)
                    .fixedSize()
                Rectangle()
                    .fill(ResumePaperPalette.muted)
                    .frame(height: 0.6)
            }
            .padding(.top, 17)
        case .timeline:
            HStack(spacing: 8) {
                Circle()
                    .fill(ResumePaperPalette.teal)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(ResumePaperPalette.ink)
                Rectangle()
                    .fill(ResumePaperPalette.teal.opacity(0.34))
                    .frame(height: 1)
            }
            .padding(.top, 17)
        }
    }
}

struct ResumePageEducation: View {
    let item: ResumeEducation
    let template: ResumeTemplate

    var body: some View {
        if template == .timeline {
            HStack(alignment: .top, spacing: 10) {
                ResumeTimelineRail()
                educationRow
            }
        } else {
            educationRow
        }
    }

    private var educationRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(item.school)
                .font(.system(size: 10.5, weight: .semibold, design: template == .editorial ? .serif : .default))
                .foregroundStyle(ResumePaperPalette.ink)
            Text([item.degree, item.major].filter(nonEmpty).joined(separator: " · "))
                .font(.system(size: 10.5, design: template == .editorial ? .serif : .default))
                .foregroundStyle(ResumePaperPalette.body)
            Spacer(minLength: 8)
            Text(item.period)
                .font(.system(size: 9.5, design: template == .editorial ? .serif : .default))
                .foregroundStyle(ResumePaperPalette.muted)
        }
    }

    private func nonEmpty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ResumePageExperience: View {
    let item: ResumeExperience
    let template: ResumeTemplate

    var body: some View {
        if template == .timeline {
            HStack(alignment: .top, spacing: 10) {
                ResumeTimelineRail()
                experienceRow
            }
        } else {
            experienceRow
        }
    }

    private var experienceRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(item.company)
                .font(.system(size: 10.5, weight: .semibold, design: template == .editorial ? .serif : .default))
                .foregroundStyle(ResumePaperPalette.ink)
            Text(item.role)
                .font(.system(size: 9.5, design: template == .editorial ? .serif : .default))
                .foregroundStyle(ResumePaperPalette.body)
            Spacer(minLength: 8)
            Text(item.period)
                .font(.system(size: 9.5, design: template == .editorial ? .serif : .default))
                .foregroundStyle(ResumePaperPalette.muted)
        }
        .padding(.bottom, 6)
    }
}

struct ResumeTimelineRail: View {
    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(ResumePaperPalette.teal)
                .frame(width: 7, height: 7)
            Rectangle()
                .fill(ResumePaperPalette.teal.opacity(0.25))
                .frame(width: 1, height: 30)
        }
        .frame(width: 9, alignment: .top)
    }
}

struct ResumePageSkills: View {
    let skills: [String]
    let template: ResumeTemplate

    var body: some View {
        ResumeSkillFlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(skills.enumerated()), id: \.offset) { _, skill in
                skillChip(skill)
            }
        }
    }

    @ViewBuilder
    private func skillChip(_ skill: String) -> some View {
        switch template {
        case .minimal:
            Text(skill)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(ResumePaperPalette.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(ResumePaperPalette.blue.opacity(0.08), in: Capsule())
        case .creative:
            Text(skill)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(ResumePaperPalette.coral)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    ResumePaperPalette.coral.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(ResumePaperPalette.coral.opacity(0.24), lineWidth: 0.6)
                }
        case .editorial:
            Text(skill)
                .font(.system(size: 9, weight: .medium, design: .serif))
                .foregroundStyle(ResumePaperPalette.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(ResumePaperPalette.ink.opacity(0.22))
                        .frame(height: 0.6)
                }
        case .timeline:
            Text(skill)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(ResumePaperPalette.teal)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(ResumePaperPalette.teal.opacity(0.10), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(ResumePaperPalette.teal.opacity(0.28), lineWidth: 0.6)
                }
        }
    }
}

private struct ResumeSkillFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, lineCount: Int) {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var lineCount = 1
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
                lineCount += 1
            }
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
            usedWidth = max(usedWidth, x - spacing)
        }
        let width = maxWidth.isFinite ? maxWidth : usedWidth
        return (CGSize(width: width, height: y + lineHeight), lineCount)
    }
}

struct ResumePageProject: View {
    let project: ResumeProject
    let template: ResumeTemplate
    let selectedProjectID: UUID?
    let selectedBulletIndex: Int?
    let onSelectProject: (UUID) -> Void
    let onSelectBullet: (UUID, Int) -> Void

    var body: some View {
        if template == .timeline {
            HStack(alignment: .top, spacing: 10) {
                ResumeTimelineRail()
                projectContent
            }
        } else {
            projectContent
        }
    }

    private var projectContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Button {
                    onSelectProject(project.id)
                } label: {
                    Text(project.name)
                        .font(.system(
                            size: 10.5,
                            weight: .semibold,
                            design: template == .editorial ? .serif : .default
                        ))
                        .foregroundStyle(ResumePaperPalette.ink)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 8)
                Text(project.period)
                    .font(.system(size: 9.5))
                    .foregroundStyle(ResumePaperPalette.muted)
            }

            if nonEmpty(project.summary) {
                Text(project.summary)
                    .font(.system(size: 9.5, design: template == .editorial ? .serif : .default))
                    .foregroundStyle(ResumePaperPalette.body)
                    .lineSpacing(1)
                    .multilineTextAlignment(.leading)
            }

            ForEach(Array(project.bullets.enumerated()).filter { nonEmpty($0.element) }, id: \.offset) { bulletIndex, bullet in
                Button {
                    onSelectBullet(project.id, bulletIndex)
                } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(ResumePaperPalette.accent(for: template))
                        Text(bullet)
                            .font(.system(size: 9.5, design: template == .editorial ? .serif : .default))
                            .foregroundStyle(ResumePaperPalette.body)
                            .lineSpacing(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(
                        project.id == selectedProjectID && bulletIndex == selectedBulletIndex
                            ? ResumePaperPalette.accent(for: template).opacity(0.12)
                            : .clear,
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 8)
    }

    private func nonEmpty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
