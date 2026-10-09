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
    static let currentPipelineVersion = 2

    var pipelineVersion: Int
    var transcriptFingerprint: String
    var stage: MeetingSummaryStage
    var completedChunkCount: Int
    var totalChunkCount: Int
    var facts: [MeetingFact]
    /// Set when the summary was produced in one request, without fact extraction.
    var directSummary: Bool?
    var errorMessage: String?
    var updatedAt: Date
    /// Window minutes already accepted. A resumed run does not repeat those windows.
    var windowSummaries: [MeetingSummary]?
    /// Present only after a run finished. Resuming that checkpoint does not call the API again.
    var finishedSummary: MeetingSummary?

    init(
        transcriptFingerprint: String,
        stage: MeetingSummaryStage,
        completedChunkCount: Int,
        totalChunkCount: Int,
        facts: [MeetingFact] = [],
        directSummary: Bool? = nil,
        errorMessage: String? = nil,
        updatedAt: Date = Date()
    ) {
        pipelineVersion = Self.currentPipelineVersion
        self.transcriptFingerprint = transcriptFingerprint
        self.stage = stage
        self.completedChunkCount = completedChunkCount
        self.totalChunkCount = totalChunkCount
        self.facts = facts
        self.directSummary = directSummary
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
        windowSummaries = nil
        finishedSummary = nil
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
        case .chineseTranscription: "系统中文语音资源，下载一次后可离线使用。应用不内置转写模型。"
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
    case processing(stage: MeetingProcessingStage, progress: Double?)
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
    var speakerID: String
    let text: String
    var confidence: Double?
    var isUncertainSpeaker: Bool

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        speakerID: String,
        text: String,
        confidence: Double? = nil,
        isUncertainSpeaker: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.speakerID = speakerID
        self.text = text
        self.confidence = confidence
        self.isUncertainSpeaker = isUncertainSpeaker
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case startTime
        case endTime
        case speakerID
        case text
        case confidence
        case isUncertainSpeaker
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startTime = try container.decode(TimeInterval.self, forKey: .startTime)
        endTime = try container.decode(TimeInterval.self, forKey: .endTime)
        speakerID = try container.decode(String.self, forKey: .speakerID)
        text = try container.decode(String.self, forKey: .text)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        isUncertainSpeaker = try container.decodeIfPresent(Bool.self, forKey: .isUncertainSpeaker) ?? false
    }
}

struct MeetingEvidence: Codable, Equatable, Sendable, Identifiable {
    var segmentID: UUID
    var startMs: Int
    var endMs: Int
    var quote: String

    var id: String {
        "\(segmentID.uuidString)|\(startMs)|\(quote)"
    }
}

struct MeetingDiscussionPoint: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var detail: String
    var evidence: [MeetingEvidence]
    var isUserEdited: Bool

    init(
        id: String,
        title: String,
        detail: String,
        evidence: [MeetingEvidence],
        isUserEdited: Bool = false
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.evidence = evidence
        self.isUserEdited = isUserEdited
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case detail
        case evidence
        case isUserEdited
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        evidence = try container.decodeIfPresent([MeetingEvidence].self, forKey: .evidence) ?? []
        isUserEdited = try container.decodeIfPresent(Bool.self, forKey: .isUserEdited) ?? false
    }
}

struct MeetingMinutesGeneration: Codable, Equatable, Sendable {
    var modelName: String
    var promptVersion: String
    var generatedAt: Date
    var transcriptFingerprint: String
}

