import AVFoundation
import CoreAudio
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
    /// Slices finalized before the session state is cleared. Files may already be concatenated.
    let chunks: [MeetingAudioChunk]

    var systemAudioStartOffset: TimeInterval {
        MeetingAudioMixer.systemAudioInsertionDelay(
            microphoneStartedAt: microphoneStartedAt,
            systemAudioStartedAt: systemAudioStartedAt
        )
    }
}

@MainActor
final class MeetingRecorder {
    private var microphoneCapture: MeetingMicrophoneCapture?
    private var startedAt: Date?
    private let systemAudioRecorder = MeetingSystemAudioRecorder()
    private var systemAudioStarted = false
    private var systemAudioStartedAt: Date?
    /// 上一次 stop() 的异步收尾是否在途。App 层在发起 stop 时同步立起（Task 调度有窗口），
    /// stop() 返回时由 defer 落下。start 前必须检查：否则旧 stop 恢复后会清掉新会话的
    /// 采集状态，新录音收不到系统音频但 UI 显示正常（S-3）。
    private(set) var isStopping = false
    private(set) var isPaused = false
    var onUnexpectedStop: (@MainActor () -> Void)?
    var onAudioEvent: (@MainActor (MeetingAudioEvent) -> Void)?

    private var meetingID: UUID?
    private var directoryURL: URL?
    private var canonicalMicrophoneURL: URL?
    private var canonicalSystemURL: URL?
    private var capturesSystemAudio = true
    private var closedChunks: [MeetingAudioChunk] = []
    private var microphoneChunkIndex = 0
    private var systemChunkIndex = 0
    private var microphoneChunkOpenedAt: Date?
    private var wallAnchor = Date()
    private var pausedDuration: TimeInterval = 0
    private var pauseBegan: Date?
    private var accountedGap: TimeInterval = 0
    private var inputDeviceListener: MeetingInputDeviceListener?

    var isRecording: Bool {
        microphoneCapture?.isRunning == true
    }

    var isSessionOpen: Bool {
        meetingID != nil
    }

    /// dBFS of the live microphone. Nil when capture is not running.
    func microphoneAveragePower() -> Float? {
        microphoneCapture?.averagePower()
    }

    func systemAveragePower() -> Float? {
        systemAudioRecorder.latestPower
    }

    func writtenByteCount() -> Int64 {
        guard let directoryURL, meetingID != nil else { return 0 }
        let names = closedChunks.map(\.fileName) + [currentMicrophoneFileName, currentSystemFileName].compactMap { $0 }
        return names.reduce(into: Int64(0)) { total, name in
            let url = directoryURL.appendingPathComponent(name)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            total += size
        }
    }

    func snapshotChunks() -> [MeetingAudioChunk] {
        var chunks = closedChunks
        if let open = openMicrophoneChunk() {
            chunks.append(open)
        }
        if let open = openSystemChunk() {
            chunks.append(open)
        }
        return chunks
    }

    func closedChunksSnapshot() -> [MeetingAudioChunk] {
        closedChunks
    }

    func start(
        meetingID: UUID,
        microphoneURL: URL,
        systemAudioURL: URL,
        capturesSystemAudio: Bool
    ) async throws -> MeetingRecordingSources {
        guard !isStopping else {
            throw MeetingRecorderError.stopInProgress
        }
        guard !isSessionOpen else {
            return MeetingRecordingSources(
                systemAudioStarted: systemAudioStarted,
                systemAudioErrorMessage: nil
            )
        }

        self.meetingID = meetingID
        directoryURL = microphoneURL.deletingLastPathComponent()
        canonicalMicrophoneURL = microphoneURL
        canonicalSystemURL = systemAudioURL
        self.capturesSystemAudio = capturesSystemAudio
        closedChunks = []
        microphoneChunkIndex = 0
        systemChunkIndex = 0
        pausedDuration = 0
        pauseBegan = nil
        accountedGap = 0
        isPaused = false
        wallAnchor = Date()
        startedAt = Date()
        try beginMicrophoneChunk()
        installInputDeviceListener()

        guard capturesSystemAudio else {
            systemAudioStarted = false
            systemAudioStartedAt = nil
            return MeetingRecordingSources(systemAudioStarted: false, systemAudioErrorMessage: nil)
        }

        do {
            let chunkURL = try chunkURL(kind: .system, index: 0)
            try await systemAudioRecorder.start(to: chunkURL)
            systemAudioStarted = true
            systemAudioStartedAt = Date()
            microphoneCapture?.setGateSpeech(true)
            return MeetingRecordingSources(systemAudioStarted: true, systemAudioErrorMessage: nil)
        } catch {
            systemAudioStarted = false
            systemAudioStartedAt = nil
            microphoneCapture?.setGateSpeech(false)
            return MeetingRecordingSources(
                systemAudioStarted: false,
                systemAudioErrorMessage: error.localizedDescription
            )
        }
    }

