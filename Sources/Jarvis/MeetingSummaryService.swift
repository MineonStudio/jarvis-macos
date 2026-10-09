import CryptoKit
import Foundation

enum MeetingMinutesError: LocalizedError, Equatable {
    case schemaRejected
    case network
    case quota
    case tooLong

    var errorDescription: String? {
        switch self {
        case .schemaRejected:
            "纪要格式连续两次不合格，没有写入半成品。逐字稿已保留，可以重试。"
        case .network:
            "生成纪要时网络不可用。逐字稿已保留，可以重试。"
        case .quota:
            "AI 服务额度不足。逐字稿已保留，可以稍后重试。"
        case .tooLong:
            "逐字稿过长，模型没有完成纪要。逐字稿已保留，可以重试。"
        }
    }

    static func classify(_ error: Error) -> Error {
        if error is CancellationError || error is MeetingMinutesError {
            return error
        }
        if error is URLError {
            return MeetingMinutesError.network
        }
        let description = error.localizedDescription
        // DeepSeek reports an empty account as "Insufficient Balance", not 429 or quota.
        // Bare "余额" or "balance" is not a billing refusal.
        if description.contains("429")
            || description.contains("额度")
            || description.contains("余额不足")
            || description.localizedCaseInsensitiveContains("insufficient balance")
            || description.localizedCaseInsensitiveContains("quota")
        {
            return MeetingMinutesError.quota
        }
        if description.localizedCaseInsensitiveContains("context")
            || description.contains("过长")
            || description.contains("maximum context")
        {
            return MeetingMinutesError.tooLong
        }
        return error
    }
}

struct MeetingSummaryService: Sendable {
    typealias CheckpointHandler = @MainActor @Sendable (MeetingSummaryCheckpoint) -> Void
    typealias ProgressHandler = @MainActor @Sendable (Double?) -> Void

    let api: any AITextCompletionAPI

    private static let maxConcurrentSummaryRequests = 3
    private static let transcriptChunkTargetTokens = 4200

    func summarize(
        record: MeetingRecord,
        configuration: AIAPIConfiguration,
        checkpoint: MeetingSummaryCheckpoint? = nil,
        preserveUserEdits: Bool = true,
        onCheckpoint: CheckpointHandler? = nil,
        onProgress: ProgressHandler? = nil
    ) async throws -> MeetingSummary {
        do {
            return try await summarizeUnchecked(
                record: record,
                configuration: configuration,
                checkpoint: checkpoint,
                preserveUserEdits: preserveUserEdits,
                onCheckpoint: onCheckpoint,
                onProgress: onProgress
            )
        } catch {
            throw MeetingMinutesError.classify(error)
        }
    }

    private func summarizeUnchecked(
        record: MeetingRecord,
        configuration: AIAPIConfiguration,
        checkpoint: MeetingSummaryCheckpoint?,
        preserveUserEdits: Bool,
        onCheckpoint: CheckpointHandler?,
        onProgress: ProgressHandler?
    ) async throws -> MeetingSummary {
        let chunks = makeChunks(from: record.transcript, speakers: record.speakers)
        guard !chunks.isEmpty else {
            throw AIAPIError.emptyGeneratedContent(context: "会议逐字稿")
        }
        let fingerprint = transcriptFingerprint(record.transcript)
        if let finished = resumableFinishedSummary(checkpoint, fingerprint: fingerprint) {
            return preserveUserEdits
                ? MeetingMinutesAlgorithm.merging(finished, preserving: record.summary)
                : finished
        }

        let resumable = resumableCheckpoint(checkpoint, fingerprint: fingerprint, chunkCount: chunks.count)
        if chunks.count == 1 {
            await report(nil, to: onProgress)
            let summary = try await requestMinutes(
                record: record,
                chunk: chunks[0],
                configuration: configuration,
                fingerprint: fingerprint,
                windowLabel: nil
            )
            let merged = preserveUserEdits
                ? MeetingMinutesAlgorithm.merging(summary, preserving: record.summary)
                : summary
            await publish(
                finishedCheckpoint(
                    fingerprint: fingerprint,
                    chunkCount: 1,
                    windows: [summary],
                    finished: merged
                ),
                to: onCheckpoint
            )
            return merged
        }

        var windows = resumable?.windowSummaries ?? []
        let completed = min(windows.count, chunks.count)
        await report(
            Self.summaryProgress(
                completedChunks: completed,
                totalChunks: chunks.count,
                completedSynthesisSteps: 0,
                totalSynthesisSteps: 1
            ),
            to: onProgress
        )
        if completed < chunks.count {
            windows = try await requestWindows(
                record: record,
                chunks: chunks,
                configuration: configuration,
                fingerprint: fingerprint,
                completed: completed,
                windows: windows,
                onCheckpoint: onCheckpoint,
                onProgress: onProgress
            )
        }

        await report(
            Self.summaryProgress(
                completedChunks: chunks.count,
                totalChunks: chunks.count,
                completedSynthesisSteps: 0,
                totalSynthesisSteps: 1
            ),
            to: onProgress
        )
        let mergedDraft: MeetingSummary
        do {
            mergedDraft = try await requestMergedMinutes(
                record: record,
                windows: windows,
                configuration: configuration,
                fingerprint: fingerprint
            )
        } catch {
            // Window calls already succeeded. The next 重新生成 still tries this merge
            // first. Only an empty account keeps those windows, without inventing text.
            let classified = MeetingMinutesError.classify(error)
            if let minutesError = classified as? MeetingMinutesError,
               minutesError == .quota,
               let stitched = MeetingMinutesAlgorithm.combiningWindows(windows)
            {
                JarvisLog.info(
                    category: .meeting,
                    event: "summary.merge_quota_stitched",
                    fields: [
                        "meetingID": record.id.uuidString,
                        "windows": String(windows.count)
                    ]
                )
                mergedDraft = stitched
            } else {
                throw error
            }
        }
        let merged = preserveUserEdits
            ? MeetingMinutesAlgorithm.merging(mergedDraft, preserving: record.summary)
            : mergedDraft
        await report(
            Self.summaryProgress(
                completedChunks: chunks.count,
                totalChunks: chunks.count,
                completedSynthesisSteps: 1,
                totalSynthesisSteps: 1
            ),
            to: onProgress
        )
        await publish(
            finishedCheckpoint(
                fingerprint: fingerprint,
                chunkCount: chunks.count,
                windows: windows,
                finished: merged
            ),
            to: onCheckpoint
        )
        return merged
    }

