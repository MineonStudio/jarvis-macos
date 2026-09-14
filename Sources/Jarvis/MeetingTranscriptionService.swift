import FluidAudio
import Foundation

protocol MeetingTranscribing: Sendable {
    func prepareModels(
        progress: @escaping @Sendable (MeetingModelPreparationStage, Double) -> Void
    ) async throws

    func transcribe(
        audioURL: URL,
        language: MeetingLanguage,
        progress: @escaping @Sendable (MeetingProcessingStage, Double) -> Void
    ) async throws -> MeetingTranscriptionResult
}

actor FluidAudioMeetingTranscriptionService: MeetingTranscribing {
    private var chineseASR: ParaformerManager?
    private var offlineDiarizer: SendableOfflineDiarizer?

    func prepareModels(
        progress: @escaping @Sendable (MeetingModelPreparationStage, Double) -> Void
    ) async throws {
        if offlineDiarizer == nil {
            progress(.speakerDiarization, 0.02)
            let manager = SendableOfflineDiarizer()
            try await manager.prepareModels()
            offlineDiarizer = manager
        }
        progress(.speakerDiarization, 0.5)

        if chineseASR == nil {
            progress(.chineseTranscription, 0.52)
            chineseASR = try await ParaformerManager.load(precision: .int8)
        }
        progress(.chineseTranscription, 1)
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
        var tokens: [TimedToken] = []
        let chunkCount = max(1, Int(ceil(Double(samples.count) / Double(chunkSize))))

        for chunkIndex in 0 ..< chunkCount {
            try Task.checkCancellation()
            let start = chunkIndex * chunkSize
            let end = min(samples.count, start + chunkSize)
            guard start < end else { continue }
            let chunk = Array(samples[start ..< end])
            let timestamped = try await asr.transcribeWithTimestamps(audio: chunk)
            let offset = Double(start) / Double(sampleRate)
            tokens.append(contentsOf: timestamped.map {
                TimedToken(
                    startTime: $0.startTime + offset,
                    endTime: $0.endTime + offset,
                    text: $0.text
                )
            })
            progress(.transcribing, 0.5 + 0.42 * Double(chunkIndex + 1) / Double(chunkCount))
        }

        let result = makeResult(tokens: tokens, diarizationSegments: diarization.segments)
        progress(.summarizing, 0.96)
        return result
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
            let speakerID = speakerID(for: token, in: diarizationSegments)
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
                currentText += token.text
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
        in segments: [TimedSpeakerSegment]
    ) -> String {
        let tokenStart = token.startTime
        let tokenEnd = max(token.endTime, token.startTime + 0.01)
        let best = segments.max { lhs, rhs in
            overlap(tokenStart, tokenEnd, lhs) < overlap(tokenStart, tokenEnd, rhs)
        }
        return best?.speakerId ?? "S1"
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
