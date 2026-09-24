import CryptoKit
import Foundation

struct MeetingSummaryService: Sendable {
    typealias CheckpointHandler = @MainActor @Sendable (MeetingSummaryCheckpoint) -> Void

    let api: any AITextCompletionAPI

    func summarize(
        record: MeetingRecord,
        configuration: AIAPIConfiguration,
        checkpoint: MeetingSummaryCheckpoint? = nil,
        onCheckpoint: CheckpointHandler? = nil
    ) async throws -> MeetingSummary {
        let chunks = makeChunks(from: record.transcript, speakers: record.speakers)
        guard !chunks.isEmpty else {
            throw AIAPIError.emptyGeneratedContent(context: "会议逐字稿")
        }

        let fingerprint = transcriptFingerprint(record.transcript)
        var facts: [MeetingFact]
        var completedChunkCount: Int
        if let checkpoint,
           checkpoint.pipelineVersion == MeetingSummaryCheckpoint.currentPipelineVersion,
           checkpoint.transcriptFingerprint == fingerprint,
           checkpoint.totalChunkCount == chunks.count,
           checkpoint.completedChunkCount >= 0,
           checkpoint.completedChunkCount <= chunks.count
        {
            facts = checkpoint.facts
            completedChunkCount = checkpoint.completedChunkCount
        } else {
            facts = []
            completedChunkCount = 0
        }

        if completedChunkCount == 0 {
            await publish(
                MeetingSummaryCheckpoint(
                    transcriptFingerprint: fingerprint,
                    stage: .extractingFacts,
                    completedChunkCount: 0,
                    totalChunkCount: chunks.count
                ),
                to: onCheckpoint
            )
        }

        for index in completedChunkCount ..< chunks.count {
            try Task.checkCancellation()
            let extractedFacts = try await requestFacts(
                title: record.title,
                chunk: chunks[index],
                configuration: configuration
            )
            facts = mergeFacts(facts + extractedFacts)
            await publish(
                MeetingSummaryCheckpoint(
                    transcriptFingerprint: fingerprint,
                    stage: .extractingFacts,
                    completedChunkCount: index + 1,
                    totalChunkCount: chunks.count,
                    facts: facts
                ),
                to: onCheckpoint
            )
        }

        await publish(
            MeetingSummaryCheckpoint(
                transcriptFingerprint: fingerprint,
                stage: .synthesizing,
                completedChunkCount: chunks.count,
                totalChunkCount: chunks.count,
                facts: facts
            ),
            to: onCheckpoint
        )

        let summary: MeetingSummary = if facts.isEmpty {
            MeetingSummary(
                overview: "未提取到可确认的会议结论",
                keyPoints: [],
                decisions: [],
                actionItems: [],
                openQuestions: []
            )
        } else {
            try await requestSummary(
                title: record.title,
                facts: facts,
                configuration: configuration
            )
        }

        await publish(
            MeetingSummaryCheckpoint(
                transcriptFingerprint: fingerprint,
                stage: .completed,
                completedChunkCount: chunks.count,
                totalChunkCount: chunks.count,
                facts: facts
            ),
            to: onCheckpoint
        )
        var validatedSummary = summary
        validatedSummary.citations = normalizedCitations(
            summary.citations ?? [],
            summary: summary,
            allowedSegmentIDs: Set(record.transcript.map(\.id))
        )
        return validatedSummary
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

    // This is a batching target, not a content limit. Every transcript segment and
    // every extracted fact is included in one of the requests below.
    private static let synthesisBatchTargetTokens = 3200
    private static let transcriptChunkTargetTokens = 4200

    private func requestFacts(
        title: String,
        chunk: TranscriptChunk,
        configuration: AIAPIConfiguration
    ) async throws -> [MeetingFact] {
        let systemPrompt = """
        你是严谨的中文会议事实提取器。只提取输入中明确出现的事实，不要推测。
        把内容整理成 JSON 对象，格式必须是：
        {"facts":[{"kind":"keyPoint|decision|actionItem|openQuestion","text":"事实","owner":"负责人或空字符串","dueDate":"截止时间或空字符串","sourceSegmentIDs":["逐字稿片段ID"]}]}
        保留输入中的全部明确事实，去除重复内容。每条事实必须简洁，并且至少引用一个输入中的 sourceSegmentID。
        actionItem 只有在原文确实提出行动或任务时才返回；没有负责人或截止时间时必须留空。
        只能返回 JSON，不要 Markdown，不要解释文字。
        """
        let userPrompt = """
        会议标题：\(title)

        逐字稿片段：
        \(chunk.text)
        """
        let raw = try await api.complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            configuration: configuration,
            options: .meetingFactExtraction
        )
        return try decodeFacts(raw, allowedSegmentIDs: Set(chunk.segmentIDs))
    }