    /// Extraction fills the first 80% of the bar. The merge uses the rest, and
    /// stops at 99 so 100% is reserved for the finished state.
    static func summaryProgress(
        completedChunks: Int,
        totalChunks: Int,
        completedSynthesisSteps: Int,
        totalSynthesisSteps: Int
    ) -> Double {
        let safeChunks = max(totalChunks, 1)
        let extraction = 0.8 * Double(min(max(completedChunks, 0), safeChunks)) / Double(safeChunks)
        let safeSteps = max(totalSynthesisSteps, 1)
        let synthesis = 0.19 * Double(min(max(completedSynthesisSteps, 0), safeSteps)) / Double(safeSteps)
        return min(0.99, extraction + synthesis)
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

    private func requestWindows(
        record: MeetingRecord,
        chunks: [TranscriptChunk],
        configuration: AIAPIConfiguration,
        fingerprint: String,
        completed: Int,
        windows: [MeetingSummary],
        onCheckpoint: CheckpointHandler?,
        onProgress: ProgressHandler?
    ) async throws -> [MeetingSummary] {
        var windows = windows
        var completedPrefix = completed
        var nextIndex = completed
        var buffered: [Int: MeetingSummary] = [:]
        try await withThrowingTaskGroup(of: (Int, MeetingSummary).self) { group in
            func enqueue() {
                guard nextIndex < chunks.count else { return }
                let index = nextIndex
                nextIndex += 1
                let chunk = chunks[index]
                group.addTask { [self] in
                    let summary = try await self.requestMinutes(
                        record: record,
                        chunk: chunk,
                        configuration: configuration,
                        fingerprint: fingerprint,
                        windowLabel: "第 \(index + 1)/\(chunks.count) 段"
                    )
                    return (index, summary)
                }
            }

            let initialCount = min(Self.maxConcurrentSummaryRequests, chunks.count - completed)
            for _ in 0 ..< initialCount {
                enqueue()
            }

            for try await (index, summary) in group {
                buffered[index] = summary
                while let ready = buffered.removeValue(forKey: completedPrefix) {
                    windows.append(ready)
                    completedPrefix += 1
                    var checkpoint = MeetingSummaryCheckpoint(
                        transcriptFingerprint: fingerprint,
                        stage: .extractingFacts,
                        completedChunkCount: completedPrefix,
                        totalChunkCount: chunks.count
                    )
                    checkpoint.windowSummaries = windows
                    await publish(checkpoint, to: onCheckpoint)
                    await report(
                        Self.summaryProgress(
                            completedChunks: completedPrefix,
                            totalChunks: chunks.count,
                            completedSynthesisSteps: 0,
                            totalSynthesisSteps: 1
                        ),
                        to: onProgress
                    )
                }
                enqueue()
            }
        }
        return windows
    }

    private func requestMinutes(
        record: MeetingRecord,
        chunk: TranscriptChunk,
        configuration: AIAPIConfiguration,
        fingerprint: String,
        windowLabel: String?
    ) async throws -> MeetingSummary {
        var correction: String?
        var lastResult: MeetingMinutesAlgorithm.ValidationResult?
        for attempt in 0 ..< 2 {
            do {
                let raw = try await api.complete(
                    systemPrompt: Self.systemPrompt,
                    userPrompt: userPrompt(
                        record: record,
                        transcript: chunk.text,
                        windowLabel: windowLabel,
                        correction: correction
                    ),
                    configuration: configuration,
                    options: .meetingSummary
                )
                let result = try validate(raw, record: record, configuration: configuration, fingerprint: fingerprint)
                lastResult = result
                logDrops(result, meetingID: record.id)
                if attempt == 0, result.summaryOutsidePreferredRange || result.droppedAllCitedItems || result.summary.overview.isEmpty {
                    correction = retryCorrection(for: result)
                    continue
                }
                return result.summary
            } catch is CancellationError {
                throw CancellationError()
            } catch is MeetingMinutesError {
                if attempt == 1 {
                    throw MeetingMinutesError.schemaRejected
                }
                correction = "输出不是规定的 JSON。"
            }
        }
        if let lastResult, !lastResult.summary.overview.isEmpty || !lastResult.summary.points.isEmpty || !lastResult.summary.actionItems.isEmpty {
            return lastResult.summary
        }
        throw MeetingMinutesError.schemaRejected
    }

    private func requestMergedMinutes(
        record: MeetingRecord,
        windows: [MeetingSummary],
        configuration: AIAPIConfiguration,
        fingerprint: String
    ) async throws -> MeetingSummary {
        let payload = try windows.enumerated().map { index, summary -> String in
            let data = try JSONEncoder().encode(MergePayload(summary))
            let json = String(decoding: data, as: UTF8.self)
            return "第 \(index + 1) 段纪要：\n\(json)"
        }.joined(separator: "\n\n")
        var correction: String?
        var lastResult: MeetingMinutesAlgorithm.ValidationResult?
        for attempt in 0 ..< 2 {
            do {
                let raw = try await api.complete(
                    systemPrompt: Self.systemPrompt,
                    userPrompt: """
                    下面是同一场会议按时间顺序切分后的纪要。请合并成一份。
                    不要丢掉中间段。同一事项只保留一次。evidence 里的 quote、segment_id、start_ms、end_ms 必须原样保留，而且 quote 仍是逐字稿中的连续原文。
                    概要写成 200 到 400 字。
                    \(correction.map { "上一次输出不合格：\($0)" } ?? "")

                    \(payload)
                    """,
                    configuration: configuration,
                    options: .meetingSummary
                )
                let result = try validate(raw, record: record, configuration: configuration, fingerprint: fingerprint)
                lastResult = result
                logDrops(result, meetingID: record.id)
                if attempt == 0, result.summaryOutsidePreferredRange || result.droppedAllCitedItems || result.summary.overview.isEmpty {
                    correction = retryCorrection(for: result)
                    continue
                }
                return result.summary
            } catch is CancellationError {
                throw CancellationError()
            } catch is MeetingMinutesError {
                if attempt == 1 {
                    throw MeetingMinutesError.schemaRejected
                }
                correction = "输出不是规定的 JSON。"
            }
        }
        if let lastResult, !lastResult.summary.overview.isEmpty || !lastResult.summary.points.isEmpty || !lastResult.summary.actionItems.isEmpty {
            return lastResult.summary
        }
        throw MeetingMinutesError.schemaRejected
    }

    private func validate(
        _ raw: String,
        record: MeetingRecord,
        configuration: AIAPIConfiguration,
        fingerprint: String
    ) throws -> MeetingMinutesAlgorithm.ValidationResult {
        let extracted = Self.extractJSONObject(raw)
        guard let data = extracted.data(using: .utf8) else {
            throw MeetingMinutesError.schemaRejected
        }
        let draft: MeetingMinutesAlgorithm.DraftMinutes
        do {
            draft = try JSONDecoder().decode(MeetingMinutesAlgorithm.DraftMinutes.self, from: data)
        } catch {
            throw MeetingMinutesError.schemaRejected
        }
        let generation = MeetingMinutesGeneration(
            modelName: configuration.model,
            promptVersion: MeetingMinutesAlgorithm.promptVersion,
            generatedAt: Date(),
            transcriptFingerprint: fingerprint
        )
        return MeetingMinutesAlgorithm.validate(
            draft,
            transcript: record.transcript,
            speakers: record.speakers,
            meetingDate: record.createdAt,
            generation: generation
        )
    }

    private func retryCorrection(for result: MeetingMinutesAlgorithm.ValidationResult) -> String {
        if result.summary.overview.isEmpty {
            return "缺少 summary。"
        }
        if result.droppedAllCitedItems {
            return "要点和待办的 quote 必须是对应 segment 里的连续原文，不能改写。"
        }
        if result.summaryOutsidePreferredRange {
            return "summary 需要 200 到 400 字，当前是 \(result.summaryCharacterCount) 字。"
        }
        return "输出必须是规定的 JSON。"
    }

    private func logDrops(_ result: MeetingMinutesAlgorithm.ValidationResult, meetingID: UUID) {
        guard !result.log.droppedPointIDs.isEmpty || !result.log.droppedTodoIDs.isEmpty else { return }
        JarvisLog.info(
            category: .meeting,
            event: "summary.dropped_items",
            fields: [
                "meetingID": meetingID.uuidString,
                "points": result.log.droppedPointIDs.joined(separator: ","),
                "todos": result.log.droppedTodoIDs.joined(separator: ",")
            ]
        )
    }

    private struct MergePayload: Encodable {
        struct Point: Encodable {
            var id: String
            var title: String
            var detail: String
            var evidence: [Evidence]
        }

        struct Todo: Encodable {
            var id: String
            var task: String
            var owner: String?
            var due: String?
            var evidence: [Evidence]
        }

        struct Evidence: Encodable {
            var segment_id: String
            var start_ms: Int
            var end_ms: Int
            var quote: String
        }

        var summary: String
        var points: [Point]
        var todos: [Todo]

        init(_ summary: MeetingSummary) {
            self.summary = summary.overview
            points = summary.points.map { point in
                Point(
                    id: point.id,
                    title: point.title,
                    detail: point.detail,
                    evidence: point.evidence.map {
                        Evidence(
                            segment_id: $0.segmentID.uuidString,
                            start_ms: $0.startMs,
                            end_ms: $0.endMs,
                            quote: $0.quote
                        )
                    }
                )
            }
            todos = summary.actionItems.map { item in
                Todo(
                    id: item.id.uuidString,
                    task: item.task,
                    owner: item.owner.isEmpty ? nil : item.owner,
                    due: item.dueDate.isEmpty ? nil : item.dueDate,
                    evidence: item.evidence.map {
                        Evidence(
                            segment_id: $0.segmentID.uuidString,
                            start_ms: $0.startMs,
                            end_ms: $0.endMs,
                            quote: $0.quote
                        )
                    }
                )
            }
        }
    }

    private func finishedCheckpoint(
        fingerprint: String,
        chunkCount: Int,
        windows: [MeetingSummary],
        finished: MeetingSummary
    ) -> MeetingSummaryCheckpoint {
        var checkpoint = MeetingSummaryCheckpoint(
            transcriptFingerprint: fingerprint,
            stage: .completed,
            completedChunkCount: chunkCount,
            totalChunkCount: chunkCount,
            directSummary: chunkCount == 1
        )
        checkpoint.windowSummaries = windows
        checkpoint.finishedSummary = finished
        return checkpoint
    }

    private func resumableFinishedSummary(
        _ checkpoint: MeetingSummaryCheckpoint?,
        fingerprint: String
    ) -> MeetingSummary? {
        guard let checkpoint,
              checkpoint.pipelineVersion == MeetingSummaryCheckpoint.currentPipelineVersion,
              checkpoint.transcriptFingerprint == fingerprint,
              checkpoint.stage == .completed,
              let finished = checkpoint.finishedSummary
        else { return nil }
        return finished
    }

    private func resumableCheckpoint(
        _ checkpoint: MeetingSummaryCheckpoint?,
        fingerprint: String,
        chunkCount: Int
    ) -> MeetingSummaryCheckpoint? {
        guard let checkpoint,
              checkpoint.pipelineVersion == MeetingSummaryCheckpoint.currentPipelineVersion,
              checkpoint.transcriptFingerprint == fingerprint,
              checkpoint.totalChunkCount == chunkCount,
              let windows = checkpoint.windowSummaries,
              windows.count <= chunkCount
        else { return nil }
        return checkpoint
    }

    private static let systemPrompt = """
    你是会议纪要编辑。只根据给出的逐字稿写中文纪要。禁止补充逐字稿里没有的事实、人名、数字、日期或结论。
    只输出一个 JSON 对象，不要 Markdown，不要解释。

    {
      "summary": "200到400字的概要",
      "points": [
        {
          "id": "P1",
          "title": "这个议题的结论或分歧",
          "detail": "展开说明，不能加入逐字稿没有的事实",
          "evidence": [
            {"segment_id": "逐字稿片段ID", "start_ms": 0, "end_ms": 0, "quote": "该片段中的连续原文"}
          ]
        }
      ],
      "todos": [
        {
          "id": "T1",
          "task": "一句完整、可执行的待办",
          "owner": null,
          "due": null,
          "owner_missing": "未指定",
          "due_missing": "未提及",
          "evidence": [
            {"segment_id": "逐字稿片段ID", "start_ms": 0, "end_ms": 0, "quote": "该片段中的连续原文"}
          ]
        }
      ]
    }

    规则：
    - 每个 point 和每个 todo 至少一条 evidence。quote 必须是对应 segment 文本里的连续原文，不要改写，不要编造。
    - segment_id、start_ms、end_ms 使用输入里给出的值。
    - title 和 detail 可以归纳，但不能加入输入里没有的事实。
    - 待办写成完整任务，不要照抄半句口头语，也不要把没有答应要做的话写成待办。
    - owner 只能使用逐字稿、quote 或说话人显示名里出现过的名字。没有明确负责人时 owner 为 null，owner_missing 为「未指定」。不要猜测或编造人名。
    - 没有明确期限时 due 为 null，due_missing 为「未提及」。「待会」「回头」「尽快」不是期限。
    - 相对时间保留原话，例如「下周三」，不要改成你自己推算的日期。
    - 讨论要点写结论和分歧。不要把寒暄、确认能否听到、卡顿、散会写成要点。
    - 没有依据的 point 或 todo 不要输出。
    """

    private func userPrompt(
        record: MeetingRecord,
        transcript: String,
        windowLabel: String?,
        correction: String?
    ) -> String {
        let speakers = record.speakers.map(\.name).joined(separator: "、")
        let scope = windowLabel.map { "这是会议的\($0)，只根据这一段写。" } ?? "这是完整逐字稿。"
        let retry = correction.map { "上一次输出不合格：\($0) 请按 schema 重写。" } ?? ""
        return """
        会议：\(record.title)
        会议日期：\(record.createdAt.formatted(date: .numeric, time: .omitted))
        说话人：\(speakers)
        \(scope)
        \(retry)

        逐字稿每一行的格式是 [start_ms][end_ms][segment_id] 说话人：原文
        \(transcript)
        """
    }

    private func makeChunks(
        from segments: [MeetingTranscriptSegment],
        speakers: [MeetingSpeaker]
    ) -> [TranscriptChunk] {
        let speakerNames = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0.name) })
        var chunks: [TranscriptChunk] = []
        var currentLines: [String] = []

        func flush() {
            guard !currentLines.isEmpty else { return }
            chunks.append(TranscriptChunk(text: currentLines.joined(separator: "\n")))
            currentLines.removeAll(keepingCapacity: true)
        }

        for segment in segments {
            let speaker = speakerNames[segment.speakerID] ?? segment.speakerID
            let startMs = Int((segment.startTime * 1000).rounded())
            let endMs = Int((segment.endTime * 1000).rounded())
            let header = "[\(startMs)][\(endMs)][\(segment.id.uuidString)] \(speaker)："
            let line = header + segment.text
            if estimateTokens(line) <= Self.transcriptChunkTargetTokens {
                let candidate = (currentLines + [line]).joined(separator: "\n")
                if !currentLines.isEmpty, estimateTokens(candidate) > Self.transcriptChunkTargetTokens {
                    flush()
                }
                currentLines.append(line)
                continue
            }
            flush()
            for piece in splitLongLine(body: segment.text) {
                chunks.append(TranscriptChunk(text: header + piece))
            }
        }
        flush()
        return chunks
    }

    private func splitLongLine(body: String) -> [String] {
        let targetCharacters = 6000
        var pieces: [String] = []
        var current = ""
        for character in body {
            current.append(character)
            if current.count >= targetCharacters {
                pieces.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            pieces.append(current)
        }
        return pieces.isEmpty ? [body] : pieces
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

    private func publish(_ checkpoint: MeetingSummaryCheckpoint, to handler: CheckpointHandler?) async {
        guard let handler else { return }
        await handler(checkpoint)
    }

    private func report(_ progress: Double?, to handler: ProgressHandler?) async {
        guard let handler else { return }
        await handler(progress)
    }

    private struct TranscriptChunk: Sendable {
        let text: String
    }
}