struct MeetingActionItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var task: String
    var owner: String
    var dueDate: String
    var isCompleted: Bool
    var evidence: [MeetingEvidence]
    var ownerMissing: String?
    var dueMissing: String?
    var isUserEdited: Bool

    init(
        id: UUID = UUID(),
        task: String,
        owner: String = "",
        dueDate: String = "",
        isCompleted: Bool = false,
        evidence: [MeetingEvidence] = [],
        ownerMissing: String? = nil,
        dueMissing: String? = nil,
        isUserEdited: Bool = false
    ) {
        self.id = id
        self.task = task
        self.owner = owner
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.evidence = evidence
        self.ownerMissing = ownerMissing
        self.dueMissing = dueMissing
        self.isUserEdited = isUserEdited
    }

    var ownerLabel: String {
        let name = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }
        return ownerMissing ?? MeetingMinutesAlgorithm.ownerMissingLabel
    }

    var dueLabel: String {
        let due = dueDate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !due.isEmpty {
            return due
        }
        return dueMissing ?? MeetingMinutesAlgorithm.dueMissingLabel
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case task
        case owner
        case dueDate
        case isCompleted
        case evidence
        case ownerMissing
        case dueMissing
        case isUserEdited
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        task = try container.decode(String.self, forKey: .task)
        owner = try container.decodeIfPresent(String.self, forKey: .owner) ?? ""
        dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate) ?? ""
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        evidence = try container.decodeIfPresent([MeetingEvidence].self, forKey: .evidence) ?? []
        ownerMissing = try container.decodeIfPresent(String.self, forKey: .ownerMissing)
        dueMissing = try container.decodeIfPresent(String.self, forKey: .dueMissing)
        isUserEdited = try container.decodeIfPresent(Bool.self, forKey: .isUserEdited) ?? false
    }
}

struct MeetingSummaryCitation: Codable, Equatable, Sendable {
    let kind: MeetingFactKind
    let text: String
    var sourceSegmentIDs: [UUID]
}

struct MeetingSummary: Codable, Equatable, Sendable {
    var overview: String
    var keyPoints: [String]
    var decisions: [String]
    var actionItems: [MeetingActionItem]
    var openQuestions: [String]
    var citations: [MeetingSummaryCitation]?
    var points: [MeetingDiscussionPoint]
    var overviewIsUserEdited: Bool
    var generation: MeetingMinutesGeneration?

    init(
        overview: String,
        keyPoints: [String],
        decisions: [String],
        actionItems: [MeetingActionItem],
        openQuestions: [String],
        citations: [MeetingSummaryCitation]? = nil,
        points: [MeetingDiscussionPoint] = [],
        overviewIsUserEdited: Bool = false,
        generation: MeetingMinutesGeneration? = nil
    ) {
        self.overview = overview
        self.keyPoints = keyPoints
        self.decisions = decisions
        self.actionItems = actionItems
        self.openQuestions = openQuestions
        self.citations = citations
        self.points = points
        self.overviewIsUserEdited = overviewIsUserEdited
        self.generation = generation
    }

    /// Old records stored three lists. New records store `points`. Display uses points when present.
    var renderedPoints: [MeetingDiscussionPoint] {
        if !points.isEmpty {
            return points
        }
        var synthesized: [MeetingDiscussionPoint] = []
        func append(texts: [String], prefix: String) {
            for (index, text) in texts.enumerated() where !text.isEmpty {
                let evidence = (citations ?? [])
                    .filter { $0.text == text }
                    .flatMap(\.sourceSegmentIDs)
                    .map { MeetingEvidence(segmentID: $0, startMs: 0, endMs: 0, quote: text) }
                synthesized.append(
                    MeetingDiscussionPoint(
                        id: "\(prefix)\(index + 1)",
                        title: text,
                        detail: "",
                        evidence: evidence
                    )
                )
            }
        }
        append(texts: decisions, prefix: "D")
        append(texts: openQuestions, prefix: "Q")
        append(texts: keyPoints, prefix: "K")
        return synthesized
    }

