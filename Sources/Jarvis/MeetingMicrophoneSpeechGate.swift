import AVFoundation
import Foundation

/// Decides which microphone samples are written during an online meeting.
/// System playback stays on the system track. The mic file keeps the local voice
/// and writes silence for everything else, so the two tracks stay aligned.
struct MeetingMicrophoneSpeechGate {
    /// While the system track is audible, only close speech is written.
    static let playbackSpeechFloorDB: Float = -30
    /// While nobody is playing through the speakers, softer speech still counts.
    static let quietSpeechFloorDB: Float = -42
    static let systemAudibleDB: Float = -45
    static let hangover: TimeInterval = 0.45
    static let preroll: TimeInterval = 0.2

    var enabled: Bool
    private var clock: TimeInterval = 0
    private var speakingUntil: TimeInterval = -.infinity
    private var held: [Float] = []

    mutating func consume(
        samples: [Float],
        sampleRate: Double,
        systemPower: Float?
    ) -> [Float] {
        guard enabled, sampleRate > 0, !samples.isEmpty else { return samples }
        let frameDuration = Double(samples.count) / sampleRate
        let end = clock + frameDuration
        let keep = keeps(power: Self.powerDB(samples), systemPower: systemPower, at: end)
        clock = end
        let prerollCount = max(1, Int((Self.preroll * sampleRate).rounded()))
        if keep {
            var output = held
            held.removeAll(keepingCapacity: true)
            output.append(contentsOf: samples)
            return output
        }
        held.append(contentsOf: samples)
        guard held.count > prerollCount else { return [] }
        let overflow = held.count - prerollCount
        held.removeFirst(overflow)
        return [Float](repeating: 0, count: overflow)
    }

    /// Samples still held for a possible word onset become silence when recording stops.
    mutating func flush() -> [Float] {
        let silence = [Float](repeating: 0, count: held.count)
        held.removeAll(keepingCapacity: true)
        return silence
    }

    private mutating func keeps(power: Float, systemPower: Float?, at time: TimeInterval) -> Bool {
        let system = systemPower ?? Self.silentPower
        let floor = system > Self.systemAudibleDB ? Self.playbackSpeechFloorDB : Self.quietSpeechFloorDB
        if power >= floor {
            speakingUntil = time + Self.hangover
            return true
        }
        return time <= speakingUntil
    }

    private static let silentPower: Float = -160

    static func powerDB(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return silentPower }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(samples.count))
        return 20 * log10(max(rms, 0.000_000_1))
    }
}

/// Writes the microphone track. Online meetings run samples through the speech gate.
final class MeetingMicrophoneCapture: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.jarvis.meeting.microphone-writer", qos: .userInitiated)
    private let stateLock = NSLock()
    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var gate = MeetingMicrophoneSpeechGate(enabled: false)
    private var framesWritten: AVAudioFramePosition = 0
    private var sampleRate: Double = 44100
    private var latestPower: Float?
    private var running = false
    private var systemPower: @Sendable () -> Float? = { nil }

    var isRunning: Bool {
        stateLock.lock()
        let active = running
        let engine = self.engine
        stateLock.unlock()
        return active && engine?.isRunning == true
    }

    var currentDuration: TimeInterval {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard sampleRate > 0 else { return 0 }
        return Double(framesWritten) / sampleRate
    }

    func averagePower() -> Float? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard running else { return nil }
        return latestPower
    }

    func start(
        url: URL,
        gateSpeech: Bool,
        systemPower: @escaping @Sendable () -> Float?
    ) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MeetingRecorderError.cannotStart
        }
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: url, settings: settings)
        } catch {
            throw MeetingRecorderError.cannotStart
        }
        guard let converter = AVAudioConverter(from: format, to: file.processingFormat) else {
            throw MeetingRecorderError.cannotStart
        }

        stateLock.lock()
        self.engine = engine
        self.file = file
        self.converter = converter
        self.systemPower = systemPower
        gate = MeetingMicrophoneSpeechGate(enabled: gateSpeech)
        framesWritten = 0
        sampleRate = file.processingFormat.sampleRate
        latestPower = nil
        running = true
        stateLock.unlock()

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let copy = Self.copy(buffer) else { return }
            let box = MicrophoneBufferBox(copy)
            self.queue.async {
                self.write(box.buffer)
            }
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            stateLock.lock()
            self.engine = nil
            self.file = nil
            self.converter = nil
            running = false
            stateLock.unlock()
            throw MeetingRecorderError.cannotStart
        }
    }

    func setGateSpeech(_ enabled: Bool) {
        queue.async { [weak self] in
            self?.gate.enabled = enabled
        }
    }

    /// Closes the file. The returned duration includes the flushed onset buffer.
    func finish() -> TimeInterval {
        stateLock.lock()
        running = false
        let engine = self.engine
        self.engine = nil
        stateLock.unlock()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()

        var duration: TimeInterval = 0
        queue.sync {
            writeSamples(gate.flush(), formatSampleRate: sampleRate)
            file = nil
            converter = nil
            duration = sampleRate > 0 ? Double(framesWritten) / sampleRate : 0
        }
        return duration
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        stateLock.lock()
        let file = self.file
        let converter = self.converter
        let readPower = systemPower
        stateLock.unlock()
        guard let file, let converter else { return }

        let ratio = file.processingFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) else {
            return
        }
        var consumed = false
        var conversionError: NSError?
        converter.convert(to: converted, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard conversionError == nil,
              converted.frameLength > 0,
              let channel = converted.floatChannelData?[0]
        else { return }

        let frames = Int(converted.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channel, count: frames))
        let power = MeetingMicrophoneSpeechGate.powerDB(samples)
        stateLock.lock()
        latestPower = power
        stateLock.unlock()
        let output = gate.consume(
            samples: samples,
            sampleRate: file.processingFormat.sampleRate,
            systemPower: readPower()
        )
        writeSamples(output, formatSampleRate: file.processingFormat.sampleRate)
    }

    private func writeSamples(_ samples: [Float], formatSampleRate: Double) {
        guard !samples.isEmpty else { return }
        stateLock.lock()
        let file = self.file
        stateLock.unlock()
        guard let file,
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: file.processingFormat,
                  frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channel = buffer.floatChannelData?[0]
        else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            channel.update(from: base, count: samples.count)
        }
        do {
            try file.write(from: buffer)
            stateLock.lock()
            sampleRate = formatSampleRate
            framesWritten += AVAudioFramePosition(samples.count)
            stateLock.unlock()
        } catch {
            stateLock.lock()
            running = false
            stateLock.unlock()
        }
    }

    private final class MicrophoneBufferBox: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        init(_ buffer: AVAudioPCMBuffer) {
            self.buffer = buffer
        }
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let source = buffer.floatChannelData,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
              let destination = copy.floatChannelData
        else { return nil }
        copy.frameLength = buffer.frameLength
        let frames = Int(buffer.frameLength)
        for channel in 0 ..< Int(buffer.format.channelCount) {
            destination[channel].update(from: source[channel], count: frames)
        }
        return copy
    }
}