    /// stop() 被丢进 Task 时同步立 flag：Task 调度有个窗口，不提前立的话
    /// start 能从窗口溜进去。stop() 返回时由 defer 落下。
    func markStopInFlight() {
        isStopping = true
    }

    /// Closes the open slice once it reaches 30 seconds. Returns slices that just closed.
    func rotateIfDue() -> [MeetingAudioChunk] {
        guard isSessionOpen, !isPaused else { return [] }
        var closed: [MeetingAudioChunk] = []
        let micDuration = microphoneCapture?.currentDuration ?? 0
        if micDuration >= MeetingAudioChunkFile.sliceDuration {
            let finished = finalizeMicrophoneChunk(duration: micDuration)
            closedChunks.append(contentsOf: finished)
            closed.append(contentsOf: finished)
            do {
                try beginMicrophoneChunk()
            } catch {
                onUnexpectedStop?()
            }
        }
        if systemAudioStarted, systemAudioRecorder.currentDuration >= MeetingAudioChunkFile.sliceDuration {
            if let chunk = finalizeSystemChunk() {
                closedChunks.append(chunk)
                closed.append(chunk)
            }
        }
        if let event = gapEventIfNeeded() {
            onAudioEvent?(event)
        }
        return closed
    }

    func pauseRecording() {
        guard isSessionOpen, !isPaused else { return }
        let micDuration = microphoneCapture?.currentDuration ?? 0
        if micDuration > 0.2 {
            closedChunks.append(contentsOf: finalizeMicrophoneChunk(duration: micDuration))
        } else {
            stopOpenMicrophoneRecorder()
        }
        if systemAudioStarted, let chunk = finalizeSystemChunk() {
            closedChunks.append(chunk)
        }
        systemAudioRecorder.setDroppingSamples(true)
        pauseBegan = Date()
        isPaused = true
    }

    func resumeRecording() throws {
        guard isPaused else { return }
        try beginMicrophoneChunk()
        if let pauseBegan {
            pausedDuration += Date().timeIntervalSince(pauseBegan)
        }
        pauseBegan = nil
        isPaused = false
        systemAudioRecorder.setDroppingSamples(false)
    }

    func stop() async -> MeetingRecordingStopResult {
        isStopping = true
        defer { isStopping = false }
        let microphoneStartedAt = startedAt ?? Date()
        let micDuration = microphoneCapture?.currentDuration ?? 0
        if MeetingMicrophoneRotation.keepsOpenSlice(micDuration) {
            closedChunks.append(contentsOf: finalizeMicrophoneChunk(duration: micDuration))
        } else {
            stopOpenMicrophoneRecorder()
        }
        let stats = await systemAudioRecorder.stop()
        if systemAudioStarted, stats.didWriteAudio, let chunk = takeOpenSystemChunk(duration: stats.duration) {
            closedChunks.append(chunk)
        }
        let finishedChunks = closedChunks
        let capturedSystemAudio = systemAudioStarted && stats.didWriteAudio
            && finishedChunks.contains { $0.kind == .system }
        var duration = finishedChunks.filter { $0.kind == .microphone }.reduce(0) { $0 + $1.duration }
        if let microphoneURL = canonicalMicrophoneURL {
            let micURLs = chunkURLs(kind: .microphone)
            if let assembled = try? await MeetingAudioAssembler.concatenate(urls: micURLs, outputURL: microphoneURL) {
                duration = max(duration, assembled)
                removeChunkFiles(kind: .microphone)
            }
        }
        if capturedSystemAudio, let systemURL = canonicalSystemURL {
            let systemURLs = chunkURLs(kind: .system)
            if await (try? MeetingAudioAssembler.concatenate(urls: systemURLs, outputURL: systemURL)) != nil {
                removeChunkFiles(kind: .system)
            }
        }
        let result = MeetingRecordingStopResult(
            duration: max(duration, 0),
            systemAudioStarted: capturedSystemAudio,
            microphoneStartedAt: microphoneStartedAt,
            systemAudioStartedAt: capturedSystemAudio ? stats.firstBufferAt : nil,
            systemAudioErrorMessage: stats.failureMessage,
            chunks: finishedChunks
        )
        resetSession()
        return result
    }

