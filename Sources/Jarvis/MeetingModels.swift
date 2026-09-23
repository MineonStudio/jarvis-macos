import Foundation

enum MeetingLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case simplifiedChinese = "zh-CN"
    case english = "en-US"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .simplifiedChinese: "中文"
        case .english: "English"
        }
    }
}

enum MeetingRecordStatus: String, Codable, Sendable {
    case recording
    case transcribing
    case transcribed
    case summarizing
    case summaryFailed
    case ready
    case failed

    var title: String {
        switch self {
        case .recording: "正在录音"
        case .transcribing: "正在转写"
        case .transcribed: "转写已完成"
        case .summarizing: "正在生成总结"
        case .summaryFailed: "纪要生成失败"
        case .ready: "纪要已完成"
        case .failed: "处理失败"
        }
    }
}

enum MeetingProcessingStage: String, Sendable {
    case transcribing
    case diarizing
    case summarizing

    var title: String {
        switch self {
        case .transcribing: "正在转写录音"
        case .diarizing: "正在识别说话人"
        case .summarizing: "正在生成会议总结"
        }
    }
}

enum MeetingSummaryStage: String, Codable, Sendable {
    case extractingFacts
    case synthesizing
    case completed
    case failed
}

enum MeetingFactKind: String, Codable, Sendable {
    case keyPoint
    case decision
    case actionItem
    case openQuestion
}

struct MeetingFact: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: MeetingFactKind
    var text: String
    var owner: String
    var dueDate: String
    var sourceSegmentIDs: [UUID]

    init(
        id: UUID = UUID(),
        kind: MeetingFactKind,
        text: String,
        owner: String = "",
        dueDate: String = "",
        sourceSegmentIDs: [UUID] = []
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.owner = owner
        self.dueDate = dueDate
        self.sourceSegmentIDs = sourceSegmentIDs
    }
}

struct MeetingSummaryCheckpoint: Codable, Equatable, Sendable {
    static let currentPipelineVersion = 1

    var pipelineVersion: Int
    var transcriptFingerprint: String
    var stage: MeetingSummaryStage
    var completedChunkCount: Int
    var totalChunkCount: Int
    var facts: [MeetingFact]
    var errorMessage: String?
    var updatedAt: Date

    init(
        transcriptFingerprint: String,
        stage: MeetingSummaryStage,
        completedChunkCount: Int,
        totalChunkCount: Int,
        facts: [MeetingFact] = [],
        errorMessage: String? = nil,
        updatedAt: Date = Date()
    ) {
        pipelineVersion = Self.currentPipelineVersion
        self.transcriptFingerprint = transcriptFingerprint
        self.stage = stage
        self.completedChunkCount = completedChunkCount
        self.totalChunkCount = totalChunkCount
        self.facts = facts
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
    }
}

enum MeetingModelPreparationStage: String, CaseIterable, Identifiable, Sendable {
    case speakerDiarization
    case chineseTranscription

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .speakerDiarization: "说话人识别"
        case .chineseTranscription: "中文语音转写"
        }
    }

    var modelName: String {
        switch self {
        case .speakerDiarization: "pyannote/speaker-diarization-community-1 · Core ML"
        case .chineseTranscription: "Paraformer-large-zh · INT8"
        }
    }
}

struct MeetingModelAvailability: Equatable, Sendable {
    let speakerDiarizationReady: Bool
    let chineseTranscriptionReady: Bool

    var isReady: Bool {
        speakerDiarizationReady && chineseTranscriptionReady
    }

    func isReady(for stage: MeetingModelPreparationStage) -> Bool {
        switch stage {
        case .speakerDiarization: speakerDiarizationReady
        case .chineseTranscription: chineseTranscriptionReady
        }
    }
}

enum MeetingModelOperation: Equatable, Sendable {
    case download
    case remove
}

enum MeetingModelPreparationState: Equatable, Sendable {
    case checking
    case notReady(MeetingModelAvailability)
    case downloading(stage: MeetingModelPreparationStage, progress: Double)
    case removing(MeetingModelPreparationStage)
    case ready
    case failed(stage: MeetingModelPreparationStage?, operation: MeetingModelOperation, message: String)

