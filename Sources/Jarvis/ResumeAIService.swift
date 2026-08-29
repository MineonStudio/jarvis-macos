import Foundation

enum ResumeGeneratedContent: Sendable {
    case education(ResumeEducation)
    case experience(ResumeExperience)
    case skill(String)
    case project(ResumeProject)
}

struct ResumeAIService: Sendable {
    private let apiClient: any AITextCompletionAPI

    init(apiClient: any AITextCompletionAPI = OpenAICompatibleAPIClient()) {
        self.apiClient = apiClient
    }

    func generateEducation(
        for document: ResumeDocument,
        configuration: AIAPIConfiguration
    ) async throws -> ResumeEducation {
        guard case let .education(item) = try await generate(
            section: .education,
            document: document,
            configuration: configuration
        ) else {
            throw AIAPIError.invalidSchema(context: "教育经历生成", reason: "返回类型错误")
        }
        return item
    }

    func generateExperience(
        for document: ResumeDocument,
        configuration: AIAPIConfiguration
    ) async throws -> ResumeExperience {
        guard case let .experience(item) = try await generate(
            section: .experience,
            document: document,
            configuration: configuration
        ) else {
            throw AIAPIError.invalidSchema(context: "工作经历生成", reason: "返回类型错误")
        }
        return item
    }

    func generateSkill(
        for document: ResumeDocument,
        configuration: AIAPIConfiguration
    ) async throws -> String {
        guard case let .skill(value) = try await generate(
            section: .skills,
            document: document,
            configuration: configuration
        ) else {
            throw AIAPIError.invalidSchema(context: "技能生成", reason: "返回类型错误")
        }
        return value
    }

    func generateProject(
        for document: ResumeDocument,
        domain: String,
        configuration: AIAPIConfiguration
    ) async throws -> ResumeProject {
        let normalizedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isConcrete(normalizedDomain) else {
            throw AIAPIError.invalidSchema(context: "项目经历生成", reason: "请先填写生成领域")
        }
        guard case let .project(item) = try await generate(
            section: .projects,
            document: document,
            configuration: configuration,
            generationFocus: normalizedDomain
        ) else {
            throw AIAPIError.invalidSchema(context: "项目经历生成", reason: "返回类型错误")
        }
        return item
    }

    private func generate(
        section: ResumeSection,
        document: ResumeDocument,
        configuration: AIAPIConfiguration,
        generationFocus: String? = nil
    ) async throws -> ResumeGeneratedContent {
        guard document.basicInfo.isReadyForAIGeneration else {
            let missingFields = document.basicInfo.missingRequiredFieldsForAI.joined(separator: "、")
            throw AIAPIError.invalidSchema(
                context: "\(section.title)生成",
                reason: "请先完成基本信息：\(missingFields)"
            )
        }
        let existingSignatures = Set(signatures(for: section, in: document))
        var rejectedSignatures: Set<String> = []
        var lastEmptyError: AIAPIError?

        for _ in 0 ..< 3 {
            let content = try await apiClient.complete(
                systemPrompt: systemPrompt(for: section),
                userPrompt: userPrompt(
                    for: section,
                    document: document,
                    rejectedSignatures: rejectedSignatures,
                    generationFocus: generationFocus
                ),
                configuration: configuration
            )
            let candidate = try decode(section, from: content, document: document)

            guard isUsable(candidate) else {
                lastEmptyError = .emptyGeneratedContent(context: section.title)
                continue
            }

            let candidateSignature = signature(for: candidate)
            guard !existingSignatures.contains(candidateSignature),
                  !rejectedSignatures.contains(candidateSignature)
            else {
                rejectedSignatures.insert(candidateSignature)
                continue
            }
            return candidate
        }

        if let lastEmptyError {
            throw lastEmptyError
        }
        throw AIAPIError.duplicateGeneratedContent(context: section.title)
    }