    /// Drops a session that never became a meeting. Does not write the canonical files.
    func discard() async {
        isStopping = true
        defer { isStopping = false }
        _ = microphoneCapture?.finish()
        microphoneCapture = nil
        _ = await systemAudioRecorder.stop()
        if let directoryURL, let meetingID {
            let prefix = "meeting-\(meetingID.uuidString)."
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )) ?? []
            for url in files where url.lastPathComponent.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        if let canonicalMicrophoneURL {
            try? FileManager.default.removeItem(at: canonicalMicrophoneURL)
        }
        if let canonicalSystemURL {
            try? FileManager.default.removeItem(at: canonicalSystemURL)
        }
        resetSession()
    }

    private var currentMicrophoneFileName: String? {
        guard let meetingID else { return nil }
        return MeetingAudioChunkFile.microphoneName(meetingID: meetingID, index: microphoneChunkIndex)
    }

    private var currentSystemFileName: String? {
        guard let meetingID, systemAudioStarted || systemChunkIndex > 0 else { return nil }
        return MeetingAudioChunkFile.systemName(meetingID: meetingID, index: systemChunkIndex)
    }

    private func beginMicrophoneChunk() throws {
        guard let meetingID, let directoryURL else { throw MeetingRecorderError.cannotStart }
        let name = MeetingAudioChunkFile.microphoneName(meetingID: meetingID, index: microphoneChunkIndex)
        let url = directoryURL.appendingPathComponent(name)
        let capture = MeetingMicrophoneCapture()
        try capture.start(
            url: url,
            gateSpeech: systemAudioStarted,
            systemPower: { [systemAudioRecorder] in
                systemAudioRecorder.latestPower
            }
        )
        microphoneCapture = capture
        microphoneChunkOpenedAt = Date()
    }

    private func finalizeMicrophoneChunk(duration _: TimeInterval) -> [MeetingAudioChunk] {
        guard let meetingID else { return [] }
        let duration = microphoneCapture?.finish() ?? 0
        microphoneCapture = nil
        let chunk = MeetingAudioChunk(
            kind: .microphone,
            index: microphoneChunkIndex,
            fileName: MeetingAudioChunkFile.microphoneName(meetingID: meetingID, index: microphoneChunkIndex),
            startOffset: closedChunks.filter { $0.kind == .microphone }.reduce(0) { $0 + $1.duration },
            duration: duration,
            closed: true
        )
        microphoneChunkIndex += 1
        microphoneChunkOpenedAt = nil
        return [chunk]
    }

    private func openMicrophoneChunk() -> MeetingAudioChunk? {
        guard let meetingID, let capture = microphoneCapture, capture.isRunning else { return nil }
        return MeetingAudioChunk(
            kind: .microphone,
            index: microphoneChunkIndex,
            fileName: MeetingAudioChunkFile.microphoneName(meetingID: meetingID, index: microphoneChunkIndex),
            startOffset: closedChunks.filter { $0.kind == .microphone }.reduce(0) { $0 + $1.duration },
            duration: capture.currentDuration,
            closed: false
        )
    }

    private func finalizeSystemChunk() -> MeetingAudioChunk? {
        guard let meetingID, let directoryURL else { return nil }
        let duration = systemAudioRecorder.currentDuration
        let closedName = MeetingAudioChunkFile.systemName(meetingID: meetingID, index: systemChunkIndex)
        let closedIndex = systemChunkIndex
        systemChunkIndex += 1
        let nextURL = directoryURL.appendingPathComponent(
            MeetingAudioChunkFile.systemName(meetingID: meetingID, index: systemChunkIndex)
        )
        systemAudioRecorder.rotate(to: nextURL)
        guard duration > 0 else { return nil }
        return MeetingAudioChunk(
            kind: .system,
            index: closedIndex,
            fileName: closedName,
            startOffset: closedChunks.filter { $0.kind == .system }.reduce(0) { $0 + $1.duration },
            duration: duration,
            closed: true
        )
    }

    private func takeOpenSystemChunk(duration: TimeInterval) -> MeetingAudioChunk? {
        guard let meetingID, duration > 0 else { return nil }
        return MeetingAudioChunk(
            kind: .system,
            index: systemChunkIndex,
            fileName: MeetingAudioChunkFile.systemName(meetingID: meetingID, index: systemChunkIndex),
            startOffset: closedChunks.filter { $0.kind == .system }.reduce(0) { $0 + $1.duration },
            duration: duration,
            closed: true
        )
    }

    private func openSystemChunk() -> MeetingAudioChunk? {
        guard let meetingID, systemAudioStarted else { return nil }
        let duration = systemAudioRecorder.currentDuration
        guard duration > 0 else { return nil }
        return MeetingAudioChunk(
            kind: .system,
            index: systemChunkIndex,
            fileName: MeetingAudioChunkFile.systemName(meetingID: meetingID, index: systemChunkIndex),
            startOffset: closedChunks.filter { $0.kind == .system }.reduce(0) { $0 + $1.duration },
            duration: duration,
            closed: false
        )
    }

    private func chunkURLs(kind: MeetingAudioChunkKind) -> [URL] {
        guard let directoryURL else { return [] }
        return closedChunks.filter { $0.kind == kind }.map { directoryURL.appendingPathComponent($0.fileName) }
    }

    private func removeChunkFiles(kind: MeetingAudioChunkKind) {
        for url in chunkURLs(kind: kind) {
            try? FileManager.default.removeItem(at: url)
        }
        closedChunks.removeAll { $0.kind == kind }
    }

    private func chunkURL(kind: MeetingAudioChunkKind, index: Int) throws -> URL {
        guard let meetingID, let directoryURL else { throw MeetingRecorderError.cannotStart }
        let name = kind == .microphone
            ? MeetingAudioChunkFile.microphoneName(meetingID: meetingID, index: index)
            : MeetingAudioChunkFile.systemName(meetingID: meetingID, index: index)
        return directoryURL.appendingPathComponent(name)
    }

    private func gapEventIfNeeded() -> MeetingAudioEvent? {
        let recorded = closedChunks.filter { $0.kind == .microphone }.reduce(0) { $0 + $1.duration }
            + (microphoneCapture?.currentDuration ?? 0)
        var wall = Date().timeIntervalSince(wallAnchor) - pausedDuration
        if let pauseBegan {
            wall -= Date().timeIntervalSince(pauseBegan)
        }
        let gap = wall - recorded
        guard gap > accountedGap + 5 else { return nil }
        accountedGap = gap
        return MeetingAudioEvent(
            at: recorded,
            kind: .gap,
            message: "录音中断超过 5 秒，已写入恢复标记"
        )
    }

    private func installInputDeviceListener() {
        inputDeviceListener = MeetingInputDeviceListener { [weak self] in
            self?.handleInputDeviceChange()
        }
    }

    private func handleInputDeviceChange() {
        guard isSessionOpen, !isPaused, !isStopping else { return }
        let duration = microphoneCapture?.currentDuration ?? 0
        if MeetingMicrophoneRotation.keepsOpenSlice(duration) {
            closedChunks.append(contentsOf: finalizeMicrophoneChunk(duration: duration))
        } else {
            stopOpenMicrophoneRecorder()
        }
        do {
            try beginMicrophoneChunk()
        } catch {
            onUnexpectedStop?()
        }
        onAudioEvent?(
            MeetingAudioEvent(
                at: closedChunks.filter { $0.kind == .microphone }.reduce(0) { $0 + $1.duration },
                kind: .deviceChange,
                message: "输入设备变了，录音已跟着切换"
            )
        )
    }

    private func stopOpenMicrophoneRecorder() {
        _ = microphoneCapture?.finish()
        microphoneCapture = nil
    }

    private func resetSession() {
        inputDeviceListener = nil
        microphoneCapture = nil
        startedAt = nil
        meetingID = nil
        directoryURL = nil
        canonicalMicrophoneURL = nil
        canonicalSystemURL = nil
        closedChunks = []
        systemAudioStarted = false
        systemAudioStartedAt = nil
        isPaused = false
    }
}

