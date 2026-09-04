import AppKit
@testable import Jarvis
import PDFKit
import XCTest

@MainActor
final class ResumeTests: XCTestCase {
    func testResumeSkillIsAvailableInTheSkillLibrary() {
        XCTAssertTrue(SkillID.allCases.contains(.resume))
        XCTAssertEqual(SkillID.resume.navigationTitle, "简历制作")
        XCTAssertEqual(SkillID.resume.icon, "doc.text.magnifyingglass")
        XCTAssertEqual(ResumeSection.allCases, [.basicInfo, .education, .experience, .skills, .projects])
    }

    func testResumeTemplatesKeepModernMinimalAsTheDefault() {
        XCTAssertEqual(ResumeTemplate.defaultTemplate, .minimal)
        XCTAssertEqual(
            ResumeTemplate.allCases,
            [.minimal, .editorial, .timeline]
        )
        XCTAssertEqual(ResumeDocument.blank().template, .minimal)
        XCTAssertEqual(ResumeTemplate.allCases.map(\.title), ["现代极简", "编辑风格", "时间轴"])
    }

    func testTemplateSelectionIsShownOnlyUntilAChoiceIsMade() {
        let workspace = ResumeWorkspace()

        XCTAssertTrue(workspace.needsTemplateSelection)

        workspace.chooseTemplate(.timeline)

        XCTAssertFalse(workspace.needsTemplateSelection)
        XCTAssertEqual(workspace.document.template, .timeline)

        workspace.beginNewResume()

        XCTAssertTrue(workspace.needsTemplateSelection)
        XCTAssertEqual(workspace.document.template, .minimal)
        XCTAssertFalse(workspace.document.hasContent)
    }

    func testResumeZoomScaleSupportsOnePercentStepsAndCustomBounds() {
        XCTAssertEqual(ResumeZoomScale.clampedPercentage(100), 100)
        XCTAssertEqual(ResumeZoomScale.clampedPercentage(24), 25)
        XCTAssertEqual(ResumeZoomScale.clampedPercentage(201), 200)
        XCTAssertEqual(ResumeZoomScale.percentage(from: "137", fallback: 100), 137)
        XCTAssertEqual(ResumeZoomScale.percentage(from: "无效", fallback: 100), 100)
    }

