import FluidAudio
import Foundation

protocol MeetingTranscribing: Sendable {
    func prepareModel(
        _ stage: MeetingModelPreparationStage,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws

    func prepareModels(
        progress: @escaping @Sendable (MeetingModelPreparationStage, Double) -> Void
    ) async throws

    func removeModel(_ stage: MeetingModelPreparationStage) async throws

    func transcribe(
        audioURL: URL,
        language: MeetingLanguage,
        progress: @escaping @Sendable (MeetingProcessingStage, Double) -> Void
    ) async throws -> MeetingTranscriptionResult

    func releaseCachedModels() async
}

extension MeetingTranscribing {
    func releaseCachedModels() async {}
}

actor FluidAudioMeetingTranscriptionService: MeetingTranscribing {
    private var chineseASR: ParaformerManager?
    private var offlineDiarizer: SendableOfflineDiarizer?

    func prepareModels(
        progress: @escaping @Sendable (MeetingModelPreparationStage, Double) -> Void
    ) async throws {
        for stage in MeetingModelPreparationStage.allCases {
            try await prepareModel(stage) { value in
                progress(stage, value)
            }
        }
    }

    func prepareModel(
        _ stage: MeetingModelPreparationStage,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        switch stage {
        case .speakerDiarization:
            if offlineDiarizer == nil {
                progress(0.02)
                let manager = SendableOfflineDiarizer()
                try await manager.prepareModels()
                offlineDiarizer = manager
            }
        case .chineseTranscription:
            if chineseASR == nil {
                progress(0.02)
                chineseASR = try await ParaformerManager.load(precision: .int8)
            }
        }
        progress(1)
    }

    func removeModel(_ stage: MeetingModelPreparationStage) async throws {
        switch stage {
        case .speakerDiarization:
            offlineDiarizer = nil
        case .chineseTranscription:
            chineseASR = nil
        }
        try await Task.detached(priority: .utility) {
            try MeetingModelStorage.removeModel(for: stage)
        }.value
    }

    func transcribe(
        audioURL: URL,
        language _: MeetingLanguage,
        progress: @escaping @Sendable (MeetingProcessingStage, Double) -> Void
    ) async throws -> MeetingTranscriptionResult {
        if offlineDiarizer == nil || chineseASR == nil {
            try await prepareModels { stage, preparationProgress in
                switch stage {
                case .speakerDiarization:
                    progress(.diarizing, preparationProgress * 0.48)
                case .chineseTranscription:
                    progress(.transcribing, 0.5 + preparationProgress * 0.42)
                }
            }
        }

        guard let offlineDiarizer, let asr = chineseASR else {
            throw MeetingTranscriptionError.modelsUnavailable
        }

        progress(.diarizing, 0.02)
        let diarization = try await offlineDiarizer.process(audioURL) { completed, total in
            let progressValue = total == 0 ? 0 : Double(completed) / Double(total)
            progress(.diarizing, min(0.48, progressValue * 0.48))
        }

        progress(.transcribing, 0.5)
        let samples = try AudioConverter(sampleRate: 16000).resampleAudioFile(audioURL)
        let sampleRate = 16000
        let chunkSize = 24 * sampleRate
        let overlapSize = 2 * sampleRate
        let stride = max(1, chunkSize - overlapSize)
        var tokens: [TimedToken] = []
        let chunkCount = max(1, Int(ceil(Double(max(0, samples.count - overlapSize)) / Double(stride))))

        for chunkIndex in 0 ..< chunkCount {
            try Task.checkCancellation()
            let start = chunkIndex * stride
            let end = min(samples.count, start + chunkSize)
            guard start < end else { continue }
            let chunk = Array(samples[start ..< end])
            let timestamped = try await asr.transcribeWithTimestamps(audio: chunk)
            let offset = Double(start) / Double(sampleRate)
            let minimumLocalTime = chunkIndex == 0 ? 0.0 : Double(overlapSize) / Double(sampleRate)
            tokens.append(contentsOf: timestamped.compactMap { token in
                guard token.startTime + 0.02 >= minimumLocalTime else { return nil }
                return TimedToken(
                    startTime: token.startTime + offset,
                    endTime: token.endTime + offset,
                    text: token.text
                )
            })
            progress(.transcribing, 0.5 + 0.48 * Double(chunkIndex + 1) / Double(chunkCount))
        }

        let result = makeResult(tokens: tokens, diarizationSegments: diarization.segments)
        progress(.transcribing, 1)
        return result
    }

    func releaseCachedModels() async {
        chineseASR = nil
        offlineDiarizer = nil
    }

    private struct TimedToken: Sendable {
        let startTime: TimeInterval
        let endTime: TimeInterval
        let text: String
    }

    private func makeResult(
        tokens: [TimedToken],
        diarizationSegments: [TimedSpeakerSegment]
    ) -> MeetingTranscriptionResult {
        let sortedTokens = tokens.sorted { $0.startTime < $1.startTime }
        var orderedSpeakerIDs: [String] = []
        var utterances: [MeetingTranscriptSegment] = []
        var currentSpeakerID: String?
        var currentStart = 0.0
        var currentEnd = 0.0
        var currentText = ""

        for token in sortedTokens where !token.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let speakerID = speakerID(
                for: token,
                in: diarizationSegments,
                fallback: currentSpeakerID ?? "S1"
            )
            if !orderedSpeakerIDs.contains(speakerID) {
                orderedSpeakerIDs.append(speakerID)
            }

            let shouldStartNewUtterance = currentSpeakerID != speakerID
                || token.startTime - currentEnd > 1.4
                || currentText.count > 180

            if shouldStartNewUtterance, !currentText.isEmpty, let currentSpeakerID {
                utterances.append(
                    MeetingTranscriptSegment(
                        startTime: currentStart,
                        endTime: currentEnd,
                        speakerID: currentSpeakerID,
                        text: currentText
                    )
                )
            }

            if shouldStartNewUtterance {
                currentSpeakerID = speakerID
                currentStart = token.startTime
                currentText = token.text
            } else {
                appendToken(token.text, to: &currentText)
            }
            currentEnd = max(currentEnd, token.endTime)

            if let lastCharacter = currentText.last, "。！？.!?".contains(lastCharacter) {
                if let currentSpeakerID {
                    utterances.append(
                        MeetingTranscriptSegment(
                            startTime: currentStart,
                            endTime: currentEnd,
                            speakerID: currentSpeakerID,
                            text: currentText
                        )
                    )
                }
                currentSpeakerID = nil
                currentText = ""
            }
        }

        if !currentText.isEmpty, let currentSpeakerID {
            utterances.append(
                MeetingTranscriptSegment(
                    startTime: currentStart,
                    endTime: currentEnd,
                    speakerID: currentSpeakerID,
                    text: currentText
                )
            )
        }

        let speakers = orderedSpeakerIDs.enumerated().map { index, id in
            MeetingSpeaker(id: id, name: "说话人 \(index + 1)", colorIndex: index)
        }
        return MeetingTranscriptionResult(speakers: speakers, segments: utterances)
    }

