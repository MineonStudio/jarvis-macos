import SwiftUI

struct ResumeTemplateSelectionView: View {
    let onSelect: (ResumeTemplate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("选择简历模板")
                    .font(JarvisTypography.pageTitle)
                Text("选择一个版式开始编辑，之后可在编辑器中继续完善内容。")
                    .font(JarvisTypography.body)
                    .foregroundStyle(Color.jarvisTextSecondary)
            }

            GeometryReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 232), spacing: 16)],
                        alignment: .leading,
                        spacing: 16
                    ) {
                        ForEach(ResumeTemplate.allCases) { template in
                            ResumeTemplateCard(template: template, onSelect: onSelect)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
                    .frame(minHeight: max(proxy.size.height, 430), alignment: .topLeading)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .jarvisFloatingPanel(cornerRadius: 18)
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.jarvisBackground)
    }
}

private struct ResumeTemplateCard: View {
    let template: ResumeTemplate
    let onSelect: (ResumeTemplate) -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            onSelect(template)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: template.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(template.title)
                                .font(JarvisTypography.cardTitle)
                            if template == .defaultTemplate {
                                Text("默认")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.11), in: Capsule())
                            }
                        }
                        Text(template.subtitle)
                            .font(JarvisTypography.caption)
                            .foregroundStyle(Color.jarvisTextSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .opacity(isHovered ? 1 : 0.55)
                }

                ResumeTemplateThumbnail(template: template)
                    .frame(maxWidth: .infinity)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHovered
                    ? Color.accentColor.opacity(0.08)
                    : Color.jarvisPanel.opacity(0.42),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isHovered ? Color.accentColor.opacity(0.48) : Color.primary.opacity(0.09),
                        lineWidth: isHovered ? 1.1 : 0.75
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("选择\(template.title)模板")
        .accessibilityHint(template.subtitle)
    }
}

private struct ResumeTemplateThumbnail: View {
    let template: ResumeTemplate

    var body: some View {
        page
            .frame(width: 168, height: 237, alignment: .topLeading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .shadow(color: .black.opacity(0.13), radius: 8, y: 3)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var page: some View {
        switch template {
        case .editorial:
            VStack(alignment: .center, spacing: 8) {
                Text("CURRICULUM VITAE")
                    .font(.system(size: 5, weight: .semibold, design: .serif))
                    .kerning(1)
                    .foregroundStyle(ResumePaperPalette.muted)
                Text("林知远")
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .foregroundStyle(ResumePaperPalette.ink)
                Text("产品经理")
                    .font(.system(size: 6, weight: .medium, design: .serif))
                    .foregroundStyle(ResumePaperPalette.muted)
                divider
                miniSection(title: "教育经历", accent: ResumePaperPalette.ink)
                miniSection(title: "工作经历", accent: ResumePaperPalette.ink)
                miniSection(title: "掌握技能", accent: ResumePaperPalette.ink)
                miniSection(title: "项目经历", accent: ResumePaperPalette.ink)
            }
            .padding(19)
        case .minimal:
            VStack(alignment: .leading, spacing: 11) {
                Text("林知远")
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .foregroundStyle(ResumePaperPalette.ink)
                Text("产品经理  ·  上海  ·  6年经验")
                    .font(.system(size: 5.5, weight: .medium, design: .rounded))
                    .foregroundStyle(ResumePaperPalette.muted)
                Rectangle()
                    .fill(ResumePaperPalette.ink)
                    .frame(height: 2)
                miniMinimalSection("教育经历")
                miniMinimalSection("工作经历")
                miniMinimalSection("掌握技能")
                miniMinimalSection("项目经历")
            }
            .padding(18)
        case .timeline:
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 6) {
                    ForEach(0 ..< 5, id: \.self) { _ in
                        Circle()
                            .fill(ResumePaperPalette.teal)
                            .frame(width: 6, height: 6)
                        Rectangle()
                            .fill(ResumePaperPalette.teal.opacity(0.28))
                            .frame(width: 1, height: 28)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("林知远")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(ResumePaperPalette.ink)
                    Text("成长轨迹")
                        .font(.system(size: 6, weight: .semibold))
                        .foregroundStyle(ResumePaperPalette.teal)
                    miniTimelineSection("2021 — 至今", "高级产品经理")
                    miniTimelineSection("2018 — 2021", "产品经理")
                    miniTimelineSection("2015 — 2018", "计算机科学 · 硕士")
                    Text("产品规划  ·  用户研究  ·  数据分析")
                        .font(.system(size: 5.5, weight: .medium, design: .rounded))
                        .foregroundStyle(ResumePaperPalette.body)
                        .lineLimit(1)
                }
            }
            .padding(16)
        }
    }

    private func miniSection(title: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 6.5, weight: .bold, design: .rounded))
                    .foregroundStyle(ResumePaperPalette.ink)
                Spacer(minLength: 0)
            }
            miniLine(width: nil, color: accent.opacity(0.32))
            miniLine(width: 90, color: ResumePaperPalette.body.opacity(0.24))
            miniLine(width: 68, color: ResumePaperPalette.muted.opacity(0.16))
        }
    }

    private func miniLine(width: CGFloat?, color: Color = .black.opacity(0.22)) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: 2)
    }

    private var divider: some View {
        divider(color: ResumePaperPalette.muted)
    }

    private func divider(color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
    }

    private func miniMinimalSection(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 5.5, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(ResumePaperPalette.muted)
            miniLine(width: nil, color: ResumePaperPalette.softLine)
            miniLine(width: 86, color: ResumePaperPalette.body.opacity(0.35))
            miniLine(width: 61, color: ResumePaperPalette.muted.opacity(0.22))
        }
    }

    private func miniTimelineSection(_ period: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(period)
                .font(.system(size: 5, weight: .bold, design: .rounded))
                .foregroundStyle(ResumePaperPalette.teal)
            Text(title)
                .font(.system(size: 6.5, weight: .semibold, design: .rounded))
                .foregroundStyle(ResumePaperPalette.ink)
            miniLine(width: 86, color: ResumePaperPalette.muted.opacity(0.25))
        }
    }
}

extension ResumeTemplate {
    var previewDocument: ResumeDocument {
        ResumeDocument(
            title: "模板示例",
            template: self,
            basicInfo: ResumeBasicInfo(
                name: "林知远",
                headline: "产品经理",
                email: "lin.zhiyuan@example.com",
                location: "上海",
                jobStatus: "在职",
                workYears: "6年经验"
            ),
            education: [
                ResumeEducation(
                    school: "上海交通大学",
                    degree: "硕士",
                    major: "计算机科学",
                    period: "2015 — 2018"
                )
            ],
            experience: [
                ResumeExperience(
                    company: "星云科技",
                    role: "高级产品经理",
                    period: "2021 — 至今"
                )
            ],
            skills: ["产品规划", "用户研究", "数据分析"],
            projects: [
                ResumeProject(
                    name: "智能工单平台",
                    period: "2022 — 2023",
                    summary: "面向企业客户的协作平台，支持问题受理、自动分派与服务分析。",
                    bullets: ["推动项目上线并持续迭代"]
                )
            ]
        )
    }
}
