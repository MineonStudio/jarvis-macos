import SwiftUI

struct ResumeInspector: View {
    @EnvironmentObject private var app: AppModel
    @Binding var draft: ResumeDocument
    @Binding var expandedSection: ResumeSection?
    @State private var projectGenerationDomain = ""
    @State private var isProjectGenerationPromptPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("编辑简历")
                    .font(JarvisTypography.pageTitle)

                ForEach(ResumeSection.allCases) { section in
                    accordionSection(section)
                }
            }
            .padding(16)
        }
        .background(Color.jarvisPanel.opacity(0.34))
        .sheet(isPresented: $isProjectGenerationPromptPresented) {
            ResumeProjectGenerationSheet(
                domain: $projectGenerationDomain,
                onCancel: { isProjectGenerationPromptPresented = false },
                onGenerate: {
                    let domain = projectGenerationDomain.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !domain.isEmpty else { return }
                    isProjectGenerationPromptPresented = false
                    generate(.projects, projectDomain: domain)
                }
            )
        }
    }

    private var canStartAIRequest: Bool {
        !app.resumeWorkspace.isGenerating
    }

    private var aiGenerationDisabledMessage: String {
        let missingFields = draft.basicInfo.missingRequiredFieldsForAI
        guard !missingFields.isEmpty else { return "生成一条内容" }
        return "请先完成基本信息：\(missingFields.joined(separator: "、"))"
    }

    private func accordionSection(_ section: ResumeSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(JarvisMotion.content) {
                    expandedSection = expandedSection == section ? nil : section
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: section.icon)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 20)
                    Text(section.title)
                        .font(JarvisTypography.controlEmphasis)
                    Spacer(minLength: 0)
                    Image(systemName: expandedSection == section ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(expandedSection == section ? Color.accentColor : Color.primary)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expandedSection == section ? "已展开" : "已收起")

            if expandedSection == section {
                sectionEditor(for: section)
                    .padding(12)
            }
        }
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    expandedSection == section ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06),
                    lineWidth: 0.75
                )
        }
    }

    @ViewBuilder
    private func sectionEditor(for section: ResumeSection) -> some View {
        switch section {
        case .basicInfo:
            ResumeBasicInfoEditor(draft: $draft)
        case .education:
            ResumeEducationEditor(
                draft: $draft,
                isGenerating: app.resumeWorkspace.generatingSection == .education,
                canGenerate: canStartAIRequest,
                disabledReason: aiGenerationDisabledMessage,
                onGenerate: { generate(.education) }
            )
        case .experience:
            ResumeExperienceEditor(
                draft: $draft,
                isGenerating: app.resumeWorkspace.generatingSection == .experience,
                canGenerate: canStartAIRequest,
                disabledReason: aiGenerationDisabledMessage,
                onGenerate: { generate(.experience) }
            )
        case .skills:
            ResumeSkillsEditor(
                draft: $draft,
                isGenerating: app.resumeWorkspace.generatingSection == .skills,
                canGenerate: canStartAIRequest,
                disabledReason: aiGenerationDisabledMessage,
                onGenerate: { generate(.skills) }
            )
        case .projects:
            ResumeProjectsEditor(
                draft: $draft,
                isGenerating: app.resumeWorkspace.generatingSection == .projects,
                canGenerate: canStartAIRequest,
                disabledReason: aiGenerationDisabledMessage,
                onGenerate: showProjectGenerationPrompt
            )
        }
    }

    private func generate(_ section: ResumeSection, projectDomain: String? = nil) {
        guard canStartAIRequest, section != .basicInfo else { return }
        guard draft.basicInfo.isReadyForAIGeneration else {
            app.showToast(aiGenerationDisabledMessage)
            return
        }
        let documentID = draft.id
        let snapshot = draft
        let configuration = AIAPIConfiguration.load()
        let workspace = app.resumeWorkspace

        workspace.startGeneration(for: section) {
            do {
                let service = ResumeAIService()
                let content = try await generateContent(
                    for: section,
                    service: service,
                    document: snapshot,
                    configuration: configuration,
                    projectDomain: projectDomain
                )
                guard !Task.isCancelled, draft.id == documentID else { return }
                append(content)
                app.showToast("已生成 1 条\(section.title)")
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, draft.id == documentID else { return }
                app.showToast(error.localizedDescription)
            }
        }
    }

    private func generateContent(
        for section: ResumeSection,
        service: ResumeAIService,
        document: ResumeDocument,
        configuration: AIAPIConfiguration,
        projectDomain: String?
    ) async throws -> ResumeGeneratedContent {
        switch section {
        case .basicInfo:
            throw AIAPIError.invalidSchema(context: "基本信息生成", reason: "基本信息不支持 AI 生成")
        case .education:
            return try await .education(service.generateEducation(for: document, configuration: configuration))
        case .experience:
            return try await .experience(service.generateExperience(for: document, configuration: configuration))
        case .skills:
            return try await .skill(service.generateSkill(for: document, configuration: configuration))
        case .projects:
            guard let projectDomain else {
                throw AIAPIError.invalidSchema(context: "项目经历生成", reason: "缺少生成领域")
            }
            return try await .project(
                service.generateProject(
                    for: document,
                    domain: projectDomain,
                    configuration: configuration
                )
            )
        }
    }

    private func append(_ content: ResumeGeneratedContent) {
        switch content {
        case let .education(item):
            draft.education.append(item)
        case let .experience(item):
            draft.experience.append(item)
        case let .skill(value):
            draft.skills.append(value)
        case let .project(item):
            draft.projects.append(item)
        }
    }

    private func showProjectGenerationPrompt() {
        guard draft.basicInfo.isReadyForAIGeneration else {
            app.showToast(aiGenerationDisabledMessage)
            return
        }
        projectGenerationDomain = ""
        isProjectGenerationPromptPresented = true
    }
}