    func testResumeAIGenerationRequiresCompleteBasicInfo() async throws {
        let api = SequenceResumeAIAPI(responses: [#"{"skill":"接口测试"}"#])
        let service = ResumeAIService(apiClient: api)

        do {
            _ = try await service.generateSkills(for: .blank(), configuration: testAIConfiguration)
            XCTFail("基本信息未完成时不应调用 AI")
        } catch let error as AIAPIError {
            XCTAssertEqual(
                error,
                .invalidSchema(
                    context: "掌握技能生成",
                    reason: "请先完成基本信息：姓名、职位标题、所在地、联系方式、岗位状态、工作年限"
                )
            )
            XCTAssertEqual(api.callCount, 0)
        }
    }

    func testResumeCareerTimelineStartsSixYearsAgo() {
        let currentYear = Calendar.current.component(.year, from: Date())

        XCTAssertEqual(ResumeCareerTimeline.years(from: "6年经验"), 6)
        XCTAssertEqual(ResumeCareerTimeline.period(for: "6年经验"), "\(currentYear - 6) — 至今")
        XCTAssertEqual(
            ResumeCareerTimeline.educationPeriod(for: "6年经验", degree: "硕士"),
            "\(currentYear - 9) — \(currentYear - 6)"
        )
    }

    func testBlankResumeHasNoSampleContent() {
        let document = ResumeDocument.blank()

        XCTAssertEqual(document.title, "未命名简历")
        XCTAssertFalse(document.hasContent)
        XCTAssertTrue(document.basicInfo.isEmpty)
        XCTAssertTrue(document.education.isEmpty)
        XCTAssertTrue(document.experience.isEmpty)
        XCTAssertTrue(document.skills.isEmpty)
        XCTAssertTrue(document.projects.isEmpty)
    }

    func testNewResumeCreatesAnIndependentBlankDocumentWithoutSaveGate() {
        let existing = makeDocument()
        let workspace = ResumeWorkspace(document: existing)
        workspace.markSaved(at: Date(timeIntervalSince1970: 100))
        let oldID = workspace.document.id

        workspace.beginNewResume()

        XCTAssertNotEqual(workspace.document.id, oldID)
        XCTAssertFalse(workspace.document.hasContent)
        XCTAssertFalse(workspace.isSaved)
        XCTAssertNil(workspace.lastSavedAt)
        XCTAssertTrue(workspace.needsTemplateSelection)
        XCTAssertEqual(workspace.document.template, .minimal)
        XCTAssertFalse(workspace.requiresSaveBeforeNewResume)
    }

    func testNewResumeRequiresAChoiceWhenCurrentResumeHasUnsavedContent() {
        let workspace = ResumeWorkspace(document: makeDocument())

        XCTAssertFalse(workspace.isSaved)
        XCTAssertTrue(workspace.requiresSaveBeforeNewResume)

        workspace.markSaved(at: Date(timeIntervalSince1970: 100))

        XCTAssertFalse(workspace.requiresSaveBeforeNewResume)
    }

    func testEditingAfterExplicitSaveMakesDocumentUnsaved() {
        let workspace = ResumeWorkspace(document: makeDocument())
        workspace.markSaved(at: Date(timeIntervalSince1970: 100))
        XCTAssertTrue(workspace.isSaved)

        workspace.document.title = "新的文件名"

        XCTAssertFalse(workspace.isSaved)
    }

    func testSavingUsesTheSavePanelFileNameAsTheDocumentTitle() {
        let workspace = ResumeWorkspace(document: makeDocument())
        XCTAssertEqual(workspace.document.title, "产品经理简历")

        workspace.markSaved(to: URL(fileURLWithPath: "/tmp/林知远-产品经理.pdf"))

        XCTAssertEqual(workspace.document.title, "林知远-产品经理")
        XCTAssertTrue(workspace.isSaved)
        XCTAssertEqual(
            ResumeSavedFile.documentTitle(from: URL(fileURLWithPath: "/tmp/未命名简历.md")),
            "未命名简历"
        )
        XCTAssertEqual(
            ResumeSavedFile.documentTitle(from: URL(fileURLWithPath: "/tmp/林知远-产品经理.backup.json")),
            "林知远-产品经理.backup"
        )
    }

    func testDocumentCodecRoundTripsTheNewSchema() throws {
        let document = makeDocument()
        var templatedDocument = document
        templatedDocument.template = .editorial
        let data = try ResumeDocumentCodec.encodedData(for: document)
        let templatedData = try ResumeDocumentCodec.encodedData(for: templatedDocument)

        let exportedRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(exportedRoot["template"])
        XCTAssertEqual(try contentMatchingTemplate(ResumeDocumentCodec.decode(data), template: document.template), document)
        XCTAssertEqual(
            try contentMatchingTemplate(ResumeDocumentCodec.decode(templatedData), template: .editorial),
            templatedDocument
        )

        var legacyRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacyRoot["template"] = "sidebar"
        let legacyData = try JSONSerialization.data(withJSONObject: legacyRoot)
        XCTAssertEqual(try ResumeDocumentCodec.decode(legacyData).template, .minimal)
    }

    func testJSONImportKeepsTheCurrentTemplateAndAcceptsUnknownTemplates() throws {
        let workspace = ResumeWorkspace(document: makeDocument())
        workspace.chooseTemplate(.timeline)

        let data = try ResumeDocumentCodec.encodedData(for: makeDocument())
        try workspace.replace(with: ResumeDocumentCodec.decode(data))
        XCTAssertEqual(workspace.document.template, .timeline)
        XCTAssertEqual(workspace.document.basicInfo.name, "林知远")

        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        root["template"] = "unknown-layout"
        let unknownData = try JSONSerialization.data(withJSONObject: root)
        XCTAssertEqual(try ResumeDocumentCodec.decode(unknownData).template, .minimal)

        for template in ResumeTemplate.allCases {
            var document = makeDocument()
            document.template = template
            XCTAssertNoThrow(try ResumeExportService.data(for: document, format: .json))
            XCTAssertNoThrow(try ResumeExportService.data(for: document, format: .markdown))
            XCTAssertNoThrow(try ResumeExportService.data(for: document, format: .rtf))
        }
    }

    func testPDFExportSupportsEveryResumeTemplate() throws {
        for template in ResumeTemplate.allCases {
            var document = makeDocument()
            document.template = template

            let data = try ResumeExportService.data(for: document, format: .pdf)
            let pdf = try XCTUnwrap(PDFDocument(data: data))

            XCTAssertGreaterThan(pdf.pageCount, 0, "(template.title) 模板应至少生成一页")
            XCTAssertGreaterThan(data.count, 2000, "(template.title) 模板不应导出空 PDF")
        }
    }

    func testDocumentCodecRejectsUnknownAndOldShapeFields() throws {
        let data = try ResumeDocumentCodec.encodedData(for: makeDocument())
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        root["targetRole"] = "旧目标岗位"
        let oldData = try JSONSerialization.data(withJSONObject: root)

        XCTAssertThrowsError(try ResumeDocumentCodec.decode(oldData))
    }

    func testDocumentCodecRejectsSingletonSections() throws {
        let data = try ResumeDocumentCodec.encodedData(for: makeDocument())
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        root["education"] = ["school": "学校", "degree": "本科", "major": "专业", "period": "时间"]
        let singletonData = try JSONSerialization.data(withJSONObject: root)

        XCTAssertThrowsError(try ResumeDocumentCodec.decode(singletonData))
    }

    func testPDFExportContainsResumeContent() throws {
        let data = try ResumeExportService.data(for: makeDocument(), format: .pdf)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(pdf.page(at: 0))
        let thumbnail = page.thumbnail(of: CGSize(width: 310, height: 438), for: .mediaBox)
        let bitmap = try XCTUnwrap(thumbnail.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))

        XCTAssertGreaterThan(pdf.pageCount, 0)
        XCTAssertGreaterThan(data.count, 2000)
        XCTAssertTrue(hasDarkPixel(in: bitmap))
    }

    func testPDFExportPaginatesLongResume() throws {
        var document = makeDocument()
        document.projects = (0 ..< 30).map { index in
            ResumeProject(
                name: "真实项目 \(index + 1)",
                period: "202\(index % 10) — 202\(index % 10 + 1)",
                bullets: ["负责项目规划、研发协作与上线迭代"]
            )
        }

        let data = try ResumeExportService.data(for: document, format: .pdf)
        let pdf = try XCTUnwrap(PDFDocument(data: data))

        XCTAssertGreaterThan(pdf.pageCount, 1)
    }

    func testMarkdownAndPlainTextExportIncludeAllExperienceSections() {
        let document = makeDocument()
        let markdown = ResumeTextFormatter.markdown(for: document)
        let plainText = ResumeTextFormatter.plainText(for: document)

        XCTAssertTrue(markdown.contains("## 教育经历"))
        XCTAssertTrue(markdown.contains("## 工作经历"))
        XCTAssertTrue(markdown.contains("## 掌握技能"))
        XCTAssertTrue(markdown.contains("## 项目经历"))
        XCTAssertFalse(markdown.contains("负责团队协作"))
        XCTAssertTrue(markdown.contains("面向企业客户的智能工单协作平台"))
        XCTAssertTrue(markdown.contains("- 推动项目上线并持续迭代"))
        XCTAssertFalse(plainText.contains("## "))
        XCTAssertFalse(plainText.contains("# "))
        XCTAssertTrue(plainText.contains("推动项目上线并持续迭代"))
    }

    func testResumeAIServiceGeneratesOneItemAndRetriesARepeatedExperience() async throws {
        let api = SequenceResumeAIAPI(responses: [
            #"{"company":"星云科技","role":"产品经理","period":"2021 — 至今"}"#,
            #"{"company":"远航软件","role":"高级产品经理","period":"2019 — 2021"}"#
        ])
        let service = ResumeAIService(apiClient: api)

        let generated = try await service.generateExperience(
            for: makeDocument(),
            configuration: testAIConfiguration
        )

        XCTAssertEqual(generated.company, "远航软件")
        XCTAssertEqual(generated.period, "2019 — 2021")
        XCTAssertEqual(api.callCount, 2)
    }

    func testResumeAIServiceGeneratesOneContentObjectForEachManualSection() async throws {
        let api = SequenceResumeAIAPI(responses: [
            #"{"school":"复旦大学","degree":"硕士","major":"软件工程","period":"2017 — 2019"}"#,
            #"{"company":"远航软件","role":"高级产品经理","period":"2019 — 2021"}"#,
            #"{"skills":["用户研究","接口测试","性能测试","自动化测试","缺陷管理","测试计划","用例设计","回归测试","质量度量","持续集成"]}"#,
            #"{"name":"客户增长平台","period":"2020 — 2021","summary":"面向企业客户的增长实验与运营分析平台，支持策略配置、效果追踪和数据复盘。","bullets":["搭建增长实验闭环"]}"#
        ])
        let service = ResumeAIService(apiClient: api)
        let document = makeAIGenerationDocument()

        let education = try await service.generateEducation(for: document, configuration: testAIConfiguration)
        let experience = try await service.generateExperience(for: document, configuration: testAIConfiguration)
        let skills = try await service.generateSkills(for: document, configuration: testAIConfiguration)
        let project = try await service.generateProject(
            for: document,
            domain: "软件平台",
            configuration: testAIConfiguration
        )

        XCTAssertEqual(education.school, "复旦大学")
        XCTAssertEqual(education.period, "2017 — 2019")
        XCTAssertEqual(experience.company, "远航软件")
        XCTAssertEqual(
            skills,
            ["用户研究", "接口测试", "性能测试", "自动化测试", "缺陷管理", "测试计划", "用例设计", "回归测试", "质量度量", "持续集成"]
        )
        XCTAssertEqual(project.name, "客户增长平台")
        XCTAssertEqual(project.summary, "面向企业客户的增长实验与运营分析平台，支持策略配置、效果追踪和数据复盘。")
        XCTAssertEqual(api.callCount, 4)
    }

    func testResumeAIServiceGeneratesTenSkillsAndDropsExistingDuplicates() async throws {
        let api = SequenceResumeAIAPI(responses: [
            #"{"skills":["产品规划","技能1","技能2","技能3","技能4","技能5","技能6","技能7","技能8","技能9","技能10"]}"#
        ])
        let service = ResumeAIService(apiClient: api)

        let skills = try await service.generateSkills(
            for: makeDocument(),
            configuration: testAIConfiguration
        )

        XCTAssertEqual(
            skills,
            ["技能1", "技能2", "技能3", "技能4", "技能5", "技能6", "技能7", "技能8", "技能9", "技能10"]
        )
        XCTAssertEqual(api.callCount, 1)
        XCTAssertTrue(api.userPrompts.first?.contains("生成 10 条") == true)
    }

    func testResumeAIServiceUsesTheRequestedProjectDomain() async throws {
        let api = SequenceResumeAIAPI(responses: [
            #"{"name":"有赞商城交易平台","period":"2022 — 2023","summary":"面向商家的在线交易平台，覆盖商品管理、订单履约、支付结算和经营数据分析。","bullets":["负责商品、订单与支付链路建设"]}"#
        ])
        let service = ResumeAIService(apiClient: api)

        let project = try await service.generateProject(
            for: makeAIGenerationDocument(),
            domain: "电商平台",
            configuration: testAIConfiguration
        )

        XCTAssertEqual(project.name, "有赞商城交易平台")
        XCTAssertEqual(project.summary, "面向商家的在线交易平台，覆盖商品管理、订单履约、支付结算和经营数据分析。")
        XCTAssertTrue(api.userPrompts.first?.contains("电商平台") == true)
        XCTAssertTrue(api.userPrompts.first?.contains("职位标题：软件测试工程师") == true)
        XCTAssertTrue(api.userPrompts.first?.contains("工作年限：6年经验") == true)
        XCTAssertTrue(api.userPrompts.first?.contains("推算工作时间：") == true)
        XCTAssertTrue(api.userPrompts.first?.contains("教育经历毕业年份基准：") == true)
    }

    func testDocumentCodecRejectsRemovedWorkAchievementField() throws {
        let data = try ResumeDocumentCodec.encodedData(for: makeDocument())
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var experience = try XCTUnwrap(root["experience"] as? [[String: Any]])
        experience[0]["bullets"] = ["不应再存在"]
        root["experience"] = experience
        let dataWithRemovedField = try JSONSerialization.data(withJSONObject: root)

        XCTAssertThrowsError(try ResumeDocumentCodec.decode(dataWithRemovedField))
    }

    func testResumeAIServiceDoesNotReturnAnExistingEducationAgain() async throws {
        let api = SequenceResumeAIAPI(responses: [
            #"{"school":"上海交通大学","degree":"本科","major":"计算机","period":"2013 — 2017"}"#
        ])
        let service = ResumeAIService(apiClient: api)

        do {
            _ = try await service.generateEducation(for: makeDocument(), configuration: testAIConfiguration)
            XCTFail("重复内容应该在重试耗尽后失败")
        } catch let error as AIAPIError {
            XCTAssertEqual(error, .duplicateGeneratedContent(context: "教育经历"))
            XCTAssertEqual(api.callCount, 3)
        }
    }

    private var testAIConfiguration: AIAPIConfiguration {
        AIAPIConfiguration(endpoint: "https://example.com", model: "test-model", apiKey: "test-key")
    }

    private func contentMatchingTemplate(_ document: ResumeDocument, template: ResumeTemplate) -> ResumeDocument {
        var copy = document
        copy.template = template
        return copy
    }

    private func makeAIGenerationDocument() -> ResumeDocument {
        ResumeDocument(
            basicInfo: ResumeBasicInfo(
                name: "林知远",
                headline: "软件测试工程师",
                email: "lin.zhiyuan@example.com",
                location: "上海",
                jobStatus: "在职",
                workYears: "6年经验"
            )
        )
    }

    private func makeDocument() -> ResumeDocument {
        ResumeDocument(
            title: "产品经理简历",
            basicInfo: ResumeBasicInfo(
                name: "林知远",
                headline: "产品经理",
                email: "lin.zhiyuan@example.com",
                location: "上海",
                jobStatus: "在职",
                workYears: "5年经验"
            ),
            education: [ResumeEducation(school: "上海交通大学", degree: "本科", major: "计算机", period: "2013 — 2017")],
            experience: [ResumeExperience(
                company: "星云科技",
                role: "产品经理",
                period: "2021 — 至今"
            )],
            skills: ["产品规划", "需求分析", "SQL", "Figma", "数据分析"],
            projects: [ResumeProject(
                name: "智能工单平台",
                period: "2022 — 2023",
                summary: "面向企业客户的智能工单协作平台，支持问题受理、自动分派、进度跟踪与服务分析。",
                bullets: ["推动项目上线并持续迭代"]
            )]
        )
    }

    private func hasDarkPixel(in bitmap: NSBitmapImageRep) -> Bool {
        for x in stride(from: 0, to: bitmap.pixelsWide, by: max(bitmap.pixelsWide / 40, 1)) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: max(bitmap.pixelsHigh / 40, 1)) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if min(color.redComponent, color.greenComponent, color.blueComponent) < 0.82 {
                    return true
                }
            }
        }
        return false
    }
}

private final class SequenceResumeAIAPI: AITextCompletionAPI, @unchecked Sendable {
    private let responses: [String]
    private(set) var callCount = 0
    private(set) var userPrompts: [String] = []

    init(responses: [String]) {
        self.responses = responses
    }

    func complete(
        systemPrompt _: String,
        userPrompt: String,
        configuration _: AIAPIConfiguration
    ) async throws -> String {
        userPrompts.append(userPrompt)
        let response = responses[min(callCount, responses.count - 1)]
        callCount += 1
        return response
    }
}
