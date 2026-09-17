import CryptoKit
import Foundation

/// RSS 的落盘层。
///
/// 订阅列表、分组、每个 feed 的条目索引各是一份 `JarvisJSONFile`；正文单独放在
/// `content/` 下按需缓存，因为正文体积远大于索引，而且它才是需要按上限淘汰的部分。
final class RSSFeedStore: @unchecked Sendable {
    /// 每个 feed 保留的条目上限。
    static let maximumItemsPerFeed = 500
    /// 条目的最长保留时间（星标不受这两条限制）。
    static let maximumItemAge: TimeInterval = 90 * 24 * 60 * 60

    let directoryURL: URL
    private let feedsFile: JarvisJSONFile<[RSSFeed]>
    private let groupsFile: JarvisJSONFile<[RSSGroup]>
    private let fileManager: FileManager

    init(
        directoryURL: URL = JarvisAppDirectory.url("RSS"),
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        feedsFile = JarvisJSONFile(
            directoryURL: directoryURL,
            fileName: "feeds.json",
            logDomain: "rss.feeds",
            fileManager: fileManager
        )
        groupsFile = JarvisJSONFile(
            directoryURL: directoryURL,
            fileName: "groups.json",
            logDomain: "rss.groups",
            fileManager: fileManager
        )
        JarvisProtectedStorage.prepareDirectory(contentDirectory(fileManager: fileManager), fileManager: fileManager)
    }

    // MARK: - 订阅列表

    func loadFeeds() -> [RSSFeed] {
        feedsFile.readOrDefault([])
    }

    func loadGroups() -> [RSSGroup] {
        groupsFile.readOrDefault([]).sorted { $0.order < $1.order }
    }

    func saveFeeds(_ feeds: [RSSFeed]) throws {
        try feedsFile.writeOrThrow(feeds)
    }

    func saveGroups(_ groups: [RSSGroup]) throws {
        try groupsFile.writeOrThrow(groups)
    }

    // MARK: - 条目

    func loadItems(feedID: UUID) -> [RSSItem] {
        itemsFile(for: feedID).readOrDefault([]).sorted { $0.sortDate > $1.sortDate }
    }

    func saveItems(_ items: [RSSItem], feedID: UUID) throws {
        try itemsFile(for: feedID).writeOrThrow(items)
    }

    func deleteItems(feedID: UUID) {
        let url = directoryURL.appendingPathComponent("items-\(feedID.uuidString).json")
        try? fileManager.removeItem(at: url)
    }

    // MARK: - 正文缓存

    func writeContent(_ html: String, itemID: String) throws {
        let url = contentFileURL(itemID: itemID)
        try JarvisProtectedStorage.write(Data(html.utf8), to: url)
    }

    func loadContent(itemID: String) -> String? {
        let url = contentFileURL(itemID: itemID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteContent(itemIDs: [String]) {
        for itemID in itemIDs {
            try? fileManager.removeItem(at: contentFileURL(itemID: itemID))
        }
    }

    /// 正文文件名用条目 ID 的哈希——条目 ID 里带着 URL，直接当文件名既要处理路径
    /// 穿越又要处理超长，哈希一次就都不用了。
    func contentFileURL(itemID: String) -> URL {
        let digest = SHA256.hash(data: Data(itemID.utf8))
        let name = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return contentDirectory(fileManager: fileManager)
            .appendingPathComponent("\(name).html", isDirectory: false)
    }

    private func contentDirectory(fileManager _: FileManager) -> URL {
        directoryURL.appendingPathComponent("content", isDirectory: true)
    }

    private func itemsFile(for feedID: UUID) -> JarvisJSONFile<[RSSItem]> {
        JarvisJSONFile(
            directoryURL: directoryURL,
            fileName: "items-\(feedID.uuidString).json",
            logDomain: "rss.items",
            fileManager: fileManager
        )
    }
}

/// 新抓取的条目与已有条目的合并。
///
/// 这是整个模块最容易出错的地方：刷新一次就把已读状态清空、或者把星标条目裁掉，
/// 用户第二天就会弃用。规则固定为——已读/星标/入库时间以本地为准，其余字段以远端
/// 为准；星标永不淘汰。
enum RSSItemMerge {
    struct Result: Equatable {
        var items: [RSSItem]
        /// 被裁掉的条目 ID，调用方据此删除对应的正文缓存。
        var removedIDs: [String]
        var insertedIDs: [String]
    }

    static func merge(
        existing: [RSSItem],
        incoming: [RSSItem],
        maximumItems: Int = RSSFeedStore.maximumItemsPerFeed,
        maximumAge: TimeInterval = RSSFeedStore.maximumItemAge,
        now: Date = Date()
    ) -> Result {
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var insertedIDs: [String] = []

        for item in incoming {
            if let previous = byID[item.id] {
                var merged = item
                merged.isRead = previous.isRead
                merged.isStarred = previous.isStarred
                merged.capturedAt = previous.capturedAt
                merged.hasCachedContent = previous.hasCachedContent
                byID[item.id] = merged
            } else {
                byID[item.id] = item
                insertedIDs.append(item.id)
            }
        }

        let ordered = byID.values.sorted { $0.sortDate > $1.sortDate }
        var kept: [RSSItem] = []
        var removedIDs: [String] = []
        let cutoff = now.addingTimeInterval(-maximumAge)

        for item in ordered {
            let overCount = kept.count >= maximumItems
            let tooOld = item.sortDate < cutoff
            if item.isStarred || (!overCount && !tooOld) {
                kept.append(item)
            } else {
                removedIDs.append(item.id)
            }
        }

        return Result(items: kept, removedIDs: removedIDs, insertedIDs: insertedIDs)
    }

    /// 把新条目转成待入库的模型。
    static func makeItems(
        from entries: [RSSParsedEntry],
        feedID: UUID,
        now: Date = Date()
    ) -> [RSSItem] {
        entries.map { entry in
            RSSItem(
                id: RSSItemIdentity.deduplicationKey(
                    guid: entry.guid,
                    link: entry.link,
                    title: entry.title,
                    publishedAt: entry.publishedAt
                ),
                feedID: feedID,
                title: entry.title,
                link: entry.link,
                author: entry.author,
                publishedAt: entry.publishedAt,
                summaryHTML: entry.summaryHTML,
                enclosureURL: entry.enclosureURL,
                hasCachedContent: false,
                isRead: false,
                isStarred: false,
                capturedAt: now
            )
        }
    }
}
