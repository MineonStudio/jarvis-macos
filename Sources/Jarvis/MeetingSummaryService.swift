import Foundation

struct MeetingSummaryService: Sendable {
    let api: any AITextCompletionAPI

    func summarize(
        record: MeetingRecord,
        configuration: AIAPIConfiguration
    ) async throws -> MeetingSummary {
        let transcript = record.transcript.map { segment in
            let speaker = record.speakers.first { $0.id == segment.speakerID }?.name ?? segment.speakerID
            return "[\(formatTime(segment.startTime))] \(speaker)：\(segment.text)"
        }.joined(separator: "\n")

        if transcript.count <= Self.maxTranscriptCharacters {
            return try await requestSummary(
                title: record.title,
                sourceTitle: "逐字稿",
                source: transcript,
                configuration: configuration
            )
        }

        let chunks = splitTranscript(transcript)
        var partialSummaries: [MeetingSummary] = []
        partialSummaries.reserveCapacity(chunks.count)
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            try await partialSummaries.append(
                requestSummary(
                    title: record.title,
                    sourceTitle: "逐字稿第 \(index + 1)/\(chunks.count) 段",
                    source: chunk,
                    configuration: configuration
                )
            )
        }

        let partialData = try JSONEncoder().encode(partialSummaries)
        let partialText = String(decoding: partialData, as: UTF8.self)
        return try await requestSummary(
            title: record.title,
            sourceTitle: "分段摘要（请去重并合并）",
            source: partialText,
            configuration: configuration,
            merging: true
        )
    }

    private static let maxTranscriptCharacters = 18000

    private func requestSummary(
        title: String,
        sourceTitle: String,
        source: String,
        configuration: AIAPIConfiguration,
        merging: Bool = false
    ) async throws -> MeetingSummary {
        let systemPrompt = """
        你是严谨的中文会议纪要助手。请只根据输入内容整理事实，不要臆测未出现的内容。
        \(merging ? "输入是多个分段摘要，请去重、合并并保留最重要的结论。" : "输入是带时间戳和说话人的逐字稿，请优先提取结论。")
        重点优先输出：一句话结论、关键讨论、明确决策、可执行待办和未解决问题。
        待办必须尽量保留负责人和截止时间；如果原文没有，就留空，不要编造。
        必须只返回 JSON，不要 Markdown 代码块，字段为：
        {"overview":"string","keyPoints":["string"],"decisions":["string"],"actionItems":[{"task":"string","owner":"string","dueDate":"string"}],"openQuestions":["string"]}
        """
        let userPrompt = "会议标题：\(title)\n\n\(sourceTitle)：\n\(source)"
        let raw = try await api.complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            configuration: configuration
        )
        return try decode(raw)
    }

    private func splitTranscript(_ transcript: String) -> [String] {
        var chunks: [String] = []
        var current = ""

        for line in transcript.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineText = String(line)
            let candidate = current.isEmpty ? lineText : "\(current)\n\(lineText)"
            if candidate.count > Self.maxTranscriptCharacters, !current.isEmpty {
                chunks.append(current)
                current = lineText
            } else {
                current = candidate
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    private func decode(_ raw: String) throws -> MeetingSummary {
        let normalized = Self.extractJSONObject(raw)
        guard let data = normalized.data(using: .utf8) else {
            throw AIAPIError.invalidJSON(context: "会议总结", reason: "返回内容为空")
        }

        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            let overview = payload.overview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !overview.isEmpty || !payload.keyPoints.isEmpty || !payload.decisions.isEmpty else {
                throw AIAPIError.emptyGeneratedContent(context: "会议总结")
            }
            return MeetingSummary(
                overview: overview,
                keyPoints: payload.keyPoints,
                decisions: payload.decisions,
                actionItems: payload.actionItems.map {
                    MeetingActionItem(task: $0.task, owner: $0.owner, dueDate: $0.dueDate)
                },
                openQuestions: payload.openQuestions
            )
        } catch let error as AIAPIError {
            throw error
        } catch {
            throw AIAPIError.decodingError(error, context: "会议总结")
        }
    }

    static func extractJSONObject(_ raw: String) -> String {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = normalized.firstIndex(of: "{"),
              let end = normalized.lastIndex(of: "}"),
              start < end
        else {
            return normalized
        }
        return String(normalized[start ... end])
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private struct Payload: Decodable {
        let overview: String?
        let keyPoints: [String]
        let decisions: [String]
        let actionItems: [ActionItem]
        let openQuestions: [String]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            overview = try container.decodeIfPresent(String.self, forKey: .overview)
            keyPoints = try container.decodeIfPresent([String].self, forKey: .keyPoints) ?? []
            decisions = try container.decodeIfPresent([String].self, forKey: .decisions) ?? []
            actionItems = try container.decodeIfPresent([ActionItem].self, forKey: .actionItems) ?? []
            openQuestions = try container.decodeIfPresent([String].self, forKey: .openQuestions) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case overview
            case keyPoints
            case decisions
            case actionItems
            case openQuestions
        }
    }

    private struct ActionItem: Decodable {
        let task: String
        let owner: String
        let dueDate: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            task = try container.decodeIfPresent(String.self, forKey: .task) ?? ""
            owner = try container.decodeIfPresent(String.self, forKey: .owner) ?? ""
            dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate) ?? ""
        }

        private enum CodingKeys: String, CodingKey {
            case task
            case owner
            case dueDate
        }
    }
}
