import Combine
import Foundation

enum ResumeTemplate: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case minimal
    case editorial
    case timeline

    static let defaultTemplate: ResumeTemplate = .minimal
    static let allCases: [ResumeTemplate] = [.minimal, .editorial, .timeline]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "minimal", "classic", "modern", "waterfall", "sidebar", "contrast":
            self = .minimal
        case "editorial":
            self = .editorial
        case "timeline":
            self = .timeline
        default:
            self = .defaultTemplate
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .minimal: "现代极简"
        case .editorial: "编辑风格"
        case .timeline: "时间轴"
        }
    }

    var icon: String {
        switch self {
        case .minimal: "text.alignleft"
        case .editorial: "newspaper"
        case .timeline: "point.3.connected.trianglepath.dotted"
        }
    }
}

struct ResumeDocument: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var template: ResumeTemplate
    var basicInfo: ResumeBasicInfo
    var education: [ResumeEducation]
    var experience: [ResumeExperience]
    var skills: [String]
    var projects: [ResumeProject]

    init(
        id: UUID = UUID(),
        title: String = "未命名简历",
        template: ResumeTemplate = .defaultTemplate,
        basicInfo: ResumeBasicInfo = .blank,
        education: [ResumeEducation] = [],
        experience: [ResumeExperience] = [],
        skills: [String] = [],
        projects: [ResumeProject] = []
    ) {
        self.id = id
        self.title = title
        self.template = template
        self.basicInfo = basicInfo
        self.education = education
        self.experience = experience
        self.skills = skills
        self.projects = projects
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case template
        case basicInfo
        case education
        case experience
        case skills
        case projects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        template = try container.decodeIfPresent(ResumeTemplate.self, forKey: .template) ?? .defaultTemplate
        basicInfo = try container.decode(ResumeBasicInfo.self, forKey: .basicInfo)
        education = try container.decode([ResumeEducation].self, forKey: .education)
        experience = try container.decode([ResumeExperience].self, forKey: .experience)
        skills = try container.decode([String].self, forKey: .skills)
        projects = try container.decode([ResumeProject].self, forKey: .projects)
    }

    static func blank() -> ResumeDocument {
        ResumeDocument()
    }

    var hasContent: Bool {
        !basicInfo.isEmpty
            || education.contains(where: \.hasContent)
            || experience.contains(where: \.hasContent)
            || skills.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            || projects.contains(where: \.hasContent)
    }
}

struct ResumeBasicInfo: Codable, Equatable, Sendable {
    var name: String
    var headline: String
    var email: String
    var location: String
    var jobStatus: String
    var workYears: String

    static let blank = ResumeBasicInfo(
        name: "",
        headline: "",
        email: "",
        location: "",
        jobStatus: "",
        workYears: ""
    )

    var isEmpty: Bool {
        [name, headline, email, location, jobStatus, workYears]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var missingRequiredFieldsForAI: [String] {
        let requiredFields = [
            (name, "姓名"),
            (headline, "职位标题"),
            (location, "所在地"),
            (email, "联系方式"),
            (jobStatus, "岗位状态")
        ]
        var missingFields = requiredFields.compactMap { value, title in
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? title : nil
        }

        let normalizedWorkYears = workYears.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedWorkYears.isEmpty {
            missingFields.append("工作年限")
        } else if ResumeCareerTimeline.years(from: normalizedWorkYears) == nil {
            missingFields.append("工作年限（如 6 年经验）")
        }
        return missingFields
    }

    var isReadyForAIGeneration: Bool {
        missingRequiredFieldsForAI.isEmpty
    }
}

enum ResumeCareerTimeline {
    static func years(from workYears: String) -> Int? {
        guard let range = workYears.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression),
              let value = Double(workYears[range]),
              value >= 0
        else {
            return nil
        }
        return Int(value.rounded(.down))
    }

    static func period(for workYears: String, referenceDate: Date = Date()) -> String? {
        guard let graduationYear = graduationYear(for: workYears, referenceDate: referenceDate) else {
            return nil
        }
        return "\(graduationYear) — 至今"
    }

    static func educationPeriod(
        for workYears: String,
        degree: String,
        referenceDate: Date = Date()
    ) -> String? {
        guard let graduationYear = graduationYear(for: workYears, referenceDate: referenceDate) else {
            return nil
        }
        let normalizedDegree = degree.trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = if normalizedDegree.contains("博士") {
            4
        } else if normalizedDegree.contains("硕") || normalizedDegree.contains("研究生") {
            3
        } else if normalizedDegree.contains("专科") || normalizedDegree.contains("大专") {
            3
        } else {
            4
        }
        return "\(graduationYear - duration) — \(graduationYear)"
    }

    static func graduationYear(for workYears: String, referenceDate: Date = Date()) -> Int? {
        guard let years = years(from: workYears) else { return nil }
        let currentYear = Calendar.current.component(.year, from: referenceDate)
        return currentYear - years
    }
}