    var isReady: Bool {
        if case .ready = self {
            return true
        }
        return false
    }
}

enum MeetingProcessingState: Equatable, Sendable {
    case idle
    case recording
    case processing(stage: MeetingProcessingStage, progress: Double)
    case awaitingConfiguration
    case ready
    case failed(String)

    var title: String {
        switch self {
        case .idle: "准备录音"
        case .recording: "正在录音"
        case let .processing(stage, _): stage.title
        case .awaitingConfiguration: "转写已完成，待生成总结"
        case .ready: "纪要已完成"
        case .failed: "处理失败"
        }
    }
}

struct MeetingSpeaker: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    let colorIndex: Int
}

struct MeetingTranscriptSegment: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let startTime: TimeInterval
    let endTime: TimeInterval
    let speakerID: String
    let text: String

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        speakerID: String,
        text: String
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.speakerID = speakerID
        self.text = text
    }
}

struct MeetingActionItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var task: String
    var owner: String
    var dueDate: String

    init(id: UUID = UUID(), task: String, owner: String = "", dueDate: String = "") {
        self.id = id
        self.task = task
        self.owner = owner
        self.dueDate = dueDate
    }
}

struct MeetingSummary: Codable, Equatable, Sendable {
    var overview: String
    var keyPoints: [String]
    var decisions: [String]
    var actionItems: [MeetingActionItem]
    var openQuestions: [String]
}

struct MeetingRecord: Codable, Equatable, Identifiable, Sendable {
    static let defaultTitle = "未命名会议"

    let id: UUID
    var title: String
    let createdAt: Date
    var duration: TimeInterval
    let audioFileName: String
    /// The original microphone track. Older records only have `audioFileName`,
    /// so the repository falls back to that file when this value is nil.
    var microphoneAudioFileName: String?
    /// The original system-audio track captured through ScreenCaptureKit.
    var systemAudioFileName: String?
    /// Seconds to delay the system-audio track when mixing, because ScreenCaptureKit
    /// capture starts after the microphone recorder. Older records treat this as 0.
    var systemAudioStartOffset: TimeInterval?
    var language: MeetingLanguage
    var status: MeetingRecordStatus
    var speakers: [MeetingSpeaker]
    var transcript: [MeetingTranscriptSegment]
    var summary: MeetingSummary?
    var summaryCheckpoint: MeetingSummaryCheckpoint?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        audioFileName: String,
        microphoneAudioFileName: String? = nil,
        systemAudioFileName: String? = nil,
        systemAudioStartOffset: TimeInterval? = nil,
        language: MeetingLanguage = .simplifiedChinese,
        status: MeetingRecordStatus = .recording,
        speakers: [MeetingSpeaker] = [],
        transcript: [MeetingTranscriptSegment] = [],
        summary: MeetingSummary? = nil,
        summaryCheckpoint: MeetingSummaryCheckpoint? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.audioFileName = audioFileName
        self.microphoneAudioFileName = microphoneAudioFileName
        self.systemAudioFileName = systemAudioFileName
        self.systemAudioStartOffset = systemAudioStartOffset
        self.language = language
        self.status = status
        self.speakers = speakers
        self.transcript = transcript
        self.summary = summary
        self.summaryCheckpoint = summaryCheckpoint
        self.errorMessage = errorMessage
    }

    static func isLegacyGeneratedTitle(_ title: String, createdAt: Date) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return title == "会议 · \(formatter.string(from: createdAt))"
    }

    var resolvedSystemAudioStartOffset: TimeInterval {
        max(0, systemAudioStartOffset ?? 0)
    }

    var canRetryProcessing: Bool {
        switch status {
        case .failed, .summaryFailed, .transcribed, .transcribing, .summarizing:
            true
        case .recording, .ready:
            false
        }
    }

    func matchesSearch(_ rawQuery: String) -> Bool {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if title.meetingSearchContains(query) || status.title.meetingSearchContains(query) {
            return true
        }
        return transcript.contains { $0.text.meetingSearchContains(query) }
    }

    mutating func applyInterruptedLaunchRecovery() {
        switch status {
        case .recording:
            status = .failed
            errorMessage = "应用上次退出时录音未正常结束；已保留已写入的原始录音，可重新处理"
        case .transcribing:
            status = .failed
            errorMessage = "转写中断，原始录音已保留，可重新处理"
        case .summarizing:
            if transcript.isEmpty {
                status = .failed
                errorMessage = "总结中断，原始录音已保留，可重新处理"
            } else {
                status = .summaryFailed
                errorMessage = "总结中断，已保留逐字稿，可重新生成纪要"
            }
        case .transcribed, .summaryFailed, .ready, .failed:
            break
        }
    }
}