    private func requestSummary(
        title: String,
        facts: [MeetingFact],
        configuration: AIAPIConfiguration
    ) async throws -> MeetingSummary {
        var partialSummaries = try await summarizeFactBatches(
            title: title,
            facts: facts,
            configuration: configuration
        )
        while partialSummaries.count > 1 {
            let batches = makeSummaryBatches(from: partialSummaries)
            var mergedSummaries: [MeetingSummary] = []
            for batch in batches {
                let merged = try await requestSummaryMerge(
                    title: title,
                    summaries: batch,
                    configuration: configuration
                )
                mergedSummaries.append(merged)
            }
            if mergedSummaries.count >= partialSummaries.count {
                let firstBatch = Array(partialSummaries.prefix(2))
                let merged = try await requestSummaryMerge(
                    title: title,
                    summaries: firstBatch,
                    configuration: configuration
                )
                partialSummaries = [merged] + Array(partialSummaries.dropFirst(2))
            } else {
                partialSummaries = mergedSummaries
            }
        }
        guard let summary = partialSummaries.first else {
            throw AIAPIError.emptyGeneratedContent(context: "会议事实提取")
        }
        return summary
    }

    private func summarizeFactBatches(
        title: String,
        facts: [MeetingFact],
        configuration: AIAPIConfiguration
    ) async throws -> [MeetingSummary] {
        let batches = makeSynthesisFactBatches(from: facts)
        guard !batches.isEmpty else {
            throw AIAPIError.emptyGeneratedContent(context: "会议事实提取")
        }
        var summaries: [MeetingSummary] = []
        for batch in batches {
            let factsData = try JSONEncoder().encode(batch)
            let factsText = String(decoding: factsData, as: UTF8.self)
            let systemPrompt = """
            你是严谨的中文会议纪要助手。只能根据给出的事实生成纪要，不要补充事实之外的内容。
            必须只返回 JSON 对象，格式为：
            {"overview":"一句话结论","keyPoints":["关键讨论"],"decisions":["明确决策"],"actionItems":[{"task":"任务","owner":"负责人","dueDate":"截止时间"}],"openQuestions":["未解决问题"],"citations":[{"kind":"keyPoint|decision|actionItem|openQuestion","text":"与对应条目完全相同","sourceSegmentIDs":["逐字稿片段ID"]}]}
            概览只写 1 句，控制在 80 个汉字以内，先说会议结论或当前状态。
            关键讨论最多 5 条，每条不超过 50 个汉字；合并同一议题，优先保留影响决策、执行或风险的内容，省略重复背景和闲聊。
            决策、待办和仍影响执行的未解决问题必须完整保留，不设条数上限。每个待办只写一个可执行动作，不要把不同负责人或截止时间的任务合并。
            没有明确负责人或截止时间时保留空字符串，不要编造。每条决策、待办和未解决问题都要引用来源；sourceSegmentIDs 只能使用输入事实中出现的 ID。
            去掉不同措辞表达的重复内容；同一事项在不同分块重复出现时合并为一条。
            只能返回 JSON，不要 Markdown，不要解释文字。
            """
            let userPrompt = """
            会议标题：\(title)

            已验证的会议事实：
            \(factsText)
            """
            let raw = try await api.complete(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                configuration: configuration,
                options: .meetingSummary
            )
            let summary = try decodeSummary(raw)
            summaries.append(summary)
        }
        return summaries
    }