    private func speakerID(
        for token: TimedToken,
        in segments: [TimedSpeakerSegment],
        fallback: String
    ) -> String {
        let tokenStart = token.startTime
        let tokenEnd = max(token.endTime, token.startTime + 0.01)
        let best = segments.max { lhs, rhs in
            overlap(tokenStart, tokenEnd, lhs) < overlap(tokenStart, tokenEnd, rhs)
        }
        guard let best, overlap(tokenStart, tokenEnd, best) > 0 else {
            return fallback
        }
        return best.speakerId
    }

    private func appendToken(_ text: String, to current: inout String) {
        guard !text.isEmpty else { return }
        if current.isEmpty {
            current = text
            return
        }
        if needsSpace(between: current, and: text) {
            current += " " + text
        } else {
            current += text
        }
    }

    private func needsSpace(between lhs: String, and rhs: String) -> Bool {
        guard let last = lhs.last, let first = rhs.first else { return false }
        return last.isLetter && last.isASCII && first.isLetter && first.isASCII
    }

    private func overlap(
        _ start: TimeInterval,
        _ end: TimeInterval,
        _ segment: TimedSpeakerSegment
    ) -> TimeInterval {
        max(
            0,
            min(end, TimeInterval(segment.endTimeSeconds))
                - max(start, TimeInterval(segment.startTimeSeconds))
        )
    }
}

/// FluidAudio's offline diarizer owns Core ML objects that are intentionally managed by
/// the library outside Swift's Sendable model. The meeting service actor serializes access;
/// this wrapper keeps that boundary explicit for Swift 6's strict concurrency checks.
private final class SendableOfflineDiarizer: @unchecked Sendable {
    private let manager: OfflineDiarizerManager

    init() {
        manager = OfflineDiarizerManager()
    }

    func prepareModels() async throws {
        try await manager.prepareModels()
    }

    func process(
        _ audioURL: URL,
        progressCallback: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> DiarizationResult {
        try await manager.process(audioURL, progressCallback: progressCallback)
    }
}

enum MeetingTranscriptionError: LocalizedError {
    case modelsUnavailable

    var errorDescription: String? {
        switch self {
        case .modelsUnavailable: "会议识别模型尚未准备好，请先下载模型"
        }
    }
}