private extension String {
    /// Substring match without locale word-breaking. Chinese locales treat
    /// `localizedCaseInsensitiveContains` as a linguistic search, so a single
    /// character like "会" does not match "会议".
    func meetingSearchContains(_ query: String) -> Bool {
        range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        ) != nil
    }
}

struct MeetingRecordDetail: Codable, Equatable, Sendable {
    var speakers: [MeetingSpeaker]
    var transcript: [MeetingTranscriptSegment]
    var summary: MeetingSummary?
    var summaryCheckpoint: MeetingSummaryCheckpoint?

    var isEmpty: Bool {
        speakers.isEmpty && transcript.isEmpty && summary == nil && summaryCheckpoint == nil
    }
}

extension MeetingRecord {
    var detail: MeetingRecordDetail {
        MeetingRecordDetail(
            speakers: speakers,
            transcript: transcript,
            summary: summary,
            summaryCheckpoint: summaryCheckpoint
        )
    }

    var metadataCopy: MeetingRecord {
        var copy = self
        copy.speakers = []
        copy.transcript = []
        copy.summary = nil
        copy.summaryCheckpoint = nil
        return copy
    }

    mutating func applyDetail(_ detail: MeetingRecordDetail) {
        speakers = detail.speakers
        transcript = detail.transcript
        summary = detail.summary
        summaryCheckpoint = detail.summaryCheckpoint
    }

    func markdownDocument() -> String {
        var lines: [String] = [
            "# \(title)",
            "",
            "- 时间：\(createdAt.formatted(date: .long, time: .shortened))",
            "- 时长：\(MeetingRecordingStyle.formatDuration(duration))",
            "- 状态：\(status.title)"
        ]
        if let summary {
            lines.append("")
            lines.append("## 会议总结")
            if !summary.overview.isEmpty {
                lines.append("")
                lines.append(summary.overview)
            }
            appendMarkdownList(title: "关键讨论", items: summary.keyPoints, to: &lines)
            appendMarkdownList(title: "明确决策", items: summary.decisions, to: &lines)
            if !summary.actionItems.isEmpty {
                lines.append("")
                lines.append("## 待办事项")
                lines.append("")
                for item in summary.actionItems {
                    var task = "- \(item.task)"
                    if !item.owner.isEmpty {
                        task += "（负责人：\(item.owner)）"
                    }
                    if !item.dueDate.isEmpty {
                        task += " 截止：\(item.dueDate)"
                    }
                    lines.append(task)
                }
            }
            appendMarkdownList(title: "未解决问题", items: summary.openQuestions, to: &lines)
        }
        if !transcript.isEmpty {
            lines.append("")
            lines.append("## 逐字稿")
            lines.append("")
            for segment in transcript {
                let speaker = speakers.first { $0.id == segment.speakerID }?.name ?? segment.speakerID
                lines.append("**\(speaker)** \(MeetingRecordingStyle.formatTimestamp(segment.startTime))")
                lines.append("")
                lines.append(segment.text)
                lines.append("")
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func appendMarkdownList(title: String, items: [String], to lines: inout [String]) {
        guard !items.isEmpty else { return }
        lines.append("")
        lines.append("## \(title)")
        lines.append("")
        for item in items {
            lines.append("- \(item)")
        }
    }
}

struct MeetingTranscriptionResult: Sendable {
    let speakers: [MeetingSpeaker]
    let segments: [MeetingTranscriptSegment]
}