    private func systemPrompt(for section: ResumeSection) -> String {
        let contract = switch section {
        case .basicInfo:
            "不支持生成基本信息"
        case .education:
            #"返回 {"school":"学校","degree":"学历","major":"专业","period":"时间"}"#
        case .experience:
            #"返回 {"company":"公司","role":"职位","period":"时间"}"#
        case .skills:
            #"返回 {"skill":"技能名称"}"#
        case .projects:
            #"返回 {"name":"真实项目名称","period":"时间","summary":"约80字的项目简介","bullets":["项目要点"]}"#
        }

        return """
        你是简历表单内容助手。本次只生成一条新的\(section.title)表单内容，不要生成其他模块，不要返回数组。
        只能返回 JSON 对象，不要 Markdown 代码围栏，不要解释文字。格式：\(contract)。
        所有字符串都必须有具体内容，不要返回空字符串、示例、待补充或待核实。
        参考当前简历内容生成合理的候选条目，但不要重复已有条目或本次已经拒绝的条目。
        教育经历时间必须与工作年限衔接，并按学历合理反推毕业前的教育周期。
        项目经历必须使用真实、具体的项目名称，不要使用“项目名称”“某某平台”等占位名称。
        项目简介控制在约80字，说明项目目标、服务对象和核心能力，内容要具体。
        """
    }

    private func userPrompt(
        for section: ResumeSection,
        document: ResumeDocument,
        rejectedSignatures: Set<String>,
        generationFocus: String?
    ) -> String {
        let basicInfo = document.basicInfo
        let role = basicInfo.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let workPeriod = ResumeCareerTimeline.period(for: basicInfo.workYears) ?? "无法根据工作年限推算"
        let graduationYear = ResumeCareerTimeline.graduationYear(for: basicInfo.workYears)
            .map(String.init) ?? "无法根据工作年限推算"
        let rejected = rejectedSignatures.isEmpty
            ? "无"
            : rejectedSignatures.joined(separator: "\n")
        return """
        用于岗位匹配的基本信息：
        职位标题：\(role)
        所在地：\(basicInfo.location)
        岗位状态：\(basicInfo.jobStatus)
        工作年限：\(basicInfo.workYears)
        推算工作时间：\(workPeriod)
        教育经历毕业年份基准：\(graduationYear)

        当前简历已有\(section.title)：
        \(existingText(for: section, in: document))

        本次请求中已经拒绝的重复内容：
        \(rejected)

        \(generationFocus.map { "目标项目领域：\($0)" } ?? "")
        工作经历必须与职位标题匹配，时间必须使用推算工作时间“\(workPeriod)”；教育经历必须围绕毕业年份基准并按学历匹配；掌握技能和项目经历必须围绕职位标题和工作年限生成。
        只生成一条新的\(section.title)，并严格返回 JSON 对象。
        """
    }

    private func existingText(for section: ResumeSection, in document: ResumeDocument) -> String {
        switch section {
        case .basicInfo:
            "无"
        case .education:
            document.education.filter(\.hasContent).map {
                [$0.school, $0.degree, $0.major, $0.period].joined(separator: " / ")
            }.joined(separator: "\n").ifEmpty("无")
        case .experience:
            document.experience.filter(\.hasContent).map {
                [$0.company, $0.role, $0.period].joined(separator: " / ")
            }.joined(separator: "\n").ifEmpty("无")
        case .skills:
            document.skills.filter(isConcrete).joined(separator: "、").ifEmpty("无")
        case .projects:
            document.projects.filter(\.hasContent).map {
                [$0.name, $0.period, $0.summary, $0.bullets.joined(separator: "；")].joined(separator: " / ")
            }.joined(separator: "\n").ifEmpty("无")
        }
    }

    private func decode(
        _ section: ResumeSection,
        from content: String,
        document: ResumeDocument
    ) throws -> ResumeGeneratedContent {
        let context = "\(section.title)生成"
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            throw AIAPIError.invalidJSON(context: context, reason: "返回内容为空")
        }
        guard !trimmedContent.hasPrefix(String(repeating: "\u{60}", count: 3)) else {
            throw AIAPIError.invalidJSON(context: context, reason: "返回了 Markdown 代码围栏，请仅返回 JSON")
        }
        guard let data = trimmedContent.data(using: .utf8) else {
            throw AIAPIError.invalidJSON(context: context, reason: "返回内容无法转换为 UTF-8")
        }

