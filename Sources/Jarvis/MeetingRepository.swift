import Foundation

final class MeetingRepository: @unchecked Sendable {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let recordingsURL: URL
    private let indexURL: URL
    private let lock = NSLock()

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        let baseURL = directoryURL ?? (
            try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        )?.appendingPathComponent(JarvisAppIdentity.dataDirectoryName, isDirectory: true)
            ?? fileManager.temporaryDirectory.appendingPathComponent("Jarvis", isDirectory: true)

        let meetingDirectory = baseURL.appendingPathComponent("Meetings", isDirectory: true)
        self.directoryURL = meetingDirectory
        self.recordingsURL = meetingDirectory.appendingPathComponent("Recordings", isDirectory: true)
        self.indexURL = meetingDirectory.appendingPathComponent("meetings.json", isDirectory: false)
        JarvisProtectedStorage.prepareDirectory(meetingDirectory, fileManager: fileManager)
        JarvisProtectedStorage.prepareDirectory(self.recordingsURL, fileManager: fileManager)
    }

    func load() -> [MeetingRecord] {
        lock.withLock { loadUnlocked().sorted { $0.createdAt > $1.createdAt } }
    }

    func save(_ record: MeetingRecord) throws {
        try lock.withLock {
            var records = loadUnlocked()
            records.removeAll { $0.id == record.id }
            records.insert(record, at: 0)
            let data = try JSONEncoder().encode(records.sorted { $0.createdAt > $1.createdAt })
            try JarvisProtectedStorage.write(data, to: indexURL)
        }
    }

    func delete(_ record: MeetingRecord) throws {
        try lock.withLock {
            for url in try audioURLs(for: record) {
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
            }
            var records = loadUnlocked()
            records.removeAll { $0.id == record.id }
            let data = try JSONEncoder().encode(records)
            try JarvisProtectedStorage.write(data, to: indexURL)
        }
    }

    func audioURL(for record: MeetingRecord) throws -> URL {
        guard isSafeAudioFileName(record.audioFileName) else {
            throw MeetingRepositoryError.invalidAudioFileName
        }
        return recordingsURL.appendingPathComponent(record.audioFileName, isDirectory: false)
    }

    /// Returns the microphone source for new records and the legacy primary
    /// audio file for records written before multi-track capture existed.
    func microphoneAudioURL(for record: MeetingRecord) throws -> URL {
        guard let fileName = record.microphoneAudioFileName else {
            return try audioURL(for: record)
        }
        guard isSafeAudioFileName(fileName) else {
            throw MeetingRepositoryError.invalidAudioFileName
        }
        return recordingsURL.appendingPathComponent(fileName, isDirectory: false)
    }

    func systemAudioURL(for record: MeetingRecord) throws -> URL? {
        guard let fileName = record.systemAudioFileName else { return nil }
        guard isSafeAudioFileName(fileName) else {
            throw MeetingRepositoryError.invalidAudioFileName
        }
        return recordingsURL.appendingPathComponent(fileName, isDirectory: false)
    }

    func recordingURLs(for id: UUID) -> (mixed: URL, microphone: URL, system: URL) {
        let prefix = "meeting-\(id.uuidString)"
        return (
            recordingsURL.appendingPathComponent("\(prefix).m4a", isDirectory: false),
            recordingsURL.appendingPathComponent("\(prefix).mic.m4a", isDirectory: false),
            recordingsURL.appendingPathComponent("\(prefix).system.caf", isDirectory: false)
        )
    }

    func recordingURL(for id: UUID) -> URL {
        recordingsURL.appendingPathComponent("meeting-\(id.uuidString).m4a", isDirectory: false)
    }

    private func loadUnlocked() -> [MeetingRecord] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? JSONDecoder().decode([MeetingRecord].self, from: data)) ?? []
    }

    private func isSafeAudioFileName(_ fileName: String) -> Bool {
        let prefix = "meeting-"
        guard fileName.hasPrefix(prefix) else { return false }
        let suffixes = [".mic.m4a", ".system.caf", ".m4a"]
        guard let suffix = suffixes.first(where: { fileName.hasSuffix($0) }) else {
            return false
        }
        let uuid = String(fileName.dropFirst(prefix.count).dropLast(suffix.count))
        return UUID(uuidString: uuid) != nil
    }

    private func audioURLs(for record: MeetingRecord) throws -> [URL] {
        var urls = try [audioURL(for: record), microphoneAudioURL(for: record)]
        if let systemURL = try systemAudioURL(for: record) {
            urls.append(systemURL)
        }
        return Array(Set(urls))
    }
}

enum MeetingRepositoryError: LocalizedError, Equatable {
    case invalidAudioFileName

    var errorDescription: String? {
        switch self {
        case .invalidAudioFileName: "会议录音文件名无效"
        }
    }
}