struct ResumeEducation: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var school: String
    var degree: String
    var major: String
    var period: String

    init(
        id: UUID = UUID(),
        school: String = "",
        degree: String = "",
        major: String = "",
        period: String = ""
    ) {
        self.id = id
        self.school = school
        self.degree = degree
        self.major = major
        self.period = period
    }

    static let blank = ResumeEducation()

    var hasContent: Bool {
        [school, degree, major, period]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct ResumeExperience: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var company: String
    var role: String
    var period: String

    init(
        id: UUID = UUID(),
        company: String = "",
        role: String = "",
        period: String = ""
    ) {
        self.id = id
        self.company = company
        self.role = role
        self.period = period
    }

    static let blank = ResumeExperience()

    var hasContent: Bool {
        [company, role, period]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct ResumeProject: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var period: String
    var summary: String
    var bullets: [String]

    init(
        id: UUID = UUID(),
        name: String = "",
        period: String = "",
        summary: String = "",
        bullets: [String] = []
    ) {
        self.id = id
        self.name = name
        self.period = period
        self.summary = summary
        self.bullets = bullets
    }

    static let blank = ResumeProject()

    var hasContent: Bool {
        [name, period]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || bullets.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

enum ResumeSection: String, CaseIterable, Identifiable, Sendable {
    case basicInfo
    case education
    case experience
    case skills
    case projects

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .basicInfo: "基本信息"
        case .education: "教育经历"
        case .experience: "工作经历"
        case .skills: "掌握技能"
        case .projects: "项目经历"
        }
    }

    var icon: String {
        switch self {
        case .basicInfo: "person.crop.circle"
        case .education: "graduationcap"
        case .experience: "briefcase"
        case .skills: "tag"
        case .projects: "folder"
        }
    }
}

enum ResumeExportFormat: String, CaseIterable, Identifiable {
    case pdf
    case rtf
    case markdown
    case json

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .pdf: "PDF"
        case .rtf: "RTF（可编辑）"
        case .markdown: "Markdown"
        case .json: "JSON"
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf: "pdf"
        case .rtf: "rtf"
        case .markdown: "md"
        case .json: "json"
        }
    }
}

enum ResumeSavedFile {
    static func documentTitle(from url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "未命名简历" : name
    }
}

@MainActor
final class ResumeWorkspace: ObservableObject {
    @Published var document: ResumeDocument
    @Published private(set) var lastSavedAt: Date?
    @Published private(set) var hasChosenTemplate: Bool
    @Published private(set) var generatingSection: ResumeSection?

    private var savedSignature: Data?
    private var generationTask: Task<Void, Never>?

    init(document: ResumeDocument = .blank(), hasChosenTemplate: Bool? = nil) {
        self.document = document
        self.hasChosenTemplate = hasChosenTemplate ?? document.hasContent
    }

    var needsTemplateSelection: Bool {
        !hasChosenTemplate
    }

    func chooseTemplate(_ template: ResumeTemplate) {
        document.template = template
        hasChosenTemplate = true
    }

    var isSaved: Bool {
        guard let savedSignature else { return false }
        return savedSignature == ResumeDocumentCodec.signature(for: document)
    }

    var requiresSaveBeforeNewResume: Bool {
        guard !isSaved else { return false }
        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return document.hasContent || !title.isEmpty && title != "未命名简历"
    }

    func beginNewResume() {
        cancelGeneration()
        document = ResumeDocument(template: .defaultTemplate)
        savedSignature = nil
        lastSavedAt = nil
        hasChosenTemplate = false
    }

    func replace(with document: ResumeDocument) {
        cancelGeneration()
        let preservedTemplate = hasChosenTemplate ? self.document.template : document.template
        self.document = document
        self.document.template = preservedTemplate
        hasChosenTemplate = true
        savedSignature = nil
        lastSavedAt = nil
    }

    func markSaved(at date: Date = Date()) {
        savedSignature = ResumeDocumentCodec.signature(for: document)
        lastSavedAt = date
    }

    func markSaved(to url: URL, at date: Date = Date()) {
        document.title = ResumeSavedFile.documentTitle(from: url)
        markSaved(at: date)
    }

    var isGenerating: Bool {
        generatingSection != nil
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        generatingSection = nil
    }

    func startGeneration(
        for section: ResumeSection,
        work: @escaping @MainActor () async -> Void
    ) {
        guard generatingSection == nil, section != .basicInfo else { return }
        generatingSection = section
        generationTask = Task { @MainActor [weak self] in
            defer {
                if let self {
                    if self.generatingSection == section {
                        self.generatingSection = nil
                    }
                    self.generationTask = nil
                }
            }
            await work()
        }
    }
}

enum ResumeDocumentCodec {
    private static let requiredDocumentKeys: Set<String> = [
        "id", "title", "basicInfo", "education", "experience", "skills", "projects"
    ]
    private static let optionalDocumentKeys: Set<String> = ["template"]
    private static let basicInfoKeys: Set<String> = [
        "name", "headline", "email", "location", "jobStatus", "workYears"
    ]
    private static let educationKeys: Set<String> = ["id", "school", "degree", "major", "period"]
    private static let experienceKeys: Set<String> = ["id", "company", "role", "period"]
    private static let projectKeys: Set<String> = ["id", "name", "period", "summary", "bullets"]

