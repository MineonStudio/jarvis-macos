import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

struct MeetingRecordingSources: Sendable {
    let systemAudioStarted: Bool
    let systemAudioErrorMessage: String?
}

struct MeetingRecordingStopResult: Sendable {
    let duration: TimeInterval
    let systemAudioStarted: Bool
    let microphoneStartedAt: Date
    let systemAudioStartedAt: Date?
    let systemAudioErrorMessage: String?

    var systemAudioStartOffset: TimeInterval {
        MeetingAudioMixer.systemAudioInsertionDelay(
            microphoneStartedAt: microphoneStartedAt,
            systemAudioStartedAt: systemAudioStartedAt
        )
    }
}

@MainActor
final class MeetingRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?
    private let systemAudioRecorder = MeetingSystemAudioRecorder()
    private var systemAudioStarted = false
    private var systemAudioStartedAt: Date?
    private var expectsStopCallback = false
    var onUnexpectedStop: (@MainActor () -> Void)?

    var isRecording: Bool {
        recorder?.isRecording == true
    }

    func start(
        microphoneURL: URL,
        systemAudioURL: URL
    ) async throws -> MeetingRecordingSources {
        guard !isRecording else {
            return MeetingRecordingSources(
                systemAudioStarted: systemAudioStarted,
                systemAudioErrorMessage: nil
            )
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: microphoneURL, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord() else {
            throw MeetingRecorderError.cannotStart
        }
        guard recorder.record() else {
            throw MeetingRecorderError.cannotStart
        }

        self.recorder = recorder
        startedAt = Date()
        expectsStopCallback = false

        do {
            try await systemAudioRecorder.start(to: systemAudioURL)
            systemAudioStarted = true
            systemAudioStartedAt = Date()
            return MeetingRecordingSources(systemAudioStarted: true, systemAudioErrorMessage: nil)
        } catch {
            systemAudioStarted = false
            systemAudioStartedAt = nil
            return MeetingRecordingSources(
                systemAudioStarted: false,
                systemAudioErrorMessage: error.localizedDescription
            )
        }
    }

    func stop() async -> MeetingRecordingStopResult {
        expectsStopCallback = true
        let microphoneStartedAt = startedAt ?? Date()
        let recordedDuration = recorder?.currentTime ?? 0
        recorder?.stop()
        let fallbackDuration = Date().timeIntervalSince(microphoneStartedAt)
        let duration = recordedDuration > 0 ? recordedDuration : fallbackDuration
        recorder = nil
        startedAt = nil

        let stats = await systemAudioRecorder.stop()
        let capturedSystemAudio = systemAudioStarted && stats.didWriteAudio
        let result = MeetingRecordingStopResult(
            duration: max(duration, 0),
            systemAudioStarted: capturedSystemAudio,
            microphoneStartedAt: microphoneStartedAt,
            systemAudioStartedAt: capturedSystemAudio ? stats.firstBufferAt : nil,
            systemAudioErrorMessage: stats.failureMessage
        )
        systemAudioStarted = false
        systemAudioStartedAt = nil
        expectsStopCallback = false
        return result
    }

    func cancel() async {
        expectsStopCallback = true
        recorder?.stop()
        recorder = nil
        startedAt = nil
        _ = await systemAudioRecorder.stop()
        systemAudioStarted = false
        systemAudioStartedAt = nil
        expectsStopCallback = false
    }

    nonisolated func audioRecorderDidFinishRecording(_: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            handleRecorderFinished(successfully: flag)
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_: AVAudioRecorder, error _: (any Error)?) {
        Task { @MainActor in
            handleRecorderFinished(successfully: false)
        }
    }

    private func handleRecorderFinished(successfully flag: Bool) {
        guard !expectsStopCallback else { return }
        guard recorder != nil else { return }
        if !flag || !isRecording {
            onUnexpectedStop?()
        }
    }
}

