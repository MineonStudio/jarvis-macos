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
    case ready
    case failed

    var title: String {
        switch self {
        case .recording: "录音中"
        case .transcribing: "转写中"
        case .transcribed: "待总结"
        case .summarizing: "总结中"
        case .ready: "已完成"
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

enum MeetingModelPreparationStage: String, Sendable {
    case speakerDiarization
    case chineseTranscription

    var title: String {
        switch self {
        case .speakerDiarization: "准备说话人识别模型"
        case .chineseTranscription: "准备中文转写模型"
        }
    }
}

struct MeetingModelAvailability: Equatable, Sendable {
    let speakerDiarizationReady: Bool
    let chineseTranscriptionReady: Bool

    var isReady: Bool {
        speakerDiarizationReady && chineseTranscriptionReady
    }

    var missingTitle: String {
        switch (speakerDiarizationReady, chineseTranscriptionReady) {
        case (false, false): "说话人识别和中文转写模型"
        case (false, true): "说话人识别模型"
        case (true, false): "中文转写模型"
        case (true, true): ""
        }
    }
}

enum MeetingModelPreparationState: Equatable, Sendable {
    case checking
    case notReady(MeetingModelAvailability)
    case downloading(stage: MeetingModelPreparationStage, progress: Double)
    case ready
    case failed(String)

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
        case .awaitingConfiguration: "逐字稿已完成"
        case .ready: "会议已整理"
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
    var language: MeetingLanguage
    var status: MeetingRecordStatus
    var speakers: [MeetingSpeaker]
    var transcript: [MeetingTranscriptSegment]
    var summary: MeetingSummary?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        audioFileName: String,
        microphoneAudioFileName: String? = nil,
        systemAudioFileName: String? = nil,
        language: MeetingLanguage = .simplifiedChinese,
        status: MeetingRecordStatus = .recording,
        speakers: [MeetingSpeaker] = [],
        transcript: [MeetingTranscriptSegment] = [],
        summary: MeetingSummary? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.audioFileName = audioFileName
        self.microphoneAudioFileName = microphoneAudioFileName
        self.systemAudioFileName = systemAudioFileName
        self.language = language
        self.status = status
        self.speakers = speakers
        self.transcript = transcript
        self.summary = summary
        self.errorMessage = errorMessage
    }

    static func isLegacyGeneratedTitle(_ title: String, createdAt: Date) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return title == "会议 · \(formatter.string(from: createdAt))"
    }
}

struct MeetingTranscriptionResult: Sendable {
    let speakers: [MeetingSpeaker]
    let segments: [MeetingTranscriptSegment]
}