    private func requestSummaryMerge(
        title: String,
        summaries: [MeetingSummary],
        configuration: AIAPIConfiguration
    ) async throws -> MeetingSummary {
        let mergeInputs = summaries.map {
            SynthesisSummary(
                overview: $0.overview,
                keyPoints: $0.keyPoints,
                decisions: $0.decisions,
                actionItems: $0.actionItems.map {
                    SynthesisActionItem(task: $0.task, owner: $0.owner, dueDate: $0.dueDate)
                },
                openQuestions: $0.openQuestions,
                citations: $0.citations
            )
        }
        let data = try JSONEncoder().encode(mergeInputs)
        let systemPrompt = """
        你是严谨的中文会议纪要合并助手。只能根据给出的局部纪要生成完整纪要，不要补充事实之外的内容。
        必须只返回 JSON 对象，格式为：
        {"overview":"一句话结论","keyPoints":["关键讨论"],"decisions":["明确决策"],"actionItems":[{"task":"任务","owner":"负责人","dueDate":"截止时间"}],"openQuestions":["未解决问题"],"citations":[{"kind":"keyPoint|decision|actionItem|openQuestion","text":"与对应条目完全相同","sourceSegmentIDs":["逐字稿片段ID"]}]}
        概览只写 1 句，控制在 80 个汉字以内。关键讨论最多 5 条，每条不超过 50 个汉字；按议题合并并删除语义重复项。
        完整保留所有不重复的明确决策、待办和仍影响执行的问题。不同负责人或截止时间的任务必须分开。没有明确负责人或截止时间时保留空字符串，不要编造。
        尽量保留输入 citations 的来源 ID，并确保每条决策和待办引用对应原文；不要生成输入中没有的 ID。
        只能返回 JSON，不要 Markdown，不要解释文字。
        """
        let userPrompt = """
        会议标题：\(title)

        已生成的局部纪要：
        \(String(decoding: data, as: UTF8.self))
        """
        let raw = try await api.complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            configuration: configuration,
            options: .meetingSummary
        )
        return try decodeSummary(raw)
    }

    private func decodeFacts(
        _ raw: String,
        allowedSegmentIDs: Set<UUID>
    ) throws -> [MeetingFact] {
        guard let data = Self.extractJSONObject(raw).data(using: .utf8) else {
            throw AIAPIError.invalidJSON(context: "会议事实提取", reason: "返回内容为空")
        }

        do {
            let payload = try JSONDecoder().decode(FactPayload.self, from: data)
            return payload.facts.compactMap { item -> MeetingFact? in
                guard let kind = MeetingFactKind(rawValue: item.kind),
                      let text = normalizedText(item.text),
                      !text.isEmpty
                else { return nil }

                let sourceIDs = item.sourceSegmentIDs.compactMap(UUID.init(uuidString:))
                    .filter(allowedSegmentIDs.contains)
                guard !sourceIDs.isEmpty else { return nil }
                return MeetingFact(
                    kind: kind,
                    text: text,
                    owner: normalizedText(item.owner) ?? "",
                    dueDate: normalizedText(item.dueDate) ?? "",
                    sourceSegmentIDs: sourceIDs
                )
            }
        } catch let error as AIAPIError {
            throw error
        } catch {
            throw AIAPIError.decodingError(error, context: "会议事实提取")
        }
    }

    private func decodeSummary(_ raw: String) throws -> MeetingSummary {
        guard let data = Self.extractJSONObject(raw).data(using: .utf8) else {
            throw AIAPIError.invalidJSON(context: "会议总结", reason: "返回内容为空")
        }

        do {
            let payload = try JSONDecoder().decode(SummaryPayload.self, from: data)
            let overview = normalizedText(payload.overview) ?? ""
            let keyPoints = normalizedList(payload.keyPoints)
            let decisions = normalizedList(payload.decisions)
            let actionItems = payload.actionItems.compactMap { item -> MeetingActionItem? in
                guard let task = normalizedText(item.task), !task.isEmpty else { return nil }
                return MeetingActionItem(
                    task: task,
                    owner: normalizedText(item.owner) ?? "",
                    dueDate: normalizedText(item.dueDate) ?? ""
                )
            }
            let openQuestions = normalizedList(payload.openQuestions)
            guard !overview.isEmpty || !keyPoints.isEmpty || !decisions.isEmpty || !actionItems.isEmpty else {
                throw AIAPIError.emptyGeneratedContent(context: "会议总结")
            }
            return MeetingSummary(
                overview: overview,
                keyPoints: keyPoints,
                decisions: decisions,
                actionItems: actionItems,
                openQuestions: openQuestions,
                citations: payload.citations.compactMap { item in
                    guard let kind = MeetingFactKind(rawValue: item.kind),
                          let text = normalizedText(item.text)
                    else { return nil }
                    return MeetingSummaryCitation(
                        kind: kind,
                        text: text,
                        sourceSegmentIDs: item.sourceSegmentIDs.compactMap(UUID.init(uuidString:))
                    )
                }
            )
        } catch let error as AIAPIError {
            throw error
        } catch {
            throw AIAPIError.decodingError(error, context: "会议总结")
        }
    }

    private func mergeFacts(_ facts: [MeetingFact]) -> [MeetingFact] {
        var result: [MeetingFact] = []
        var indexBySignature: [String: Int] = [:]
        for fact in facts {
            let signature = [fact.kind.rawValue, fact.text, fact.owner, fact.dueDate]
                .joined(separator: "\u{1F}")
            if let index = indexBySignature[signature] {
                result[index].sourceSegmentIDs = Array(
                    Set(result[index].sourceSegmentIDs + fact.sourceSegmentIDs)
                ).sorted { $0.uuidString < $1.uuidString }
            } else {
                indexBySignature[signature] = result.count
                result.append(fact)
            }
        }
        return result
    }

    private func makeSynthesisFactBatches(from facts: [MeetingFact]) -> [[SynthesisFact]] {
        var batches: [[SynthesisFact]] = []
        var current: [SynthesisFact] = []
        for fact in facts {
            let candidate = SynthesisFact(
                kind: fact.kind.rawValue,
                text: fact.text,
                owner: fact.owner,
                dueDate: fact.dueDate,
                sourceSegmentIDs: fact.sourceSegmentIDs
            )
            guard let candidateData = try? JSONEncoder().encode(current + [candidate]) else {
                break
            }
            let candidateText = String(decoding: candidateData, as: UTF8.self)
            if !current.isEmpty, estimateTokens(candidateText) > Self.synthesisBatchTargetTokens {
                batches.append(current)
                current = []
            }
            current.append(candidate)
        }
        if !current.isEmpty {
            batches.append(current)
        }
        return batches
    }

    private func makeSummaryBatches(from summaries: [MeetingSummary]) -> [[MeetingSummary]] {
        var batches: [[MeetingSummary]] = []
        var current: [MeetingSummary] = []
        for summary in summaries {
            let candidate = current + [summary]
            let candidateText = (try? JSONEncoder().encode(candidate)).map {
                String(decoding: $0, as: UTF8.self)
            } ?? ""
            if !current.isEmpty, estimateTokens(candidateText) > Self.synthesisBatchTargetTokens {
                batches.append(current)
                current = []
            }
            current.append(summary)
        }
        if !current.isEmpty {
            batches.append(current)
        }
        return batches
    }

    private func makeChunks(
        from segments: [MeetingTranscriptSegment],
        speakers: [MeetingSpeaker]
    ) -> [TranscriptChunk] {
        let speakerNames = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0.name) })
        var chunks: [TranscriptChunk] = []
        var currentLines: [String] = []
        var currentIDs: [UUID] = []

        func flush() {
            guard !currentLines.isEmpty else { return }
            chunks.append(TranscriptChunk(text: currentLines.joined(separator: "\n"), segmentIDs: currentIDs))
            currentLines.removeAll(keepingCapacity: true)
            currentIDs.removeAll(keepingCapacity: true)
        }

        for segment in segments {
            let speaker = speakerNames[segment.speakerID] ?? segment.speakerID
            let line = "[\(formatTime(segment.startTime))][\(segment.id.uuidString)] \(speaker)：\(segment.text)"
            if estimateTokens(line) <= Self.transcriptChunkTargetTokens {
                let candidate = (currentLines + [line]).joined(separator: "\n")
                if !currentLines.isEmpty, estimateTokens(candidate) > Self.transcriptChunkTargetTokens {
                    flush()
                }
                currentLines.append(line)
                currentIDs.append(segment.id)
                continue
            }

            flush()
            for piece in splitLongLine(line) {
                chunks.append(TranscriptChunk(text: piece, segmentIDs: [segment.id]))
            }
        }
        flush()
        return chunks
    }

    private func splitLongLine(_ line: String) -> [String] {
        let targetCharacters = 6000
        var pieces: [String] = []
        var current = ""
        for character in line {
            current.append(character)
            if current.count >= targetCharacters {
                pieces.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            pieces.append(current)
        }
        return pieces
    }

    private func estimateTokens(_ text: String) -> Int {
        var cjkCount = 0
        var otherCount = 0
        for scalar in text.unicodeScalars where !CharacterSet.whitespacesAndNewlines.contains(scalar) {
            if isCJK(scalar) {
                cjkCount += 1
            } else {
                otherCount += 1
            }
        }
        return cjkCount + Int(ceil(Double(otherCount) / 4))
    }

    private func isCJK(_ scalar: UnicodeScalar) -> Bool {
        let value = scalar.value
        return (0x3400 ... 0x4DBF).contains(value)
            || (0x4E00 ... 0x9FFF).contains(value)
            || (0xF900 ... 0xFAFF).contains(value)
    }

    private func transcriptFingerprint(_ segments: [MeetingTranscriptSegment]) -> String {
        let canonical = segments.map {
            "\($0.id.uuidString)|\($0.startTime)|\($0.endTime)|\($0.speakerID)|\($0.text)"
        }.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func normalizedList(_ values: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for value in values {
            guard let normalized = normalizedText(value), seen.insert(normalized).inserted else { continue }
            result.append(normalized)
        }
        return result
    }

    private func normalizedCitations(
        _ citations: [MeetingSummaryCitation],
        summary: MeetingSummary,
        allowedSegmentIDs: Set<UUID>
    ) -> [MeetingSummaryCitation] {
        var result: [MeetingSummaryCitation] = []
        var indexesBySignature: [String: Int] = [:]
        for citation in citations where citationMatchesSummary(citation, summary: summary) {
            let sourceIDs = Array(Set(citation.sourceSegmentIDs.filter(allowedSegmentIDs.contains)))
                .sorted { $0.uuidString < $1.uuidString }
            guard !sourceIDs.isEmpty else { continue }
            let signature = "\(citation.kind.rawValue)\u{1F}\(citation.text)"
            if let index = indexesBySignature[signature] {
                result[index].sourceSegmentIDs = Array(
                    Set(result[index].sourceSegmentIDs + sourceIDs)
                ).sorted { $0.uuidString < $1.uuidString }
            } else {
                indexesBySignature[signature] = result.count
                result.append(
                    MeetingSummaryCitation(
                        kind: citation.kind,
                        text: citation.text,
                        sourceSegmentIDs: sourceIDs
                    )
                )
            }
        }
        return result
    }

    private func citationMatchesSummary(
        _ citation: MeetingSummaryCitation,
        summary: MeetingSummary
    ) -> Bool {
        switch citation.kind {
        case .keyPoint:
            summary.keyPoints.contains(citation.text)
        case .decision:
            summary.decisions.contains(citation.text)
        case .actionItem:
            summary.actionItems.contains { $0.task == citation.text }
        case .openQuestion:
            summary.openQuestions.contains(citation.text)
        }
    }

    private func publish(
        _ checkpoint: MeetingSummaryCheckpoint,
        to handler: CheckpointHandler?
    ) async {
        guard let handler else { return }
        await handler(checkpoint)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private struct TranscriptChunk: Sendable {
        let text: String
        let segmentIDs: [UUID]
    }

    private struct SynthesisFact: Encodable {
        let kind: String
        let text: String
        let owner: String
        let dueDate: String
        let sourceSegmentIDs: [UUID]
    }

    private struct SynthesisSummary: Encodable {
        let overview: String
        let keyPoints: [String]
        let decisions: [String]
        let actionItems: [SynthesisActionItem]
        let openQuestions: [String]
        let citations: [MeetingSummaryCitation]?
    }

    private struct SynthesisActionItem: Encodable {
        let task: String
        let owner: String
        let dueDate: String
    }

    private struct FactPayload: Decodable {
        let facts: [DecodedFact]
    }

    private struct DecodedFact: Decodable {
        let kind: String
        let text: String
        let owner: String?
        let dueDate: String?
        let sourceSegmentIDs: [String]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
            text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            owner = try container.decodeIfPresent(String.self, forKey: .owner)
            dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate)
            sourceSegmentIDs = try container.decodeIfPresent([String].self, forKey: .sourceSegmentIDs) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case kind
            case text
            case owner
            case dueDate
            case sourceSegmentIDs
        }
    }

    private struct SummaryPayload: Decodable {
        let overview: String?
        let keyPoints: [String]
        let decisions: [String]
        let actionItems: [DecodedActionItem]
        let openQuestions: [String]
        let citations: [DecodedCitation]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            overview = try container.decodeIfPresent(String.self, forKey: .overview)
            keyPoints = try container.decodeIfPresent([String].self, forKey: .keyPoints) ?? []
            decisions = try container.decodeIfPresent([String].self, forKey: .decisions) ?? []
            actionItems = try container.decodeIfPresent([DecodedActionItem].self, forKey: .actionItems) ?? []
            openQuestions = try container.decodeIfPresent([String].self, forKey: .openQuestions) ?? []
            citations = try container.decodeIfPresent([DecodedCitation].self, forKey: .citations) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case overview
            case keyPoints
            case decisions
            case actionItems
            case openQuestions
            case citations
        }
    }

    private struct DecodedCitation: Decodable {
        let kind: String
        let text: String
        let sourceSegmentIDs: [String]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
            text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            sourceSegmentIDs = try container.decodeIfPresent([String].self, forKey: .sourceSegmentIDs) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case kind
            case text
            case sourceSegmentIDs
        }
    }

    private struct DecodedActionItem: Decodable {
        let task: String
        let owner: String?
        let dueDate: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            task = try container.decodeIfPresent(String.self, forKey: .task) ?? ""
            owner = try container.decodeIfPresent(String.self, forKey: .owner)
            dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate)
        }

        private enum CodingKeys: String, CodingKey {
            case task
            case owner
            case dueDate
        }
    }
}
