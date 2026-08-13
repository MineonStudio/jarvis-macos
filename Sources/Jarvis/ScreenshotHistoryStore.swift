import Foundation

struct ScreenshotHistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    let fileName: String
}

/// Stores screenshot history as PNG files plus a small JSON index. Keeping the
/// image data out of UserDefaults makes history durable without making the
/// app's preferences file grow with every screenshot.
final class ScreenshotHistoryStore {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let metadataURL: URL
    private let maximumCount = 100

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let supportDirectory = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        let directory = supportDirectory
            .appendingPathComponent("Jarvis", isDirectory: true)
            .appendingPathComponent("ScreenshotHistory", isDirectory: true)
        self.directoryURL = directory
        self.metadataURL = directory.appendingPathComponent("metadata.json")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
        self.metadataURL = directoryURL.appendingPathComponent("metadata.json")
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func load() -> [ScreenshotHistoryItem] {
        guard let data = try? Data(contentsOf: metadataURL),
              let items = try? JSONDecoder().decode([ScreenshotHistoryItem].self, from: data) else {
            return []
        }
        return items
            .filter { fileManager.fileExists(atPath: directoryURL.appendingPathComponent($0.fileName).path) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func data(for item: ScreenshotHistoryItem) -> Data? {
        try? Data(contentsOf: directoryURL.appendingPathComponent(item.fileName))
    }

    @discardableResult
    func add(data: Data, date: Date = Date()) -> ScreenshotHistoryItem? {
        guard !data.isEmpty else { return nil }
        let id = UUID()
        let item = ScreenshotHistoryItem(
            id: id,
            createdAt: date,
            updatedAt: date,
            fileName: "screenshot-\(id.uuidString).png"
        )
        guard write(data, for: item) else { return nil }

        var items = load()
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        save(trimmed(items))
        return item
    }

    @discardableResult
    func update(_ item: ScreenshotHistoryItem, data: Data, date: Date = Date()) -> ScreenshotHistoryItem? {
        guard !data.isEmpty else { return nil }
        var items = load()
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        guard write(data, for: item) else { return nil }

        var updated = items[index]
        updated.updatedAt = date
        items[index] = updated
        save(items.sorted { $0.updatedAt > $1.updatedAt })
        return updated
    }

    func delete(_ item: ScreenshotHistoryItem) {
        try? fileManager.removeItem(at: directoryURL.appendingPathComponent(item.fileName))
        var items = load()
        items.removeAll { $0.id == item.id }
        save(items)
    }

    private func write(_ data: Data, for item: ScreenshotHistoryItem) -> Bool {
        do {
            try data.write(
                to: directoryURL.appendingPathComponent(item.fileName),
                options: .atomic
            )
            return true
        } catch {
            return false
        }
    }

    private func save(_ items: [ScreenshotHistoryItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    private func trimmed(_ items: [ScreenshotHistoryItem]) -> [ScreenshotHistoryItem] {
        let sorted = items.sorted { $0.updatedAt > $1.updatedAt }
        guard sorted.count > maximumCount else { return sorted }

        let kept = Array(sorted.prefix(maximumCount))
        let keptIDs = Set(kept.map(\.id))
        for removed in sorted where !keptIDs.contains(removed.id) {
            try? fileManager.removeItem(at: directoryURL.appendingPathComponent(removed.fileName))
        }
        return kept
    }
}
