import AVFoundation
import Foundation

enum MeetingCaptureMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case dual
    case microphone

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .dual: "线上双轨"
        case .microphone: "线下单麦"
        }
    }
}

enum MeetingAudioChunkKind: String, Codable, Sendable {
    case microphone
    case system
}

struct MeetingAudioChunk: Codable, Equatable, Sendable {
    var kind: MeetingAudioChunkKind
    var index: Int
    var fileName: String
    var startOffset: TimeInterval
    var duration: TimeInterval
    /// False while this slice is still the open file. A crash may lose only that slice.
    var closed: Bool
}

struct MeetingAudioEvent: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var at: TimeInterval
    var kind: Kind
    var message: String

    enum Kind: String, Codable, Sendable {
        case gap
        case deviceChange
    }

    init(id: UUID = UUID(), at: TimeInterval, kind: Kind, message: String) {
        self.id = id
        self.at = at
        self.kind = kind
        self.message = message
    }
}

struct MeetingSpeakerTurnRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var clusterID: String

    init(id: UUID = UUID(), startTime: TimeInterval, endTime: TimeInterval, clusterID: String) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.clusterID = clusterID
    }
}

struct MeetingSegmentSpeakerOverride: Codable, Equatable, Sendable {
    var segmentID: UUID
    var speakerID: String
}

struct MeetingMinutesVersion: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var savedAt: Date
    var summary: MeetingSummary

    init(id: UUID = UUID(), savedAt: Date = Date(), summary: MeetingSummary) {
        self.id = id
        self.savedAt = savedAt
        self.summary = summary
    }
}

struct MeetingPCMPacket: Sendable {
    var sampleRate: Double
    var samples: [Float]

    init?(buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        guard frames > 0, buffer.format.sampleRate > 0 else { return nil }
        sampleRate = buffer.format.sampleRate
        if let channels = buffer.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            var mono = [Float](repeating: 0, count: frames)
            let usedChannels = max(channelCount, 1)
            for channel in 0 ..< channelCount {
                let data = channels[channel]
                for frame in 0 ..< frames {
                    mono[frame] += data[frame] / Float(usedChannels)
                }
            }
            samples = mono
            return
        }
        return nil
    }
}

enum MeetingAudioChunkFile {
    static let sliceDuration: TimeInterval = 30

    static func microphoneName(meetingID: UUID, index: Int) -> String {
        String(format: "meeting-%@.mic.%03d.m4a", meetingID.uuidString, index)
    }

    static func systemName(meetingID: UUID, index: Int) -> String {
        String(format: "meeting-%@.system.%03d.caf", meetingID.uuidString, index)
    }

    static func isChunkFileName(_ fileName: String) -> Bool {
        guard fileName.hasPrefix("meeting-") else { return false }
        let pattern = #"^meeting-[0-9A-Fa-f-]{36}\.(mic|system)\.\d{3}\.(m4a|caf)$"#
        return fileName.range(of: pattern, options: .regularExpression) != nil
    }

    /// Files found after a crash. The newest slice of each track may still be open.
    static func discoveredChunks(meetingID: UUID, fileNames: [String]) -> [MeetingAudioChunk] {
        let prefix = "meeting-\(meetingID.uuidString)."
        var parsed: [(kind: MeetingAudioChunkKind, index: Int, fileName: String)] = []
        for name in fileNames {
            guard name.hasPrefix(prefix), isChunkFileName(name) else { continue }
            let parts = name.split(separator: ".")
            guard parts.count == 4, let index = Int(parts[2]) else { continue }
            let kind: MeetingAudioChunkKind
            switch parts[1] {
            case "mic":
                kind = .microphone
            case "system":
                kind = .system
            default:
                continue
            }
            parsed.append((kind, index, name))
        }
        let latestMicrophone = parsed.filter { $0.kind == .microphone }.map(\.index).max()
        let latestSystem = parsed.filter { $0.kind == .system }.map(\.index).max()
        return parsed.map { item in
            let latest = item.kind == .microphone ? latestMicrophone : latestSystem
            return MeetingAudioChunk(
                kind: item.kind,
                index: item.index,
                fileName: item.fileName,
                startOffset: 0,
                duration: 0,
                closed: item.index != latest
            )
        }.sorted { lhs, rhs in
            if lhs.kind == rhs.kind {
                return lhs.index < rhs.index
            }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
    }

    /// Stored metadata wins the closed flag. Disk names fill slices the record never saved.
    static func mergedChunks(stored: [MeetingAudioChunk], discovered: [MeetingAudioChunk]) -> [MeetingAudioChunk] {
        var byKey: [String: MeetingAudioChunk] = [:]
        for chunk in discovered {
            byKey[chunkKey(chunk)] = chunk
        }
        for chunk in stored {
            let key = chunkKey(chunk)
            if var existing = byKey[key] {
                existing.closed = chunk.closed
                if chunk.duration > 0 {
                    existing.duration = chunk.duration
                }
                existing.startOffset = chunk.startOffset
                byKey[key] = existing
            } else {
                byKey[key] = chunk
            }
        }
        return byKey.values.sorted { lhs, rhs in
            if lhs.kind == rhs.kind {
                return lhs.index < rhs.index
            }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
    }

    private static func chunkKey(_ chunk: MeetingAudioChunk) -> String {
        "\(chunk.kind.rawValue)#\(chunk.index)"
    }

    /// Closed slices are kept. The open slice is kept only when the container can be read.
    static func recoverableChunks(_ chunks: [MeetingAudioChunk], playable: (MeetingAudioChunk) -> Bool) -> [MeetingAudioChunk] {
        chunks.filter { chunk in
            chunk.closed || playable(chunk)
        }
    }
}

enum MeetingCanonicalAssembly {
    struct Plan: Equatable {
        var assembleMicrophone: Bool
        var assembleSystem: Bool
    }

    /// A playable canonical file stays as it is. The other track can still be built from slices.
    static func plan(microphoneReady: Bool, systemReady: Bool) -> Plan {
        Plan(
            assembleMicrophone: !microphoneReady,
            assembleSystem: !systemReady
        )
    }
}

enum MeetingAudioAssembler {
    static func concatenate(urls: [URL], outputURL: URL) async throws -> TimeInterval {
        let ready = urls.filter { MeetingAudioMixer.isReadyAudioFile(at: $0) }
        guard let first = ready.first else {
            throw MeetingAudioMixer.Error.noAudioTrack
        }
        if ready.count == 1 {
            if first.standardizedFileURL != outputURL.standardizedFileURL {
                try? FileManager.default.removeItem(at: outputURL)
                try FileManager.default.copyItem(at: first, to: outputURL)
            }
            return await playableDuration(at: outputURL) ?? 0
        }
        if outputURL.pathExtension.lowercased() == "caf" {
            return try concatenateCAF(urls: ready, outputURL: outputURL)
        }
        return try await concatenateWithExport(urls: ready, outputURL: outputURL)
    }

    static func playableDuration(at url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        let playable = await (try? asset.load(.isPlayable)) ?? false
        guard playable else { return nil }
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    private static func concatenateWithExport(urls: [URL], outputURL: URL) async throws -> TimeInterval {
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw MeetingAudioMixer.Error.noAudioTrack
        }
        var cursor = CMTime.zero
        for url in urls {
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard let assetTrack = tracks.first else { continue }
            let duration = try await asset.load(.duration)
            guard duration.seconds > 0 else { continue }
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: assetTrack, at: cursor)
            cursor = CMTimeAdd(cursor, duration)
        }
        guard cursor.seconds > 0 else {
            throw MeetingAudioMixer.Error.noAudioTrack
        }
        try? FileManager.default.removeItem(at: outputURL)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw MeetingAudioMixer.Error.exportFailed
        }
        exporter.shouldOptimizeForNetworkUse = false
        try await exporter.export(to: outputURL, as: .m4a)
        return cursor.seconds
    }