enum MeetingMicrophoneRotation {
    /// Same floor `stop()` uses. A device change keeps a slice that already has audio
    /// instead of deleting the open file. Pause still drops slices of 0.2 seconds or less.
    static let minimumKeptSlice: TimeInterval = 0.05

    static func keepsOpenSlice(_ duration: TimeInterval) -> Bool {
        duration > minimumKeptSlice
    }
}

enum MeetingSystemAudioStopNotice {
    static func message(wroteSystemAudio: Bool, failureMessage: String?) -> String? {
        guard wroteSystemAudio, failureMessage != nil else { return nil }
        return JarvisFeedbackCopy.systemAudioCaptureInterrupted
    }
}

struct MeetingSystemLevelState: Equatable {
    static let silentFloor: Float = -160

    var power: Float?
    var frozen = false

    static func shouldFreeze(stopRequested: Bool) -> Bool {
        !stopRequested
    }

    mutating func observe(_ samplePower: Float) {
        guard !frozen else { return }
        power = samplePower
    }

    mutating func freezeSilent() {
        frozen = true
        power = Self.silentFloor
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
                "未开启屏幕录制权限，无法采集系统音频。请到系统设置 > 隐私与安全性 > 屏幕录制，允许贾维斯。"
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
    private var stopRequested = false
    private var levelState = MeetingSystemLevelState()

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
        let duration: TimeInterval
    }