        do {
            switch section {
            case .basicInfo:
                throw AIAPIError.invalidSchema(context: context, reason: "基本信息不支持 AI 生成")
            case .education:
                let response = try JSONDecoder().decode(EducationResponse.self, from: data)
                return .education(
                    ResumeEducation(
                        school: response.school,
                        degree: response.degree,
                        major: response.major,
                        period: ResumeCareerTimeline.educationPeriod(
                            for: document.basicInfo.workYears,
                            degree: response.degree
                        ) ?? response.period
                    )
                )
            case .experience:
                let response = try JSONDecoder().decode(ExperienceResponse.self, from: data)
                return .experience(
                    ResumeExperience(
                        company: response.company,
                        role: response.role,
                        period: ResumeCareerTimeline.period(for: document.basicInfo.workYears) ?? response.period
                    )
                )
            case .skills:
                let response = try JSONDecoder().decode(SkillResponse.self, from: data)
                return .skill(response.skill)
            case .projects:
                let response = try JSONDecoder().decode(ProjectResponse.self, from: data)
                return .project(
                    ResumeProject(
                        name: response.name,
                        period: response.period,
                        summary: response.summary,
                        bullets: response.bullets
                    )
                )
            }
        } catch let error as AIAPIError {
            throw error
        } catch {
            throw AIAPIError.decodingError(error, context: context)
        }
    }

    private func isUsable(_ content: ResumeGeneratedContent) -> Bool {
        switch content {
        case let .education(item):
            [item.school, item.degree, item.major, item.period].allSatisfy(isConcrete)
        case let .experience(item):
            [item.company, item.role, item.period].allSatisfy(isConcrete)
        case let .skill(value):
            isConcrete(value)
        case let .project(item):
            isConcrete(item.name)
                && isConcrete(item.period)
                && isConcrete(item.summary)
                && !item.bullets.isEmpty
                && item.bullets.allSatisfy(isConcrete)
        }
    }

    private func signatures(for section: ResumeSection, in document: ResumeDocument) -> [String] {
        switch section {
        case .basicInfo:
            []
        case .education:
            document.education.filter(\.hasContent).map {
                signature(values: [$0.school, $0.degree, $0.major])
            }
        case .experience:
            document.experience.filter(\.hasContent).map {
                signature(values: [$0.company, $0.role, $0.period])
            }
        case .skills:
            document.skills.filter(isConcrete).map { signature(values: [$0]) }
        case .projects:
            document.projects.filter(\.hasContent).map {
                signature(values: [$0.name, $0.period])
            }
        }
    }

    private func signature(for content: ResumeGeneratedContent) -> String {
        switch content {
        case let .education(item):
            signature(values: [item.school, item.degree, item.major])
        case let .experience(item):
            signature(values: [item.company, item.role, item.period])
        case let .skill(value):
            signature(values: [value])
        case let .project(item):
            signature(values: [item.name, item.period])
        }
    }

    private func signature(values: [String]) -> String {
        values.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
                .lowercased()
        }.joined(separator: "\u{1F}")
    }

    private func isConcrete(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && !["示例", "待核实", "待补充", "候选人", "待填写", "example.com", "candidate@"]
            .contains(where: trimmed.localizedCaseInsensitiveContains)
    }

    private struct EducationResponse: Decodable {
        let school: String
        let degree: String
        let major: String
        let period: String
    }

    private struct ExperienceResponse: Decodable {
        let company: String
        let role: String
        let period: String
    }

    private struct SkillResponse: Decodable {
        let skill: String
    }

    private struct ProjectResponse: Decodable {
        let name: String
        let period: String
        let summary: String
        let bullets: [String]
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