private struct ResumeAIGenerateButton: View {
    let isGenerating: Bool
    let isEnabled: Bool
    let disabledReason: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(isGenerating ? "生成中…" : "AI 生成", systemImage: "sparkles")
        }
        .buttonStyle(ResumeAddButtonStyle(tint: .accentColor))
        .disabled(!isEnabled)
        .help(helpText)
        .accessibilityHint(helpText)
    }

    private var helpText: String {
        disabledReason.hasPrefix("请先完成") ? disabledReason : "生成一条\(title)"
    }
}

private struct ResumeProjectGenerationSheet: View {
    @Binding var domain: String
    let onCancel: () -> Void
    let onGenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("生成项目经历")
                .font(JarvisTypography.cardTitle)

            TextField("例如：电商平台、棋牌手游", text: $domain)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onGenerate)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("取消", action: onCancel)
                    .buttonStyle(ResumeAddButtonStyle())
                Button("生成", action: onGenerate)
                    .buttonStyle(ResumeAddButtonStyle(tint: .accentColor))
                    .disabled(domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

private struct ResumeBasicInfoEditor: View {
    @Binding var draft: ResumeDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResumeTextField(title: "姓名", placeholder: "请输入姓名", text: $draft.basicInfo.name)
            ResumeTextField(title: "职位标题", placeholder: "请输入职位标题", text: $draft.basicInfo.headline)
            ResumeTextField(title: "所在地", placeholder: "请输入所在地", text: $draft.basicInfo.location)
            ResumeTextField(title: "联系方式", placeholder: "请输入联系方式", text: $draft.basicInfo.email)
            HStack(spacing: 8) {
                ResumeTextField(title: "岗位状态", placeholder: "请输入岗位状态", text: $draft.basicInfo.jobStatus)
                ResumeTextField(title: "工作年限", placeholder: "请输入工作年限", text: $draft.basicInfo.workYears)
            }
        }
    }
}

private struct ResumeEducationEditor: View {
    @Binding var draft: ResumeDocument
    let isGenerating: Bool
    let canGenerate: Bool
    let disabledReason: String
    let onGenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach($draft.education) { $item in
                VStack(alignment: .leading, spacing: 9) {
                    ResumeItemHeader(title: "教育经历", onDelete: { deleteEducation(id: item.id) })
                    ResumeTextField(title: "学校", placeholder: "请输入学校", text: $item.school)
                    HStack(spacing: 8) {
                        ResumeTextField(title: "学历", placeholder: "请输入学历", text: $item.degree)
                        ResumeTextField(title: "专业", placeholder: "请输入专业", text: $item.major)
                    }
                    ResumeTextField(title: "时间", placeholder: "请输入时间", text: $item.period)
                }
                .padding(11)
                .jarvisGlass(cornerRadius: 11, interactive: false)
            }

            HStack(spacing: 8) {
                Button {
                    draft.education.append(.blank)
                } label: {
                    Label("添加教育经历", systemImage: "plus")
                }
                .buttonStyle(ResumeAddButtonStyle())

                ResumeAIGenerateButton(
                    isGenerating: isGenerating,
                    isEnabled: canGenerate,
                    disabledReason: disabledReason,
                    title: "教育经历",
                    action: onGenerate
                )
            }
        }
    }

    private func deleteEducation(id: UUID) {
        draft.education.removeAll { $0.id == id }
    }
}

private struct ResumeExperienceEditor: View {
    @Binding var draft: ResumeDocument
    let isGenerating: Bool
    let canGenerate: Bool
    let disabledReason: String
    let onGenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach($draft.experience) { $item in
                VStack(alignment: .leading, spacing: 9) {
                    ResumeItemHeader(title: "工作经历", onDelete: { deleteExperience(id: item.id) })
                    HStack(spacing: 8) {
                        ResumeTextField(title: "公司", placeholder: "请输入公司", text: $item.company)
                        ResumeTextField(title: "职位", placeholder: "请输入职位", text: $item.role)
                    }
                    ResumeTextField(title: "时间", placeholder: "请输入时间", text: $item.period)
                }
                .padding(11)
                .jarvisGlass(cornerRadius: 11, interactive: false)
            }

