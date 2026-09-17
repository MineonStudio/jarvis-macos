import Foundation

struct RSSGroup: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var order: Int

    init(id: UUID = UUID(), title: String, order: Int) {
        self.id = id
        self.title = title
        self.order = order
    }
}

struct RSSFeed: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var feedURL: URL
    var siteURL: URL?
    var groupID: UUID?
    var iconURL: URL?
    var isEnabled: Bool
    var lastFetchedAt: Date?
    var lastSuccessAt: Date?
    /// 条件请求的凭据：命中 304 时整段抓取只剩一次往返，不解析也不落盘。
    var etag: String?
    var lastModified: String?
    var failureCount: Int
    var lastErrorMessage: String?
    /// 由 `RSSFeedStore` 在写入条目时维护，免得菜单栏角标要读遍所有条目文件。
    var unreadCount: Int
    var itemCount: Int

    init(
        id: UUID = UUID(),
        title: String,
        feedURL: URL,
        siteURL: URL? = nil,
        groupID: UUID? = nil,
        iconURL: URL? = nil,
        isEnabled: Bool = true,
        lastFetchedAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        etag: String? = nil,
        lastModified: String? = nil,
        failureCount: Int = 0,
        lastErrorMessage: String? = nil,
        unreadCount: Int = 0,
        itemCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.feedURL = feedURL
        self.siteURL = siteURL
        self.groupID = groupID
        self.iconURL = iconURL
        self.isEnabled = isEnabled
        self.lastFetchedAt = lastFetchedAt
        self.lastSuccessAt = lastSuccessAt
        self.etag = etag
        self.lastModified = lastModified
        self.failureCount = failureCount
        self.lastErrorMessage = lastErrorMessage
        self.unreadCount = unreadCount
        self.itemCount = itemCount
    }
}

struct RSSItem: Codable, Identifiable, Hashable, Sendable {
    /// 去重键：同一条目在每次抓取中都必须算出同一个值，见 `RSSItemIdentity`。
    let id: String
    let feedID: UUID
    var title: String
    var link: URL?
    var author: String?
    var publishedAt: Date?
    var summaryHTML: String
    var enclosureURL: URL?
    /// 正文是否已缓存到 `content/` 下。
    var hasCachedContent: Bool
    var isRead: Bool
    var isStarred: Bool
    var capturedAt: Date

    init(
        id: String,
        feedID: UUID,
        title: String,
        link: URL? = nil,
        author: String? = nil,
        publishedAt: Date? = nil,
        summaryHTML: String = "",
        enclosureURL: URL? = nil,
        hasCachedContent: Bool = false,
        isRead: Bool = false,
        isStarred: Bool = false,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.feedID = feedID
        self.title = title
        self.link = link
        self.author = author
        self.publishedAt = publishedAt
        self.summaryHTML = summaryHTML
        self.enclosureURL = enclosureURL
        self.hasCachedContent = hasCachedContent
        self.isRead = isRead
        self.isStarred = isStarred
        self.capturedAt = capturedAt
    }

    /// 列表排序用：没有发布时间的条目按入库时间排。
    var sortDate: Date {
        publishedAt ?? capturedAt
    }
}

enum RSSItemFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case unread
    case starred

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all: "全部"
        case .unread: "未读"
        case .starred: "星标"
        }
    }

    func matches(_ item: RSSItem) -> Bool {
        switch self {
        case .all: true
        case .unread: !item.isRead
        case .starred: item.isStarred
        }
    }
}

enum RSSFilterLogic {
    static func count(for filter: RSSItemFilter, in items: [RSSItem]) -> Int {
        items.count { filter.matches($0) }
    }
}

/// 条目身份与链接规范化。
///
/// 同一条目每次抓取必须落回同一个 `id`，否则每次刷新都会把全部文章再插一遍。
/// `guid` 优先，其次规范化链接，最后退回标题 + 时间的哈希。
enum RSSItemIdentity {
    static func deduplicationKey(
        guid: String?,
        link: URL?,
        title: String,
        publishedAt: Date?
    ) -> String {
        if let guid = normalizedGUID(guid) {
            return "guid:\(guid)"
        }
        if let link, let canonical = canonicalLink(link) {
            return "link:\(canonical)"
        }
        let stamp = publishedAt.map { String(Int($0.timeIntervalSince1970)) } ?? ""
        return "title:\(stableHash("\(title)|\(stamp)"))"
    }

    private static func normalizedGUID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // 有些 feed 把链接当 guid 用，这种也走链接规范化，否则同一篇文章会因为
        // 尾部的 utm 参数在两种形态间反复横跳。
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https"
        {
            return canonicalLink(url) ?? trimmed
        }
        return trimmed
    }

    /// 去掉跟踪参数、片段和尾斜杠，scheme 与 host 统一小写。
    static func canonicalLink(_ url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let scheme = components.scheme?.lowercased()
        guard scheme == "http" || scheme == "https", let host = components.host?.lowercased() else {
            return nil
        }
        components.scheme = scheme
        components.host = host
        components.fragment = nil
        components.user = nil
        components.password = nil
        let filtered = components.queryItems?.filter { item in
            let name = item.name.lowercased()
            return !name.hasPrefix("utm_")
                && name != "fbclid"
                && name != "gclid"
                && name != "spm"
                && name != "ref_src"
        }
        components.queryItems = (filtered?.isEmpty ?? true) ? nil : filtered

        var path = components.percentEncodedPath
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        components.percentEncodedPath = path
        return components.url?.absoluteString
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}

/// 抓取失败后的退避：坏 feed 不能每轮都重试一次。
enum RSSRefreshBackoff {
    static let maximumDelay: TimeInterval = 8 * 60 * 60

    static func delay(failureCount: Int, baseInterval: TimeInterval) -> TimeInterval {
        guard failureCount > 0 else { return baseInterval }
        let exponent = min(failureCount, 8)
        let delay = baseInterval * pow(2, Double(exponent))
        return min(delay, maximumDelay)
    }

    /// 该 feed 现在是否可以抓取。停用的、还在退避窗口里的一律跳过。
    static func isDue(
        feed: RSSFeed,
        now: Date,
        baseInterval: TimeInterval
    ) -> Bool {
        guard feed.isEnabled else { return false }
        let lastAttempt = max(feed.lastFetchedAt ?? .distantPast, feed.lastSuccessAt ?? .distantPast)
        guard lastAttempt > .distantPast else { return true }
        let elapsed = now.timeIntervalSince(lastAttempt)
        return elapsed >= delay(failureCount: feed.failureCount, baseInterval: baseInterval)
    }
}