    private struct ExportDocument: Encodable {
        let id: UUID
        let title: String
        let basicInfo: ResumeBasicInfo
        let education: [ResumeEducation]
        let experience: [ResumeExperience]
        let skills: [String]
        let projects: [ResumeProject]

        init(_ document: ResumeDocument) {
            id = document.id
            title = document.title
            basicInfo = document.basicInfo
            education = document.education
            experience = document.experience
            skills = document.skills
            projects = document.projects
        }
    }

    static func encodedData(for document: ResumeDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ExportDocument(document))
    }

    static func signature(for document: ResumeDocument) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> ResumeDocument {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodeError.invalidSchema
        }
        try validateKeys(root, required: requiredDocumentKeys, optional: optionalDocumentKeys)
        try validateObject(root["basicInfo"], keys: basicInfoKeys)
        try validateArray(root["education"], itemKeys: educationKeys)
        try validateArray(root["experience"], itemKeys: experienceKeys)
        try validateStringArray(root["skills"])
        try validateArray(root["projects"], itemKeys: projectKeys)
        return try JSONDecoder().decode(ResumeDocument.self, from: data)
    }

    private static func validateObject(_ value: Any?, keys: Set<String>) throws {
        guard let object = value as? [String: Any] else {
            throw DecodeError.invalidSchema
        }
        try validateKeys(object, exactly: keys)
    }

    private static func validateArray(_ value: Any?, itemKeys: Set<String>) throws {
        guard let items = value as? [[String: Any]] else {
            throw DecodeError.invalidSchema
        }
        for item in items {
            try validateKeys(item, exactly: itemKeys)
        }
    }

    private static func validateStringArray(_ value: Any?) throws {
        guard value is [String] else {
            throw DecodeError.invalidSchema
        }
    }

    private static func validateKeys(
        _ object: [String: Any],
        required: Set<String>,
        optional: Set<String> = []
    ) throws {
        let keys = Set(object.keys)
        guard keys.isSuperset(of: required), keys.subtracting(required.union(optional)).isEmpty else {
            throw DecodeError.invalidSchema
        }
    }

    private static func validateKeys(_ object: [String: Any], exactly keys: Set<String>) throws {
        guard Set(object.keys) == keys else {
            throw DecodeError.invalidSchema
        }
    }

    private enum DecodeError: Error {
        case invalidSchema
    }
}

enum ResumeTextFormatter {
    static func markdown(for document: ResumeDocument) -> String {
        var lines: [String] = []
        let info = document.basicInfo

        appendIfPresent(info.name, to: &lines, prefix: "# ")
        let headline = [info.headline, info.location, info.email]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " · ")
        appendIfPresent(headline, to: &lines, prefix: "")

        let status = [info.jobStatus, info.workYears]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " · ")
        appendIfPresent(status, to: &lines, prefix: "状态：")

        appendEducation(document.education.filter(\.hasContent), to: &lines)
        appendExperience(document.experience.filter(\.hasContent), to: &lines)
        let skills = document.skills.filter(nonEmpty)
        if !skills.isEmpty {
            lines.append("## 掌握技能")
            lines.append(skills.joined(separator: "、"))
            lines.append("")
        }
        appendProjects(document.projects.filter(\.hasContent), to: &lines)

        return lines.joined(separator: "\n")
    }

    static func plainText(for document: ResumeDocument) -> String {
        markdown(for: document)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "### ", with: "")
            .replacingOccurrences(of: "## ", with: "")
            .replacingOccurrences(of: "# ", with: "")
    }

    private static func appendEducation(_ education: [ResumeEducation], to lines: inout [String]) {
        guard !education.isEmpty else { return }
        lines.append("## 教育经历")
        for item in education {
            let title = [item.school, item.degree, item.major]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " · ")
            appendIfPresent(title, to: &lines, prefix: "### ")
            appendIfPresent(item.period, to: &lines, prefix: "")
            lines.append("")
        }
    }

    private static func appendExperience(_ experience: [ResumeExperience], to lines: inout [String]) {
        guard !experience.isEmpty else { return }
        lines.append("## 工作经历")
        for item in experience {
            let title = [item.company, item.role, item.period]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " · ")
            appendIfPresent(title, to: &lines, prefix: "### ")
            lines.append("")
        }
    }

    private static func appendProjects(_ projects: [ResumeProject], to lines: inout [String]) {
        guard !projects.isEmpty else { return }
        lines.append("## 项目经历")
        for item in projects {
            let title = [item.name, item.period]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " · ")
            appendIfPresent(title, to: &lines, prefix: "### ")
            appendIfPresent(item.summary, to: &lines, prefix: "")
            lines += item.bullets.filter(nonEmpty).map { "- \($0)" }
            lines.append("")
        }
    }

    private static func appendIfPresent(_ value: String, to lines: inout [String], prefix: String) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lines.append(prefix + value)
    }

    private static func nonEmpty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
