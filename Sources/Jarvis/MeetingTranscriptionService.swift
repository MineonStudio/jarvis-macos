import FluidAudio
import Foundation

protocol MeetingTranscribing: Sendable {
    func prepareModel(
        _ stage: MeetingModelPreparationStage,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws

    func removeModel(_ stage: MeetingModelPreparationStage) async throws

    func transcribeTracks(
        _ tracks: [MeetingTranscriptionTrack],
        language: MeetingLanguage,
        progress: @escaping @Sendable (MeetingProcessingStage, Double) -> Void
    ) async throws -> MeetingTranscriptionResult

    func releaseCachedModels() async
}

actor FluidAudioMeetingTranscriptionService: MeetingTranscribing {
    private var offlineDiarizer: SendableOfflineDiarizer?

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
            try await MeetingSpeechAssets.install(onProgress: progress)
        }
        progress(1)
    }

    func removeModel(_ stage: MeetingModelPreparationStage) async throws {
        switch stage {
        case .speakerDiarization:
            offlineDiarizer = nil
            try await Task.detached(priority: .utility) {
                try MeetingModelStorage.removeModel(for: stage)
            }.value
        case .chineseTranscription:
            throw MeetingTranscriptionError.speechAssetUnavailable(
                "中文转写使用的是系统语音资源，不能从贾维斯里移除。"
            )
        }
    }

    func transcribeTracks(
        _ tracks: [MeetingTranscriptionTrack],
        language _: MeetingLanguage,
        progress: @escaping @Sendable (MeetingProcessingStage, Double) -> Void
    ) async throws -> MeetingTranscriptionResult {
        if tracks.contains(where: \.diarize), offlineDiarizer == nil {
            try await prepareModel(.speakerDiarization) { value in
                progress(.diarizing, value * 0.2)
            }
        }
        if await !MeetingSpeechAssets.isInstalled() {
            try await prepareModel(.chineseTranscription) { value in
                progress(.transcribing, 0.2 + value * 0.2)
            }
        }

        var tokens: [TimedToken] = []
        var turns: [MeetingMinutesAlgorithm.SpeakerTurn] = []
        var degraded = false
        var reasons: [String] = []
        let count = max(tracks.count, 1)
        for (index, track) in tracks.enumerated() {
            let span = 1 / Double(count)
            let base = Double(index) * span
            let turnCountBefore = turns.count
            if track.diarize {
                do {
                    guard let offlineDiarizer else {
                        throw MeetingTranscriptionError.modelsUnavailable
                    }
                    progress(.diarizing, base + span * 0.1)
                    let diarization = try await offlineDiarizer.process(track.url) { completed, total in
                        let fraction = total == 0 ? 0 : Double(completed) / Double(total)
                        progress(.diarizing, base + span * fraction * 0.45)
                    }
                    turns.append(contentsOf: diarization.segments.map { segment in
                        MeetingMinutesAlgorithm.SpeakerTurn(
                            speakerID: "\(track.trackID):\(segment.speakerId)",
                            startTime: TimeInterval(segment.startTimeSeconds) + track.timeOffset,
                            endTime: TimeInterval(segment.endTimeSeconds) + track.timeOffset
                        )
                    })
                } catch {
                    degraded = true
                    reasons.append(error.localizedDescription)
                }
            }
            do {
                progress(.transcribing, base + span * 0.5)
                let speechTokens = try await MeetingSpeechAssets.transcribe(audioURL: track.url)
                tokens.append(contentsOf: speechTokens.map {
                    TimedToken(
                        startTime: $0.startTime + track.timeOffset,
                        endTime: $0.endTime + track.timeOffset,
                        text: $0.text,
                        confidence: $0.confidence
                    )
                })
            } catch {
                turns = MeetingTrackFailure.turnsAfterFailedTranscription(
                    turns,
                    appendedFrom: turnCountBefore
                )
                reasons.append(error.localizedDescription)
            }
        }
        guard !tokens.isEmpty else {
            throw MeetingTranscriptionError.speechAssetUnavailable(
                reasons.last ?? "没有识别到语音"
            )
        }
        var result = makeResult(tokens: tokens, turns: turns)
        result.diarizationDegraded = degraded
        let reason = reasons.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        result.diarizationDegradeReason = reason.isEmpty ? nil : reason
        if degraded, result.speakers.isEmpty {
            result.speakers = [
                MeetingSpeaker(id: "unlabeled", name: "未标注", colorIndex: 0)
            ]
        }
        progress(.transcribing, 1)
        return result
    }

    func releaseCachedModels() async {
        offlineDiarizer = nil
    }

    private struct TimedToken: Sendable {
        let startTime: TimeInterval
        let endTime: TimeInterval
        let text: String
        let confidence: Double?
    }

    private func makeResult(
        tokens: [TimedToken],
        turns suppliedTurns: [MeetingMinutesAlgorithm.SpeakerTurn]
    ) -> MeetingTranscriptionResult {
        let sortedTokens = tokens.sorted { $0.startTime < $1.startTime }
        var pieces: [(start: TimeInterval, end: TimeInterval, text: String, confidence: Double?)] = []
        var currentStart = 0.0
        var currentEnd = 0.0
        var currentText = ""
        var confidenceSum = 0.0
        var confidenceCount = 0

        func flush() {
            let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let confidence = confidenceCount > 0 ? confidenceSum / Double(confidenceCount) : nil
            pieces.append((currentStart, currentEnd, text, confidence))
            currentText = ""
            confidenceSum = 0
            confidenceCount = 0
        }

        for token in sortedTokens where !token.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let shouldSplit = MeetingMinutesAlgorithm.shouldSplitUtterance(
                currentText: currentText,
                currentStart: currentStart,
                currentEnd: currentEnd,
                nextStart: token.startTime,
                nextEnd: token.endTime,
                turns: suppliedTurns
            )
            if shouldSplit {
                flush()
            }
            if currentText.isEmpty {
                currentStart = token.startTime
                currentText = token.text
            } else {
                appendToken(token.text, to: &currentText)
            }
            currentEnd = max(currentEnd, token.endTime)
            if let confidence = token.confidence {
                confidenceSum += confidence
                confidenceCount += 1
            }
            if let lastCharacter = currentText.last, "。！？.!?".contains(lastCharacter) {
                flush()
            }
        }
        flush()

        let turns = suppliedTurns
        var orderedSpeakerIDs: [String] = []
        var sawUncertain = false
        let utterances: [MeetingTranscriptSegment] = pieces.map { piece in
            let speakerID: String
            let uncertain: Bool
            if turns.isEmpty {
                speakerID = "unlabeled"
                uncertain = false
            } else {
                speakerID = MeetingMinutesAlgorithm.assignedSpeakerID(
                    startTime: piece.start,
                    endTime: piece.end,
                    turns: turns
                )
                uncertain = speakerID == MeetingMinutesAlgorithm.uncertainSpeakerID
            }
            if uncertain {
                sawUncertain = true
            } else if !orderedSpeakerIDs.contains(speakerID) {
                orderedSpeakerIDs.append(speakerID)
            }
            return MeetingTranscriptSegment(
                startTime: piece.start,
                endTime: piece.end,
                speakerID: speakerID,
                text: piece.text,
                confidence: piece.confidence,
                isUncertainSpeaker: uncertain
            )
        }
        var speakers = orderedSpeakerIDs.enumerated().map { index, id in
            let name = id == "unlabeled" ? "未标注" : "说话人 \(index + 1)"
            return MeetingSpeaker(id: id, name: name, colorIndex: index)
        }
        if sawUncertain {
            speakers.append(
                MeetingSpeaker(
                    id: MeetingMinutesAlgorithm.uncertainSpeakerID,
                    name: MeetingMinutesAlgorithm.uncertainSpeakerName,
                    colorIndex: speakers.count
                )
            )
        }
        let uncertainCount = utterances.filter(\.isUncertainSpeaker).count
        let ratio = utterances.isEmpty ? 0 : Double(uncertainCount) / Double(utterances.count)
        let estimated = speakers.filter { $0.id != MeetingMinutesAlgorithm.uncertainSpeakerID }.count
        return MeetingTranscriptionResult(
            speakers: speakers,
            segments: utterances.sorted { $0.startTime < $1.startTime },
            speakerTurns: turns.map {
                MeetingSpeakerTurnRecord(
                    startTime: $0.startTime,
                    endTime: $0.endTime,
                    clusterID: $0.speakerID
                )
            },
            estimatedSpeakerCount: estimated,
            uncertainSegmentRatio: ratio
        )
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

enum MeetingTrackFailure {
    /// Drops speaker turns added for a track whose transcription just failed.
    static func turnsAfterFailedTranscription(
        _ turns: [MeetingMinutesAlgorithm.SpeakerTurn],
        appendedFrom index: Int
    ) -> [MeetingMinutesAlgorithm.SpeakerTurn] {
        guard index >= 0, index <= turns.count else { return turns }
        return Array(turns.prefix(index))
    }
}

enum MeetingTranscriptionError: LocalizedError {
    case modelsUnavailable
    case speechAssetUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .modelsUnavailable:
            "说话人识别模型尚未准备好，请先下载。中文转写使用系统语音资源。"
        case let .speechAssetUnavailable(message):
            message
        }
    }
}