private final class MeetingSystemAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    enum Error: LocalizedError {
        case permissionDenied
        case noDisplay
        case captureFailed(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "未开启屏幕录制权限，无法采集系统音频"
            case .noDisplay:
                "未找到可用于系统音频采集的显示器"
            case let .captureFailed(message):
                "系统音频采集失败：\(message)"
            }
        }
    }

    private let stateLock = NSLock()
    private let writeQueue = DispatchQueue(
        label: "com.jarvis.meeting.system-audio-writer",
        qos: .userInitiated
    )
    private var stream: SCStream?
    private var outputURL: URL?
    private var audioFile: AVAudioFile?
    private var didWriteAudio = false
    private var firstBufferAt: Date?
    private var failureMessage: String?

    func start(to url: URL) async throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw Error.permissionDenied
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
        } catch {
            throw Error.captureFailed(error.localizedDescription)
        }

        guard let display = content.displays.first else {
            throw Error.noDisplay
        }

        try? FileManager.default.removeItem(at: url)
        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.capturesAudio = true
        configuration.sampleRate = 48000
        configuration.channelCount = 2
        // Do not record Jarvis's own sounds into a meeting source track.
        configuration.excludesCurrentProcessAudio = true

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(
                self,
                type: .audio,
                sampleHandlerQueue: writeQueue
            )
            setCaptureState(stream: stream, outputURL: url)

            try await stream.startCapture()
        } catch {
            clearCaptureState()
            throw Error.captureFailed(error.localizedDescription)
        }
    }

    struct CaptureStats: Sendable {
        let didWriteAudio: Bool
        let firstBufferAt: Date?
        let failureMessage: String?
    }

    func stop() async -> CaptureStats {
        let stream = currentStream()

        if let stream {
            try? await stream.stopCapture()
        }

        // stopCapture finishes callbacks asynchronously. This synchronization
        // drains queued sample buffers before the CAF is used for transcription.
        writeQueue.sync {}
        let stats = captureStats()
        clearCaptureState()
        return stats
    }

    private func captureStats() -> CaptureStats {
        stateLock.lock()
        defer { stateLock.unlock() }
        return CaptureStats(
            didWriteAudio: didWriteAudio,
            firstBufferAt: firstBufferAt,
            failureMessage: failureMessage
        )
    }

    func stream(
        _: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let outputURL = lockedOutputURL() else { return }

        try? sampleBuffer.withAudioBufferList { audioBufferList, _ in
            guard let formatDescription = sampleBuffer.formatDescription,
                  let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
                      formatDescription
                  ),
                  let format = AVAudioFormat(streamDescription: streamDescription),
                  let buffer = AVAudioPCMBuffer(
                      pcmFormat: format,
                      bufferListNoCopy: audioBufferList.unsafePointer
                  )
            else { return }

            if self.audioFile == nil {
                do {
                    self.audioFile = try AVAudioFile(
                        forWriting: outputURL,
                        settings: format.settings
                    )
                } catch {
                    self.recordFailure("无法写入系统音频：\(error.localizedDescription)")
                    return
                }
            }

            do {
                try self.audioFile?.write(from: buffer)
                self.stateLock.lock()
                if !didWriteAudio {
                    firstBufferAt = Date()
                }
                didWriteAudio = true
                self.stateLock.unlock()
            } catch {
                self.recordFailure("系统音频写入中断：\(error.localizedDescription)")
            }
        }
    }

    func stream(_: SCStream, didStopWithError error: Swift.Error) {
        recordFailure("系统音频采集中断：\(error.localizedDescription)")
    }

    private func recordFailure(_ message: String) {
        stateLock.lock()
        if failureMessage == nil {
            failureMessage = message
        }
        stateLock.unlock()
    }

    private func lockedOutputURL() -> URL? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return outputURL
    }

    private func currentStream() -> SCStream? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stream
    }

    private func setCaptureState(stream: SCStream, outputURL: URL) {
        stateLock.lock()
        self.stream = stream
        self.outputURL = outputURL
        audioFile = nil
        didWriteAudio = false
        firstBufferAt = nil
        failureMessage = nil
        stateLock.unlock()
    }

    private func clearCaptureState() {
        stateLock.lock()
        audioFile = nil
        stream = nil
        outputURL = nil
        stateLock.unlock()
    }
}