    private static func concatenateCAF(urls: [URL], outputURL: URL) throws -> TimeInterval {
        let first = try AVAudioFile(forReading: urls[0])
        try? FileManager.default.removeItem(at: outputURL)
        let output = try AVAudioFile(forWriting: outputURL, settings: first.fileFormat.settings)
        var frames: AVAudioFramePosition = 0
        for url in urls {
            let input = try AVAudioFile(forReading: url)
            guard input.processingFormat.sampleRate == first.processingFormat.sampleRate else { continue }
            let capacity = AVAudioFrameCount(input.length)
            guard capacity > 0, let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: capacity) else {
                continue
            }
            try input.read(into: buffer)
            try output.write(from: buffer)
            frames += AVAudioFramePosition(buffer.frameLength)
        }
        let rate = first.processingFormat.sampleRate
        guard rate > 0, frames > 0 else {
            throw MeetingAudioMixer.Error.noAudioTrack
        }
        return Double(frames) / rate
    }
}

enum MeetingSpeakerRemerge {
    static func apply(
        segments: [MeetingTranscriptSegment],
        turns: [MeetingSpeakerTurnRecord],
        overrides: [MeetingSegmentSpeakerOverride],
        speakers: [MeetingSpeaker]
    ) -> (segments: [MeetingTranscriptSegment], speakers: [MeetingSpeaker]) {
        let overrideMap = Dictionary(overrides.map { ($0.segmentID, $0.speakerID) }, uniquingKeysWith: { _, latest in latest })
        let algorithmTurns = turns.map {
            MeetingMinutesAlgorithm.SpeakerTurn(
                speakerID: $0.clusterID,
                startTime: $0.startTime,
                endTime: $0.endTime
            )
        }
        var names = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0.name) })
        var updated = segments
        for index in updated.indices {
            let segment = updated[index]
            let speakerID: String = if let override = overrideMap[segment.id] {
                override
            } else if algorithmTurns.isEmpty {
                segment.speakerID
            } else {
                MeetingMinutesAlgorithm.assignedSpeakerID(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    turns: algorithmTurns
                )
            }
            updated[index].speakerID = speakerID
            updated[index].isUncertainSpeaker = speakerID == MeetingMinutesAlgorithm.uncertainSpeakerID
            if names[speakerID] == nil {
                if speakerID == MeetingMinutesAlgorithm.uncertainSpeakerID {
                    names[speakerID] = MeetingMinutesAlgorithm.uncertainSpeakerName
                } else {
                    let numbered = names.values.filter { $0.hasPrefix("说话人 ") }.count
                    names[speakerID] = "说话人 \(numbered + 1)"
                }
            }
        }
        var ordered: [String] = []
        for segment in updated where !ordered.contains(segment.speakerID) {
            ordered.append(segment.speakerID)
        }
        let rebuilt = ordered.enumerated().map { index, id in
            MeetingSpeaker(id: id, name: names[id] ?? "说话人 \(index + 1)", colorIndex: index)
        }
        return (updated, rebuilt)
    }
}
