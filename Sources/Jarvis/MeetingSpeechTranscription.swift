import AVFoundation
import CoreMedia
import Foundation
import Network
import Speech

enum MeetingSpeechDownloadMeter {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var completedBytes: Int64 = 0
    nonisolated(unsafe) private static var totalBytes: Int64 = 0

    static func reset() {
        lock.lock()
        completedBytes = 0
        totalBytes = 0
        lock.unlock()
    }

    static func update(_ progress: Progress) {
        lock.lock()
        completedBytes = Int64(progress.completedUnitCount)
        totalBytes = Int64(progress.totalUnitCount)
        lock.unlock()
    }

    static func snapshot() -> (completed: Int64, total: Int64) {
        lock.lock()
        defer { lock.unlock() }
        return (completedBytes, totalBytes)
    }
}

struct MeetingSpeechToken: Sendable {
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var confidence: Double?
}

/// System Chinese speech assets. The app does not bundle an ASR model.
enum MeetingSpeechAssets {
    static func isInstalled() async -> Bool {
        let status = await AssetInventory.status(forModules: [makeTranscriber()])
        return status == .installed
    }

    static func install(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let transcriber = makeTranscriber()
        let status = await AssetInventory.status(forModules: [transcriber])
        switch status {
        case .installed:
            onProgress(1)
            return
        case .unsupported:
            throw MeetingTranscriptionError.speechAssetUnavailable(
                "这台 Mac 不支持系统中文转写资源。正式录音需要先装好这个资源。"
            )
        case .downloading, .supported:
            break
        @unknown default:
            break
        }

        if await networkIsUnavailable() {
            throw MeetingTranscriptionError.speechAssetUnavailable(
                "当前没有网络，系统语音资源下载不了。接上网络后再试。已经下载过的资源可以离线转写。"
            )
        }

        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            onProgress(1)
            return
        }
        let progress = request.progress
        MeetingSpeechDownloadMeter.reset()
        let poll = Task {
            while !Task.isCancelled {
                MeetingSpeechDownloadMeter.update(progress)
                onProgress(progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { poll.cancel() }
        do {
            try await request.downloadAndInstall()
        } catch is CancellationError {
            progress.cancel()
            throw CancellationError()
        } catch {
            throw MeetingTranscriptionError.speechAssetUnavailable(installFailureMessage(error))
        }
        onProgress(1)
    }

    /// Final transcript only. Volatile draft text is not returned.
    static func transcribe(audioURL: URL) async throws -> [MeetingSpeechToken] {
        let transcriber = makeTranscriber()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let collected = collectFinalTokens(from: transcriber)
        let file = try AVAudioFile(forReading: audioURL)
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        return try await collected
    }

    private static func makeTranscriber() -> SpeechTranscriber {
        SpeechTranscriber(
            locale: Locale(identifier: "zh-CN"),
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence]
        )
    }

    private static func collectFinalTokens(from transcriber: SpeechTranscriber) async throws -> [MeetingSpeechToken] {
        var tokens: [MeetingSpeechToken] = []
        for try await result in transcriber.results {
            guard result.isFinal else { continue }
            tokens.append(contentsOf: speechTokens(from: result))
        }
        return tokens
    }

    private static func speechTokens(from result: SpeechTranscriber.Result) -> [MeetingSpeechToken] {
        var tokens: [MeetingSpeechToken] = []
        for run in result.text.runs {
            let text = String(result.text[run.range].characters)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let timeRange = run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] ?? result.range
            let confidence = run[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self]
            guard let token = token(text: text, timeRange: timeRange, confidence: confidence) else { continue }
            tokens.append(token)
        }
        if tokens.isEmpty {
            let text = String(result.text.characters)
            if let token = token(text: text, timeRange: result.range, confidence: nil) {
                tokens.append(token)
            }
        }
        return tokens
    }

    private static func token(
        text: String,
        timeRange: CMTimeRange,
        confidence: Double?
    ) -> MeetingSpeechToken? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, timeRange.start.isValid, timeRange.duration.isValid else { return nil }
        let start = CMTimeGetSeconds(timeRange.start)
        let end = CMTimeGetSeconds(timeRange.end)
        guard start.isFinite, end.isFinite else { return nil }
        return MeetingSpeechToken(
            startTime: start,
            endTime: max(end, start),
            text: text,
            confidence: confidence
        )
    }

    private static func networkIsUnavailable() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "com.jarvis.meeting.asset-network")
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                continuation.resume(returning: path.status != .satisfied)
            }
            monitor.start(queue: queue)
        }
    }

    private static func installFailureMessage(_ error: Error) -> String {
        let description = error.localizedDescription
        if description.localizedCaseInsensitiveContains("network") || description.contains("网络") {
            return "系统中文转写资源下载失败：网络不可用。资源来自系统，下载一次后可离线使用。"
        }
        if description.localizedCaseInsensitiveContains("disk") || description.contains("空间") {
            return "系统中文转写资源下载失败：磁盘空间不足。"
        }
        return "系统中文转写资源下载失败：\(description)"
    }
}
