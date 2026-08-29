import SwiftUI

enum ResumePaperPalette {
    static let paper = Color.white
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let body = Color(red: 0.18, green: 0.19, blue: 0.22)
    static let muted = Color(red: 0.38, green: 0.40, blue: 0.44)
    static let softLine = Color(red: 0.89, green: 0.90, blue: 0.92)
    static let blue = Color(red: 0.16, green: 0.38, blue: 0.86)
    static let teal = Color(red: 0.04, green: 0.43, blue: 0.43)

    static func accent(for template: ResumeTemplate) -> Color {
        switch template {
        case .minimal:
            blue
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

    private var contact: [String] {
        [
            document.basicInfo.location,
            document.basicInfo.email,
            document.basicInfo.jobStatus,
            document.basicInfo.workYears
        ].filter(nonEmpty)
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
        }
    }

    @ViewBuilder
    private func headline(accent: Color) -> some View {
        if nonEmpty(document.basicInfo.headline) {
            Text(document.basicInfo.headline)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
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
        switch template {
        case .minimal, .editorial:
            Text(skills.joined(separator: "  ·  "))
                .font(.system(size: 9.5, weight: .medium, design: template == .editorial ? .serif : .rounded))
                .foregroundStyle(ResumePaperPalette.body)
                .lineSpacing(4)
        case .timeline:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ForEach(Array(skills.enumerated()), id: \.offset) { index, skill in
                    if index > 0 {
                        Text("·")
                            .foregroundStyle(ResumePaperPalette.teal)
                    }
                    Text(skill)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(ResumePaperPalette.body)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
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