            HStack(spacing: 8) {
                Button {
                    draft.experience.append(.blank)
                } label: {
                    Label("添加工作经历", systemImage: "plus")
                }
                .buttonStyle(ResumeAddButtonStyle())

                ResumeAIGenerateButton(
                    isGenerating: isGenerating,
                    isEnabled: canGenerate,
                    disabledReason: disabledReason,
                    title: "工作经历",
                    action: onGenerate
                )
            }
        }
    }

    private func deleteExperience(id: UUID) {
        draft.experience.removeAll { $0.id == id }
    }
}

private struct ResumeSkillsEditor: View {
    @Binding var draft: ResumeDocument
    let isGenerating: Bool
    let canGenerate: Bool
    let disabledReason: String
    let onGenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(draft.skills.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    ResumeTextField(title: "技能", placeholder: "请输入技能", text: skillBinding(index: index))
                    Button {
                        guard draft.skills.indices.contains(index) else { return }
                        draft.skills.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red.opacity(0.78))
                    }
                    .buttonStyle(.plain)
                    .help("删除技能")
                    .padding(.top, 18)
                }
            }

            HStack(spacing: 8) {
                Button {
                    draft.skills.append("")
                } label: {
                    Label("添加技能", systemImage: "plus")
                }
                .buttonStyle(ResumeAddButtonStyle())

                ResumeAIGenerateButton(
                    isGenerating: isGenerating,
                    isEnabled: canGenerate,
                    disabledReason: disabledReason,
                    title: "技能",
                    action: onGenerate
                )
            }
        }
    }

    private func skillBinding(index: Int) -> Binding<String> {
        Binding(
            get: { draft.skills.indices.contains(index) ? draft.skills[index] : "" },
            set: { newValue in
                guard draft.skills.indices.contains(index) else { return }
                draft.skills[index] = newValue
            }
        )
    }
}

private struct ResumeProjectsEditor: View {
    @Binding var draft: ResumeDocument
    let isGenerating: Bool
    let canGenerate: Bool
    let disabledReason: String
    let onGenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach($draft.projects) { $project in
                VStack(alignment: .leading, spacing: 9) {
                    ResumeItemHeader(title: "项目经历", onDelete: { deleteProject(id: project.id) })
                    HStack(spacing: 8) {
                        ResumeTextField(title: "真实项目名称", placeholder: "请输入真实项目名称", text: $project.name)
                        ResumeTextField(title: "时间", placeholder: "请输入时间", text: $project.period)
                    }
                    ResumeTextEditor(title: "项目简介", placeholder: "请输入项目简介，约80字", text: $project.summary)
                    ResumeBulletEditor(title: "项目要点", bullets: $project.bullets)
                }
                .padding(11)
                .jarvisGlass(cornerRadius: 11, interactive: false)
            }

            HStack(spacing: 8) {
                Button {
                    draft.projects.append(.blank)
                } label: {
                    Label("添加项目经历", systemImage: "plus")
                }
                .buttonStyle(ResumeAddButtonStyle())

                ResumeAIGenerateButton(
                    isGenerating: isGenerating,
                    isEnabled: canGenerate,
                    disabledReason: disabledReason,
                    title: "项目经历",
                    action: onGenerate
                )
            }
        }
    }

    private func deleteProject(id: UUID) {
        draft.projects.removeAll { $0.id == id }
    }
}

private struct ResumeBulletEditor: View {
    let title: String
    @Binding var bullets: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(JarvisTypography.captionEmphasis)
                .foregroundStyle(Color.jarvisTextSecondary)

            ForEach(bullets.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 8) {
                    ResumeTextField(
                        title: "要点 \(index + 1)",
                        placeholder: "请输入\(title)",
                        text: bulletBinding(index: index)
                    )
                    Button {
                        guard bullets.indices.contains(index) else { return }
                        bullets.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(0.70))
                    }
                    .buttonStyle(.plain)
                    .help("删除要点")
                    .padding(.top, 18)
                }
            }

            Button {
                bullets.append("")
            } label: {
                Label("添加要点", systemImage: "plus")
                    .font(JarvisTypography.control)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    private func bulletBinding(index: Int) -> Binding<String> {
        Binding(
            get: { bullets.indices.contains(index) ? bullets[index] : "" },
            set: { newValue in
                guard bullets.indices.contains(index) else { return }
                bullets[index] = newValue
            }
        )
    }
}

private struct ResumeItemHeader: View {
    let title: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(JarvisTypography.controlEmphasis)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.78))
            }
            .buttonStyle(.plain)
            .help("删除\(title)")
        }
    }
}

private struct ResumeTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(JarvisTypography.captionEmphasis)
                .foregroundStyle(Color.jarvisTextSecondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(JarvisTypography.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ResumeTextEditor: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(JarvisTypography.captionEmphasis)
                .foregroundStyle(Color.jarvisTextSecondary)
            TextField(placeholder, text: limitedTextBinding, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(JarvisTypography.secondary)
                .lineLimit(3 ... 4)
                .frame(minHeight: 64, alignment: .top)
        }
    }

    private var limitedTextBinding: Binding<String> {
        Binding(
            get: { text },
            set: { text = String($0.prefix(120)) }
        )
    }
}