    private enum CodingKeys: String, CodingKey {
        case overview
        case keyPoints
        case decisions
        case actionItems
        case openQuestions
        case citations
        case points
        case overviewIsUserEdited
        case generation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overview = try container.decodeIfPresent(String.self, forKey: .overview) ?? ""
        keyPoints = try container.decodeIfPresent([String].self, forKey: .keyPoints) ?? []
        decisions = try container.decodeIfPresent([String].self, forKey: .decisions) ?? []
        actionItems = try container.decodeIfPresent([MeetingActionItem].self, forKey: .actionItems) ?? []
        openQuestions = try container.decodeIfPresent([String].self, forKey: .openQuestions) ?? []
        citations = try container.decodeIfPresent([MeetingSummaryCitation].self, forKey: .citations)
        points = try container.decodeIfPresent([MeetingDiscussionPoint].self, forKey: .points) ?? []
        overviewIsUserEdited = try container.decodeIfPresent(Bool.self, forKey: .overviewIsUserEdited) ?? false
        generation = try container.decodeIfPresent(MeetingMinutesGeneration.self, forKey: .generation)
    }
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
    /// Set when a recording was still open at the last launch. Processing stays manual.
    var interruptedRecording: Bool?
    /// Nil on records written before capture mode existed. Playback then infers it from the system track.
    var captureMode: MeetingCaptureMode?
    var audioChunks: [MeetingAudioChunk]
    var audioEvents: [MeetingAudioEvent]
    /// True when the row was created before speech assets were installed.
    var awaitingAssets: Bool?
    var diarizationDegraded: Bool?
    var diarizationDegradeReason: String?
    var estimatedSpeakerCount: Int?
    var uncertainSegmentRatio: Double?
    var speakerTurns: [MeetingSpeakerTurnRecord]
    var segmentSpeakerOverrides: [MeetingSegmentSpeakerOverride]
    var minutesVersions: [MeetingMinutesVersion]

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
        errorMessage: String? = nil,
        interruptedRecording: Bool? = nil,
        captureMode: MeetingCaptureMode? = nil,
        audioChunks: [MeetingAudioChunk] = [],
        audioEvents: [MeetingAudioEvent] = [],
        awaitingAssets: Bool? = nil,
        diarizationDegraded: Bool? = nil,
        diarizationDegradeReason: String? = nil,
        estimatedSpeakerCount: Int? = nil,
        uncertainSegmentRatio: Double? = nil,
        speakerTurns: [MeetingSpeakerTurnRecord] = [],
        segmentSpeakerOverrides: [MeetingSegmentSpeakerOverride] = [],
        minutesVersions: [MeetingMinutesVersion] = []
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
        self.interruptedRecording = interruptedRecording
        self.captureMode = captureMode
        self.audioChunks = audioChunks
        self.audioEvents = audioEvents
        self.awaitingAssets = awaitingAssets
        self.diarizationDegraded = diarizationDegraded
        self.diarizationDegradeReason = diarizationDegradeReason
        self.estimatedSpeakerCount = estimatedSpeakerCount
        self.uncertainSegmentRatio = uncertainSegmentRatio
        self.speakerTurns = speakerTurns
        self.segmentSpeakerOverrides = segmentSpeakerOverrides
        self.minutesVersions = minutesVersions
    }

    var resolvedCaptureMode: MeetingCaptureMode {
        if let captureMode {
            return captureMode
        }
        return systemAudioFileName == nil ? .microphone : .dual
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case duration
        case audioFileName
        case microphoneAudioFileName
        case systemAudioFileName
        case systemAudioStartOffset
        case language
        case status
        case speakers
        case transcript
        case summary
        case summaryCheckpoint
        case errorMessage
        case interruptedRecording
        case captureMode
        case audioChunks
        case audioEvents
        case awaitingAssets
        case diarizationDegraded
        case diarizationDegradeReason
        case estimatedSpeakerCount
        case uncertainSegmentRatio
        case speakerTurns
        case segmentSpeakerOverrides
        case minutesVersions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? Self.defaultTitle
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        audioFileName = try container.decode(String.self, forKey: .audioFileName)
        microphoneAudioFileName = try container.decodeIfPresent(String.self, forKey: .microphoneAudioFileName)
        systemAudioFileName = try container.decodeIfPresent(String.self, forKey: .systemAudioFileName)
        systemAudioStartOffset = try container.decodeIfPresent(TimeInterval.self, forKey: .systemAudioStartOffset)
        language = try container.decodeIfPresent(MeetingLanguage.self, forKey: .language) ?? .simplifiedChinese
        status = try container.decodeIfPresent(MeetingRecordStatus.self, forKey: .status) ?? .failed
        speakers = try container.decodeIfPresent([MeetingSpeaker].self, forKey: .speakers) ?? []
        transcript = try container.decodeIfPresent([MeetingTranscriptSegment].self, forKey: .transcript) ?? []
        summary = try container.decodeIfPresent(MeetingSummary.self, forKey: .summary)
        summaryCheckpoint = try container.decodeIfPresent(MeetingSummaryCheckpoint.self, forKey: .summaryCheckpoint)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        interruptedRecording = try container.decodeIfPresent(Bool.self, forKey: .interruptedRecording)
        captureMode = try container.decodeIfPresent(MeetingCaptureMode.self, forKey: .captureMode)
        audioChunks = try container.decodeIfPresent([MeetingAudioChunk].self, forKey: .audioChunks) ?? []
        audioEvents = try container.decodeIfPresent([MeetingAudioEvent].self, forKey: .audioEvents) ?? []
        awaitingAssets = try container.decodeIfPresent(Bool.self, forKey: .awaitingAssets)
        diarizationDegraded = try container.decodeIfPresent(Bool.self, forKey: .diarizationDegraded)
        diarizationDegradeReason = try container.decodeIfPresent(String.self, forKey: .diarizationDegradeReason)
        estimatedSpeakerCount = try container.decodeIfPresent(Int.self, forKey: .estimatedSpeakerCount)
        uncertainSegmentRatio = try container.decodeIfPresent(Double.self, forKey: .uncertainSegmentRatio)
        speakerTurns = try container.decodeIfPresent([MeetingSpeakerTurnRecord].self, forKey: .speakerTurns) ?? []
        segmentSpeakerOverrides = try container.decodeIfPresent(
            [MeetingSegmentSpeakerOverride].self,
            forKey: .segmentSpeakerOverrides
        ) ?? []
        minutesVersions = try container.decodeIfPresent([MeetingMinutesVersion].self, forKey: .minutesVersions) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(duration, forKey: .duration)
        try container.encode(audioFileName, forKey: .audioFileName)
        try container.encodeIfPresent(microphoneAudioFileName, forKey: .microphoneAudioFileName)
        try container.encodeIfPresent(systemAudioFileName, forKey: .systemAudioFileName)
        try container.encodeIfPresent(systemAudioStartOffset, forKey: .systemAudioStartOffset)
        try container.encode(language, forKey: .language)
        try container.encode(status, forKey: .status)
        try container.encode(speakers, forKey: .speakers)
        try container.encode(transcript, forKey: .transcript)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(summaryCheckpoint, forKey: .summaryCheckpoint)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
        try container.encodeIfPresent(interruptedRecording, forKey: .interruptedRecording)
        try container.encodeIfPresent(captureMode, forKey: .captureMode)
        try container.encode(audioChunks, forKey: .audioChunks)
        try container.encode(audioEvents, forKey: .audioEvents)
        try container.encodeIfPresent(awaitingAssets, forKey: .awaitingAssets)
        try container.encodeIfPresent(diarizationDegraded, forKey: .diarizationDegraded)
        try container.encodeIfPresent(diarizationDegradeReason, forKey: .diarizationDegradeReason)
        try container.encodeIfPresent(estimatedSpeakerCount, forKey: .estimatedSpeakerCount)
        try container.encodeIfPresent(uncertainSegmentRatio, forKey: .uncertainSegmentRatio)
        try container.encode(speakerTurns, forKey: .speakerTurns)
        try container.encode(segmentSpeakerOverrides, forKey: .segmentSpeakerOverrides)
        try container.encode(minutesVersions, forKey: .minutesVersions)
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
        if awaitingAssets == true {
            return false
        }
        switch status {
        case .failed, .summaryFailed, .transcribed, .transcribing, .summarizing:
            return true
        case .recording, .ready:
            return false
        }
    }

    func matchesSearch(_ rawQuery: String) -> Bool {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if title.meetingSearchContains(query) || status.title.meetingSearchContains(query) {
            return true
        }
        if transcript.contains(where: { $0.text.meetingSearchContains(query) }) {
            return true
        }
        guard let summary else { return false }
        let pointText = summary.renderedPoints.flatMap { [$0.title, $0.detail] }
        return ([summary.overview] + summary.keyPoints + summary.decisions + summary.openQuestions
            + pointText
            + summary.actionItems.map(\.task))
            .contains { $0.meetingSearchContains(query) }
    }

    mutating func applyInterruptedLaunchRecovery() {
        switch status {
        case .recording:
            status = .failed
            interruptedRecording = true
            errorMessage = "录音未正常结束，已保留约 \(MeetingRecordingStyle.formatDuration(duration))。可以手动继续处理，不会自动开始转写。"
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

extension String {
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
    var speakerTurns: [MeetingSpeakerTurnRecord]
    var segmentSpeakerOverrides: [MeetingSegmentSpeakerOverride]
    var minutesVersions: [MeetingMinutesVersion]

    var isEmpty: Bool {
        speakers.isEmpty && transcript.isEmpty && summary == nil && summaryCheckpoint == nil
            && speakerTurns.isEmpty && segmentSpeakerOverrides.isEmpty && minutesVersions.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case speakers
        case transcript
        case summary
        case summaryCheckpoint
        case speakerTurns
        case segmentSpeakerOverrides
        case minutesVersions
    }

    init(
        speakers: [MeetingSpeaker],
        transcript: [MeetingTranscriptSegment],
        summary: MeetingSummary?,
        summaryCheckpoint: MeetingSummaryCheckpoint?,
        speakerTurns: [MeetingSpeakerTurnRecord] = [],
        segmentSpeakerOverrides: [MeetingSegmentSpeakerOverride] = [],
        minutesVersions: [MeetingMinutesVersion] = []
    ) {
        self.speakers = speakers
        self.transcript = transcript
        self.summary = summary
        self.summaryCheckpoint = summaryCheckpoint
        self.speakerTurns = speakerTurns
        self.segmentSpeakerOverrides = segmentSpeakerOverrides
        self.minutesVersions = minutesVersions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        speakers = try container.decodeIfPresent([MeetingSpeaker].self, forKey: .speakers) ?? []
        transcript = try container.decodeIfPresent([MeetingTranscriptSegment].self, forKey: .transcript) ?? []
        summary = try container.decodeIfPresent(MeetingSummary.self, forKey: .summary)
        summaryCheckpoint = try container.decodeIfPresent(MeetingSummaryCheckpoint.self, forKey: .summaryCheckpoint)
        speakerTurns = try container.decodeIfPresent([MeetingSpeakerTurnRecord].self, forKey: .speakerTurns) ?? []
        segmentSpeakerOverrides = try container.decodeIfPresent(
            [MeetingSegmentSpeakerOverride].self,
            forKey: .segmentSpeakerOverrides
        ) ?? []
        minutesVersions = try container.decodeIfPresent([MeetingMinutesVersion].self, forKey: .minutesVersions) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(speakers, forKey: .speakers)
        try container.encode(transcript, forKey: .transcript)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(summaryCheckpoint, forKey: .summaryCheckpoint)
        try container.encode(speakerTurns, forKey: .speakerTurns)
        try container.encode(segmentSpeakerOverrides, forKey: .segmentSpeakerOverrides)
        try container.encode(minutesVersions, forKey: .minutesVersions)
    }
}

extension MeetingRecord {
    var detail: MeetingRecordDetail {
        MeetingRecordDetail(
            speakers: speakers,
            transcript: transcript,
            summary: summary,
            summaryCheckpoint: summaryCheckpoint,
            speakerTurns: speakerTurns,
            segmentSpeakerOverrides: segmentSpeakerOverrides,
            minutesVersions: minutesVersions
        )
    }

    var metadataCopy: MeetingRecord {
        var copy = self
        copy.speakers = []
        copy.transcript = []
        copy.summary = nil
        copy.summaryCheckpoint = nil
        copy.speakerTurns = []
        copy.segmentSpeakerOverrides = []
        copy.minutesVersions = []
        return copy
    }

    mutating func applyDetail(_ detail: MeetingRecordDetail) {
        speakers = detail.speakers
        transcript = detail.transcript
        summary = detail.summary
        summaryCheckpoint = detail.summaryCheckpoint
        speakerTurns = detail.speakerTurns
        segmentSpeakerOverrides = detail.segmentSpeakerOverrides
        minutesVersions = detail.minutesVersions
    }

    func markdownDocument(includeTranscript: Bool = true) -> String {
        var lines: [String] = [
            "# \(title)",
            "",
            "- 时间：\(createdAt.formatted(date: .long, time: .shortened))",
            "- 时长：\(MeetingRecordingStyle.formatDuration(duration))",
            "- 状态：\(status.title)"
        ]
        if !speakers.isEmpty {
            lines.append("- 说话人：\(speakers.map(\.name).joined(separator: "、"))")
        }
        if let summary {
            lines.append("")
            lines.append("## 概要")
            if !summary.overview.isEmpty {
                lines.append("")
                lines.append(summary.overview)
            }
            let points = summary.renderedPoints
            if !points.isEmpty {
                lines.append("")
                lines.append("## 讨论要点")
                for point in points {
                    lines.append("")
                    lines.append("- **\(point.title)**")
                    if !point.detail.isEmpty {
                        lines.append("  \(point.detail)")
                    }
                    appendEvidence(point.evidence, to: &lines)
                }
            }
            if !summary.actionItems.isEmpty {
                lines.append("")
                lines.append("## 待办")
                for item in summary.actionItems {
                    lines.append("")
                    lines.append("- [\(item.isCompleted ? "x" : " ")] \(item.task)")
                    lines.append("  负责人：\(item.ownerLabel)")
                    lines.append("  期限：\(item.dueLabel)")
                    appendEvidence(item.evidence.isEmpty ? legacyEvidence(for: item, in: summary) : item.evidence, to: &lines)
                }
            }
        }
        if includeTranscript, !transcript.isEmpty {
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

    func plainTranscriptDocument() -> String {
        var lines = [
            title,
            createdAt.formatted(date: .long, time: .shortened),
            ""
        ]
        if !speakers.isEmpty {
            lines.append(speakers.map { "\($0.name)（\($0.id)）" }.joined(separator: "\n"))
            lines.append("")
        }
        for segment in transcript {
            let speaker = speakers.first { $0.id == segment.speakerID }?.name ?? segment.speakerID
            lines.append("[\(MeetingRecordingStyle.formatTimestamp(segment.startTime))] \(speaker)：\(segment.text)")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func appendEvidence(_ evidence: [MeetingEvidence], to lines: inout [String]) {
        for item in evidence {
            let stamp = MeetingRecordingStyle.formatTimestamp(TimeInterval(item.startMs) / 1000)
            lines.append("  - 出处 [\(stamp)] \(item.quote)")
        }
    }

    private func legacyEvidence(for item: MeetingActionItem, in summary: MeetingSummary) -> [MeetingEvidence] {
        guard let citation = summary.citations?.first(where: { $0.kind == .actionItem && $0.text == item.task }) else {
            return []
        }
        return citation.sourceSegmentIDs.map { segmentID in
            let segment = transcript.first { $0.id == segmentID }
            return MeetingEvidence(
                segmentID: segmentID,
                startMs: Int(((segment?.startTime ?? 0) * 1000).rounded()),
                endMs: Int(((segment?.endTime ?? 0) * 1000).rounded()),
                quote: segment?.text ?? item.task
            )
        }
    }
}

enum MeetingTranscriptConsent {
    private static let key = "jarvis.meeting.transcriptOutboundConfirmed"

    static var isConfirmed: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func confirm() {
        UserDefaults.standard.set(true, forKey: key)
    }
}

struct MeetingTranscriptionTrack: Sendable {
    var url: URL
    var timeOffset: TimeInterval
    var diarize: Bool
    var trackID: String
}

struct MeetingTranscriptionResult: Sendable {
    var speakers: [MeetingSpeaker]
    var segments: [MeetingTranscriptSegment]
    var speakerTurns: [MeetingSpeakerTurnRecord]
    var diarizationDegraded: Bool
    var diarizationDegradeReason: String?
    var estimatedSpeakerCount: Int
    var uncertainSegmentRatio: Double

    init(
        speakers: [MeetingSpeaker],
        segments: [MeetingTranscriptSegment],
        speakerTurns: [MeetingSpeakerTurnRecord] = [],
        diarizationDegraded: Bool = false,
        diarizationDegradeReason: String? = nil,
        estimatedSpeakerCount: Int = 0,
        uncertainSegmentRatio: Double = 0
    ) {
        self.speakers = speakers
        self.segments = segments
        self.speakerTurns = speakerTurns
        self.diarizationDegraded = diarizationDegraded
        self.diarizationDegradeReason = diarizationDegradeReason
        self.estimatedSpeakerCount = estimatedSpeakerCount
        self.uncertainSegmentRatio = uncertainSegmentRatio
    }
}
