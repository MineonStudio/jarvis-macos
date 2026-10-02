import Foundation

struct MeetingRepositoryLoadResult: Equatable, Sendable {
    let records: [MeetingRecord]
    let errorMessage: String?
    let isReadOnly: Bool
}

final class MeetingRepository: @unchecked Sendable {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let recordingsURL: URL
    private let recordsURL: URL
    private let indexURL: URL
    private let lock = NSLock()
    private var writesDisabled = false
    /// #15：搜索文本缓存（内存轻量索引）。detailMatchesSearch 以前每次按键都对
    /// 全部会议逐条 lock + 读文件 + JSON 全量解码（含逐字稿），期间 save/load 被
    /// NSLock 阻塞。现在解码一次后缓存可搜索文本，写详情/删除时失效。
    /// 调用方持有 lock 时读写，无需额外同步。
    private var searchTextCache: [UUID: [String]] = [:]

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
        self.recordsURL = meetingDirectory.appendingPathComponent("Records", isDirectory: true)
        self.indexURL = meetingDirectory.appendingPathComponent("meetings.json", isDirectory: false)
        JarvisProtectedStorage.prepareDirectory(meetingDirectory, fileManager: fileManager)
        JarvisProtectedStorage.prepareDirectory(self.recordingsURL, fileManager: fileManager)
        JarvisProtectedStorage.prepareDirectory(self.recordsURL, fileManager: fileManager)
    }

    func load() -> MeetingRepositoryLoadResult {
        lock.withLock { loadUnlocked() }
    }

    func save(_ record: MeetingRecord) throws {
        try lock.withLock {
            guard !writesDisabled else {
                throw MeetingRepositoryError.writesDisabled
            }
            try writeRecordFile(record.metadataCopy)
            if !record.detail.isEmpty {
                try writeDetailFile(record.detail, for: record.id)
            }
        }
    }

    func delete(_ record: MeetingRecord) throws {
        try lock.withLock {
            guard !writesDisabled else {
                throw MeetingRepositoryError.writesDisabled
            }
            for url in try audioURLs(for: record) {
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
            }
            let recordFileURL = recordFileURL(for: record.id)
            if fileManager.fileExists(atPath: recordFileURL.path) {
                try fileManager.removeItem(at: recordFileURL)
            }
            let detailFileURL = detailFileURL(for: record.id)
            if fileManager.fileExists(atPath: detailFileURL.path) {
                try fileManager.removeItem(at: detailFileURL)
            }
            // #15：会议删了，搜索缓存同步清掉。
            searchTextCache[record.id] = nil
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

    func recordingURLs(for id: UUID) -> (mixed: URL, microphone: URL, system: URL, systemCompressed: URL) {
        let prefix = "meeting-\(id.uuidString)"
        return (
            recordingsURL.appendingPathComponent("\(prefix).m4a", isDirectory: false),
            recordingsURL.appendingPathComponent("\(prefix).mic.m4a", isDirectory: false),
            recordingsURL.appendingPathComponent("\(prefix).system.caf", isDirectory: false),
            recordingsURL.appendingPathComponent("\(prefix).system.m4a", isDirectory: false)
        )
    }

    func loadDetail(for id: UUID) -> MeetingRecordDetail? {
        lock.withLock {
            let url = detailFileURL(for: id)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(MeetingRecordDetail.self, from: data)
        }
    }

    func detailMatchesSearch(for id: UUID, query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return true }
        // #15：命中缓存直接比对，不再每次按键都读文件 + 全量 JSON 解码。
        let searchableText: [String]? = lock.withLock {
            if let cached = searchTextCache[id] {
                return cached
            }
            let url = detailFileURL(for: id)
            guard let data = try? Data(contentsOf: url),
                  let detail = try? JSONDecoder().decode(MeetingRecordDetail.self, from: data)
            else { return nil }
            let texts = Self.searchableTexts(for: detail)
            searchTextCache[id] = texts
            return texts
        }
        guard let searchableText else { return false }
        return searchableText.contains { $0.meetingSearchContains(normalizedQuery) }
    }

    /// 与 detailMatchesSearch 原来的拼接顺序完全一致，保证语义不变。
    private static func searchableTexts(for detail: MeetingRecordDetail) -> [String] {
        [detail.summary?.overview ?? ""]
            + (detail.summary?.keyPoints ?? [])
            + (detail.summary?.decisions ?? [])
            + (detail.summary?.actionItems.map(\.task) ?? [])
            + (detail.summary?.openQuestions ?? [])
            + detail.transcript.map(\.text)
    }

    func recordingsUsageBytes() -> Int64 {
        lock.withLock {
            let urls = (try? fileManager.contentsOfDirectory(
                at: recordingsURL,
                includingPropertiesForKeys: [.fileSizeKey]
            )) ?? []
            return urls.reduce(into: Int64(0)) { total, url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                total += size
            }
        }
    }

    static let recordingsWarningBytes: Int64 = 2 * 1024 * 1024 * 1024

    private func loadUnlocked() -> MeetingRepositoryLoadResult {
        let splitRecords = loadRecordFiles()
        if !splitRecords.records.isEmpty || splitRecords.foundRecordFiles {
            if splitRecords.foundRecordFiles {
                replaceLegacyIndexIfNeeded()
            }
            return MeetingRepositoryLoadResult(
                records: splitRecords.records.sorted { $0.createdAt > $1.createdAt },
                errorMessage: splitRecords.errorMessage,
                isReadOnly: false
            )
        }

        guard fileManager.fileExists(atPath: indexURL.path) else {
            return MeetingRepositoryLoadResult(records: [], errorMessage: nil, isReadOnly: false)
        }
        guard let data = try? Data(contentsOf: indexURL), !data.isEmpty else {
            return MeetingRepositoryLoadResult(records: [], errorMessage: nil, isReadOnly: false)
        }

        if let envelope = try? JSONDecoder().decode(MeetingIndexEnvelope.self, from: data),
           envelope.format == MeetingIndexEnvelope.recordFilesFormat
        {
            return MeetingRepositoryLoadResult(records: [], errorMessage: nil, isReadOnly: false)
        }

        do {
            let legacyRecords = try JSONDecoder().decode([MeetingRecord].self, from: data)
            migrateLegacyRecords(legacyRecords)
            return MeetingRepositoryLoadResult(
                records: legacyRecords.sorted { $0.createdAt > $1.createdAt },
                errorMessage: nil,
                isReadOnly: false
            )
        } catch {
            writesDisabled = true
            JarvisLog.error(
                category: .storage,
                event: "meeting.index.decode.failed",
                error: error
            )
            return MeetingRepositoryLoadResult(
                records: [],
                errorMessage: "会议索引已损坏，已停止写入以免覆盖已有记录",
                isReadOnly: true
            )
        }
    }

    private func loadRecordFiles() -> (records: [MeetingRecord], foundRecordFiles: Bool, errorMessage: String?) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: recordsURL,
            includingPropertiesForKeys: nil
        ) else {
            return ([], false, nil)
        }

        let files = contents.filter {
            $0.pathExtension == "json" && !$0.lastPathComponent.hasSuffix(".detail.json")
        }
        guard !files.isEmpty else {
            return ([], false, nil)
        }

        var records: [MeetingRecord] = []
        var failedCount = 0
        for fileURL in files {
            do {
                let data = try Data(contentsOf: fileURL)
                var record = try JSONDecoder().decode(MeetingRecord.self, from: data)
                if !record.detail.isEmpty {
                    try writeDetailFile(record.detail, for: record.id)
                    try writeRecordFile(record.metadataCopy)
                    record = record.metadataCopy
                }
                records.append(record)
            } catch {
                failedCount += 1
                JarvisLog.error(
                    category: .storage,
                    event: "meeting.record.decode.failed",
                    error: error,
                    fields: ["file": fileURL.lastPathComponent]
                )
            }
        }

        let errorMessage: String? = if failedCount > 0 {
            "有 \(failedCount) 条会议记录文件损坏，已跳过这些记录"
        } else {
            nil
        }
        return (records, true, errorMessage)
    }

    private func migrateLegacyRecords(_ records: [MeetingRecord]) {
        for record in records {
            do {
                try writeRecordFile(record)
                try writeDetailFile(record.detail, for: record.id)
            } catch {
                JarvisLog.error(
                    category: .storage,
                    event: "meeting.record.migrate.failed",
                    error: error,
                    fields: ["meetingID": record.id.uuidString]
                )
            }
        }
        replaceLegacyIndexIfNeeded()
    }

    private func replaceLegacyIndexIfNeeded() {
        let envelope = MeetingIndexEnvelope(format: MeetingIndexEnvelope.recordFilesFormat, version: 1)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        do {
            try JarvisProtectedStorage.write(data, to: indexURL)
        } catch {
            // #16：以前 try? 静默吞掉。索引替换失败意味着旧索引还在，
            // 下次启动会重复走迁移分支——记下来，方便排查。
            JarvisLog.error(
                category: .storage,
                event: "meeting.index.replace.failed",
                error: error
            )
        }
    }

    private func writeRecordFile(_ record: MeetingRecord) throws {
        let data = try JSONEncoder().encode(record.metadataCopy)
        try JarvisProtectedStorage.write(data, to: recordFileURL(for: record.id))
    }

    private func writeDetailFile(_ detail: MeetingRecordDetail, for id: UUID) throws {
        let data = try JSONEncoder().encode(detail)
        try JarvisProtectedStorage.write(data, to: detailFileURL(for: id))
        // #15：详情变了，搜索缓存失效（调用方持有 lock）。
        searchTextCache[id] = nil
    }

    private func recordFileURL(for id: UUID) -> URL {
        recordsURL.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    private func detailFileURL(for id: UUID) -> URL {
        recordsURL.appendingPathComponent("\(id.uuidString).detail.json", isDirectory: false)
    }

    private func isSafeAudioFileName(_ fileName: String) -> Bool {
        let prefix = "meeting-"
        guard fileName.hasPrefix(prefix) else { return false }
        let suffixes = [".mic.m4a", ".system.caf", ".system.m4a", ".m4a"]
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
        let generated = recordingURLs(for: record.id)
        urls.append(contentsOf: [generated.system, generated.systemCompressed])
        return Array(Set(urls))
    }
}

private struct MeetingIndexEnvelope: Codable {
    static let recordFilesFormat = "record-files"

    var format: String
    var version: Int
}

enum MeetingRepositoryError: LocalizedError, Equatable {
    case invalidAudioFileName
    case writesDisabled

    var errorDescription: String? {
        switch self {
        case .invalidAudioFileName: "会议录音文件名无效"
        case .writesDisabled: "会议存储已损坏，已停止写入以免覆盖已有记录"
        }
    }
}
