import Foundation

struct EntertainmentVideoDownloadRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let platform: EntertainmentPlatform
    let title: String
    let qualityTitle: String
    let filename: String
    let sourceURL: URL
    let destinationPath: String
    let createdAt: Date
    var finishedAt: Date
    var state: AIConversationDownloadState
    var errorMessage: String?

    var destinationURL: URL {
        URL(fileURLWithPath: destinationPath)
    }

    var fileExists: Bool {
        FileManager.default.fileExists(atPath: destinationPath)
    }

    var canOpenFile: Bool {
        state == .completed && fileExists
    }

    init(
        id: UUID,
        platform: EntertainmentPlatform,
        title: String,
        qualityTitle: String,
        filename: String,
        sourceURL: URL,
        destinationPath: String,
        createdAt: Date,
        finishedAt: Date,
        state: AIConversationDownloadState,
        errorMessage: String?
    ) {
        self.id = id
        self.platform = platform
        self.title = title
        self.qualityTitle = qualityTitle
        self.filename = filename
        self.sourceURL = sourceURL
        self.destinationPath = destinationPath
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.state = state
        self.errorMessage = errorMessage
    }

    init(item: EntertainmentVideoDownloadItem, finishedAt: Date = Date()) {
        self.init(
            id: item.id,
            platform: item.platform,
            title: item.title,
            qualityTitle: item.qualityTitle,
            filename: item.filename,
            sourceURL: item.sourceURL,
            destinationPath: item.destinationURL?.path ?? "",
            createdAt: item.createdAt,
            finishedAt: finishedAt,
            state: item.state,
            errorMessage: item.errorMessage
        )
    }
}

enum EntertainmentVideoDownloadHistory {
    static let maxCount = 100

    static func recording(
        _ record: EntertainmentVideoDownloadRecord,
        into history: [EntertainmentVideoDownloadRecord]
    ) -> [EntertainmentVideoDownloadRecord] {
        var next = history.filter { $0.id != record.id }
        next.insert(record, at: 0)
        return Array(next.prefix(maxCount))
    }

    static func removing(
        _ id: UUID,
        from history: [EntertainmentVideoDownloadRecord]
    ) -> [EntertainmentVideoDownloadRecord] {
        history.filter { $0.id != id }
    }

    static func timestamp(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }
}

final class EntertainmentVideoDownloadHistoryStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let metadataURL: URL
    private let lock = NSLock()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let supportDirectory = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        let directory = supportDirectory
            .appendingPathComponent(JarvisAppIdentity.dataDirectoryName, isDirectory: true)
            .appendingPathComponent("EntertainmentDownloads", isDirectory: true)
        directoryURL = directory
        metadataURL = directory.appendingPathComponent("history.json")
        JarvisProtectedStorage.prepareDirectory(directory, fileManager: fileManager)
    }

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
        metadataURL = directoryURL.appendingPathComponent("history.json")
        JarvisProtectedStorage.prepareDirectory(directoryURL, fileManager: fileManager)
    }

    func load() -> [EntertainmentVideoDownloadRecord] {
        lock.withLock {
            guard fileManager.fileExists(atPath: metadataURL.path) else { return [] }
            do {
                let data = try Data(contentsOf: metadataURL)
                return try JSONDecoder().decode([EntertainmentVideoDownloadRecord].self, from: data)
            } catch {
                JarvisLog.error(
                    category: .storage,
                    event: "entertainment.download.history.load.failed",
                    error: error
                )
                return []
            }
        }
    }

    func save(_ history: [EntertainmentVideoDownloadRecord]) {
        lock.withLock {
            do {
                let data = try JSONEncoder().encode(history)
                try JarvisProtectedStorage.write(data, to: metadataURL)
            } catch {
                JarvisLog.error(
                    category: .storage,
                    event: "entertainment.download.history.save.failed",
                    error: error
                )
            }
        }
    }
}