enum MeetingAudioMixer {
    enum Error: LocalizedError {
        case microphoneMissing
        case noAudioTrack
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .microphoneMissing: "麦克风原始录音文件不存在"
            case .noAudioTrack: "原始录音中没有可处理的音频轨道"
            case .exportFailed: "无法生成会议合并音轨"
            }
        }
    }

    static func systemAudioInsertionDelay(
        microphoneStartedAt: Date?,
        systemAudioStartedAt: Date?
    ) -> TimeInterval {
        guard let microphoneStartedAt, let systemAudioStartedAt else { return 0 }
        return max(0, systemAudioStartedAt.timeIntervalSince(microphoneStartedAt))
    }

    static func makeMixedAudio(
        microphoneURL: URL,
        systemAudioURL: URL?,
        outputURL: URL,
        systemAudioDelay: TimeInterval = 0
    ) async throws {
        guard isReadyAudioFile(at: microphoneURL) else {
            throw Error.microphoneMissing
        }

        if microphoneURL.standardizedFileURL == outputURL.standardizedFileURL {
            return
        }

        try? FileManager.default.removeItem(at: outputURL)
        guard let systemAudioURL, isReadyAudioFile(at: systemAudioURL) else {
            try FileManager.default.copyItem(at: microphoneURL, to: outputURL)
            return
        }

        let microphoneAsset = AVURLAsset(url: microphoneURL)
        let systemAsset = AVURLAsset(url: systemAudioURL)
        let microphoneTracks = try await microphoneAsset.loadTracks(withMediaType: .audio)
        let systemTracks = try await systemAsset.loadTracks(withMediaType: .audio)
        guard let microphoneTrack = microphoneTracks.first,
              let systemTrack = systemTracks.first
        else {
            throw Error.noAudioTrack
        }

        let microphoneDuration = try await microphoneAsset.load(.duration)
        let systemDuration = try await systemAsset.load(.duration)
        let composition = AVMutableComposition()
        guard let microphoneCompositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ),
            let systemCompositionTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw Error.noAudioTrack
        }

        try microphoneCompositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: microphoneDuration),
            of: microphoneTrack,
            at: .zero
        )
        let delay = max(0, systemAudioDelay)
        try systemCompositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: systemDuration),
            of: systemTrack,
            at: CMTime(seconds: delay, preferredTimescale: 600)
        )

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw Error.exportFailed
        }
        let microphoneMix = AVMutableAudioMixInputParameters(track: microphoneCompositionTrack)
        microphoneMix.setVolume(1.0, at: .zero)
        let systemMix = AVMutableAudioMixInputParameters(track: systemCompositionTrack)
        systemMix.setVolume(0.75, at: .zero)
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [microphoneMix, systemMix]
        exporter.audioMix = audioMix
        exporter.shouldOptimizeForNetworkUse = false
        try await exporter.export(to: outputURL, as: .m4a)
    }

    static func transcodeToM4A(inputURL: URL, outputURL: URL) async throws {
        guard isReadyAudioFile(at: inputURL) else {
            throw Error.noAudioTrack
        }
        if inputURL.standardizedFileURL == outputURL.standardizedFileURL {
            return
        }
        try? FileManager.default.removeItem(at: outputURL)
        let asset = AVURLAsset(url: inputURL)
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw Error.exportFailed
        }
        exporter.shouldOptimizeForNetworkUse = false
        try await exporter.export(to: outputURL, as: .m4a)
    }

    static func removeFileIfExists(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func isReadyAudioFile(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber
        else {
            return false
        }
        return fileSize.intValue > 0
    }
}

enum MeetingRecorderError: LocalizedError {
    case cannotStart

    var errorDescription: String? {
        switch self {
        case .cannotStart: "无法开始录音，请检查麦克风权限和输入设备"
        }
    }
}