    private var droppingSamples = false
    private var framesWritten: AVAudioFramePosition = 0
    private var sampleRate: Double = 48000

    var latestPower: Float? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return levelState.power
    }

    var currentDuration: TimeInterval {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard sampleRate > 0 else { return 0 }
        return Double(framesWritten) / sampleRate
    }

    func setDroppingSamples(_ dropping: Bool) {
        stateLock.lock()
        droppingSamples = dropping
        stateLock.unlock()
    }

    private func markStopRequested() {
        stateLock.lock()
        stopRequested = true
        stateLock.unlock()
    }

    func rotate(to url: URL) {
        writeQueue.sync {
            stateLock.lock()
            audioFile = nil
            outputURL = url
            framesWritten = 0
            stateLock.unlock()
        }
    }

    func stop() async -> CaptureStats {
        markStopRequested()
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
            failureMessage: failureMessage,
            duration: sampleRate > 0 ? Double(framesWritten) / sampleRate : 0
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

            self.stateLock.lock()
            let dropping = self.droppingSamples
            self.stateLock.unlock()
            if let packet = MeetingPCMPacket(buffer: buffer) {
                let power = Self.powerDB(samples: packet.samples)
                self.stateLock.lock()
                self.levelState.observe(power)
                self.stateLock.unlock()
            }
            if dropping {
                return
            }

            // #13：audioFile 引用的创建与读取统一走 stateLock——writeQueue 与
            // stop() 路径（clearCaptureState 置 nil）并发访问，类是 @unchecked Sendable。
            // 锁内不调 recordFailure（它自己也拿锁，会死锁），先解锁再记失败。
            self.stateLock.lock()
            if self.audioFile == nil {
                do {
                    self.audioFile = try AVAudioFile(
                        forWriting: outputURL,
                        settings: format.settings
                    )
                    self.sampleRate = format.sampleRate
                } catch {
                    self.stateLock.unlock()
                    self.recordFailure("无法写入系统音频：\(error.localizedDescription)")
                    return
                }
            }
            let audioFile = self.audioFile
            self.stateLock.unlock()

            do {
                try audioFile?.write(from: buffer)
                self.stateLock.lock()
                if !didWriteAudio {
                    firstBufferAt = Date()
                }
                didWriteAudio = true
                framesWritten += AVAudioFramePosition(buffer.frameLength)
                self.stateLock.unlock()
            } catch {
                self.recordFailure("系统音频写入中断：\(error.localizedDescription)")
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Swift.Error) {
        stateLock.lock()
        let current = self.stream
        let stopping = stopRequested
        stateLock.unlock()
        guard stream === current, MeetingSystemLevelState.shouldFreeze(stopRequested: stopping) else {
            return
        }
        recordFailure("系统音频采集中断：\(error.localizedDescription)")
        stateLock.lock()
        levelState.freezeSilent()
        stateLock.unlock()
    }

    private static func powerDB(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -160 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(samples.count))
        return 20 * log10(max(rms, 0.000_000_1))
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
        framesWritten = 0
        stopRequested = false
        levelState = MeetingSystemLevelState()
        droppingSamples = false
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

private final class MeetingInputDeviceListener {
    private final class Box: @unchecked Sendable {
        var fire: (@MainActor () -> Void)?
    }

    private let box = Box()
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private let listener: AudioObjectPropertyListenerBlock

    init(onChange: @escaping @MainActor () -> Void) {
        box.fire = onChange
        let captured = box
        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in
                captured.fire?()
            }
        }
        self.listener = listener
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            listener
        )
    }

    deinit {
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            listener
        )
    }
}

enum MeetingRecorderError: LocalizedError {
    case cannotStart
    case stopInProgress

    var errorDescription: String? {
        switch self {
        case .cannotStart: "无法开始录音，请检查麦克风权限和输入设备"
        case .stopInProgress: "上一次录音正在收尾，请稍后再试"
        }
    }
}
