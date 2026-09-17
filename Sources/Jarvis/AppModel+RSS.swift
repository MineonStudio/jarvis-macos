import AppKit
import Foundation
import UserNotifications

extension AppModel {
    /// 一次刷新的结果，供通知与状态栏使用。
    struct RSSRefreshOutcome {
        var newItems: [RSSItem] = []
        var failures: [UUID: String] = [:]

        var didChangeAnything: Bool {
            !newItems.isEmpty
        }
    }

    enum RSSSubscribeError: LocalizedError {
        case invalidInput
        case alreadySubscribed
        case noFeedFound
        case unreachable(String)

        var errorDescription: String? {
            switch self {
            case .invalidInput: "请输入订阅源地址或网站地址"
            case .alreadySubscribed: "这个订阅源已经在列表里了"
            case .noFeedFound: "没有在页面里找到 RSS/Atom 订阅源"
            case let .unreachable(message): message
            }
        }
    }

    // MARK: - 启动与生命周期

    /// 启动时把订阅列表和条目读进内存。整批读盘在后台线程做，主线程只接收结果。
    func loadRSSState() async {
        let store = rssStore
        let snapshot = await Task.detached(priority: .utility) { () -> RSSSnapshot in
            let feeds = store.loadFeeds()
            var items: [UUID: [RSSItem]] = [:]
            for feed in feeds {
                items[feed.id] = store.loadItems(feedID: feed.id)
            }
            return RSSSnapshot(feeds: feeds, groups: store.loadGroups(), itemsByFeed: items)
        }.value

        rssFeeds = snapshot.feeds.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        rssGroups = snapshot.groups
        rssItemsByFeed = snapshot.itemsByFeed
        if rssSelectedFeedID == nil {
            rssSelectedItemID = rssFilteredRSSItems().first?.id
        }
        JarvisLog.info(
            category: .storage,
            event: "rss.state.loaded",
            result: "success",
            fields: [
                "feedCount": String(rssFeeds.count),
                "itemCount": String(rssItemsByFeed.values.reduce(0) { $0 + $1.count })
            ]
        )
    }

    func startRSSServices() {
        rssRefreshInterval = loadRSSRefreshInterval()
        rssNotificationsEnabled = loadRSSNotificationsEnabled()
        UNUserNotificationCenter.current().delegate = rssNotificationDelegate
        rssNotificationDelegate.onOpenItem = { [weak self] itemID in
            guard let self else { return }
            selectedSection = .skill(.rss)
            rssSelectedFeedID = rssFeeds.first { feed in
                (rssItemsByFeed[feed.id] ?? []).contains { $0.id == itemID }
            }?.id
            rssSelectedItemID = itemID
            markRSSItemRead(itemID: itemID, isRead: true)
        }
        startRSSRefreshScheduler()
    }

    func stopRSSServices() {
        rssScheduler.stop()
    }

    private func startRSSRefreshScheduler() {
        rssScheduler.start(interval: rssRefreshInterval) { [weak self] in
            await self?.refreshAllRSSFeeds(manual: false)
        }
    }

    // MARK: - 订阅管理

    /// 输入可以是订阅源地址，也可以是网站首页——后者会先去页面里找订阅源。
    @discardableResult
    func subscribeRSSFeed(fromInput input: String) async -> Result<RSSFeed, RSSSubscribeError> {
        guard let url = Self.normalizedRSSInput(input) else {
            return .failure(.invalidInput)
        }
        if rssFeeds.contains(where: { RSSItemIdentity.canonicalLink($0.feedURL) == RSSItemIdentity.canonicalLink(url) }) {
            return .failure(.alreadySubscribed)
        }

        let candidates = await discoverRSSFeedCandidates(startingAt: url)
        guard !candidates.isEmpty else {
            return .failure(.noFeedFound)
        }

        var lastError: String?
        for candidate in candidates {
            do {
                let parsed = try await fetchAndParseRSSFeed(candidate)
                let parsedTitle = parsed.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let feed = RSSFeed(
                    title: parsedTitle.isEmpty ? (candidate.host ?? candidate.absoluteString) : parsedTitle,
                    feedURL: candidate,
                    siteURL: parsed.siteURL,
                    iconURL: parsed.iconURL
                )
                rssFeeds.append(feed)
                rssFeeds.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                persistRSSFeedList()
                JarvisLog.notice(
                    category: .network,
                    event: "rss.feed.subscribed",
                    result: "success",
                    fields: ["feedCount": String(rssFeeds.count)]
                )
                if rssNotificationsEnabled {
                    await rssNotifications.requestAuthorizationIfNeeded()
                }
                // 订阅完立刻拉一次，用户马上能看到内容。
                await refreshRSSFeed(feed)
                return .success(feed)
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }
        return .failure(.unreachable(lastError ?? "订阅源无法访问"))
    }

    func removeRSSFeed(_ feed: RSSFeed) {
        rssFeeds.removeAll { $0.id == feed.id }
        let removedIDs = (rssItemsByFeed[feed.id] ?? []).map(\.id)
        rssItemsByFeed[feed.id] = nil
        rssStore.deleteItems(feedID: feed.id)
        rssStore.deleteContent(itemIDs: removedIDs)
        if rssSelectedFeedID == feed.id {
            rssSelectedFeedID = nil
        }
        if let selectedItemID = rssSelectedItemID,
           removedIDs.contains(selectedItemID)
        {
            rssSelectedItemID = rssFilteredRSSItems().first?.id
        }
        persistRSSFeedList()
    }

    func setRSSFeedEnabled(_ feed: RSSFeed, isEnabled: Bool) {
        updateRSSFeed(feed.id) { $0.isEnabled = isEnabled }
    }

    func renameRSSFeed(_ feed: RSSFeed, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateRSSFeed(feed.id) { $0.title = trimmed }
    }

    func moveRSSFeed(_ feed: RSSFeed, toGroup groupID: UUID?) {
        updateRSSFeed(feed.id) { $0.groupID = groupID }
    }

    func addRSSGroup(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        rssGroups.append(RSSGroup(title: trimmed, order: rssGroups.count))
        persistRSSFeedList()
    }

    func importRSSOPML(from url: URL) async {
        do {
            let data = try Data(contentsOf: url)
            let result = try RSSOPML.importFeeds(from: data)
            var groupIDsByTitle: [String: UUID] = [:]
            var added = 0
            for imported in result.feeds {
                if rssFeeds.contains(where: {
                    RSSItemIdentity.canonicalLink($0.feedURL) == RSSItemIdentity.canonicalLink(imported.feedURL)
                }) {
                    continue
                }
                var groupID: UUID?
                if let groupTitle = imported.groupTitle {
                    if let existing = groupIDsByTitle[groupTitle] {
                        groupID = existing
                    } else {
                        let group = RSSGroup(title: groupTitle, order: rssGroups.count)
                        rssGroups.append(group)
                        groupIDsByTitle[groupTitle] = group.id
                        groupID = group.id
                    }
                }
                rssFeeds.append(
                    RSSFeed(
                        title: imported.title ?? imported.feedURL.host ?? imported.feedURL.absoluteString,
                        feedURL: imported.feedURL,
                        siteURL: imported.siteURL,
                        groupID: groupID
                    )
                )
                added += 1
            }
            rssFeeds.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            persistRSSFeedList()
            JarvisLog.notice(
                category: .storage,
                event: "rss.opml.imported",
                result: "success",
                fields: [
                    "added": String(added),
                    "duplicates": String(result.duplicateCount)
                ]
            )
            if added > 0, rssNotificationsEnabled {
                await rssNotifications.requestAuthorizationIfNeeded()
                await refreshAllRSSFeeds(manual: true)
            }
        } catch {
            rssStorageError = "OPML 导入失败：\(error.localizedDescription)"
            JarvisLog.error(category: .storage, event: "rss.opml.importFailed", error: error)
        }
    }

    func exportRSSOPML(to url: URL) {
        let document = RSSOPML.export(feeds: rssFeeds, groups: rssGroups)
        do {
            try JarvisProtectedStorage.write(Data(document.utf8), to: url)
            JarvisLog.notice(category: .storage, event: "rss.opml.exported", result: "success")
        } catch {
            rssStorageError = "OPML 导出失败：\(error.localizedDescription)"
            JarvisLog.error(category: .storage, event: "rss.opml.exportFailed", error: error)
        }
    }

    // MARK: - 抓取

    func refreshAllRSSFeeds(manual: Bool) async {
        guard !rssIsRefreshing else { return }
        rssIsRefreshing = true
        defer { rssIsRefreshing = false }

        let startedAt = Date()
        let now = Date()
        let baseInterval = rssRefreshInterval.seconds ?? 30 * 60
        let due = rssFeeds.filter { feed in
            manual || RSSRefreshBackoff.isDue(feed: feed, now: now, baseInterval: baseInterval)
        }

        var outcome = RSSRefreshOutcome()
        for feed in due {
            let result = await refreshRSSFeed(feed, collectNewItems: true)
            outcome.newItems.append(contentsOf: result.newItems)
            if let error = result.failures[feed.id] {
                outcome.failures[feed.id] = error
            }
        }

        rssLastRefreshAt = Date()
        if !outcome.newItems.isEmpty, rssNotificationsEnabled {
            rssNotifications.post(newItems: outcome.newItems, feedTitles: rssFeedTitles)
        }
        JarvisLog.info(
            category: .network,
            event: "rss.refresh.completed",
            durationMilliseconds: Date().timeIntervalSince(startedAt) * 1000,
            result: outcome.failures.isEmpty ? "success" : "partial",
            fields: [
                "refreshed": String(due.count),
                "newItems": String(outcome.newItems.count),
                "failures": String(outcome.failures.count)
            ]
        )
    }

    /// 抓单个订阅源。`notModified` 时只更新条件请求凭据，不解析也不落盘。
    @discardableResult
    func refreshRSSFeed(_ feed: RSSFeed, collectNewItems: Bool = true) async -> RSSRefreshOutcome {
        guard let index = rssFeeds.firstIndex(where: { $0.id == feed.id }) else {
            return RSSRefreshOutcome()
        }
        var current = rssFeeds[index]
        var outcome = RSSRefreshOutcome()

        do {
            let response = try await rssClient.fetch(
                RSSFetchRequest(
                    url: current.feedURL,
                    etag: current.etag,
                    lastModified: current.lastModified
                )
            )
            current.lastFetchedAt = Date()
            current.failureCount = 0
            current.lastErrorMessage = nil

            if response.notModified {
                current.lastSuccessAt = Date()
                current.etag = response.etag
                current.lastModified = response.lastModified
                rssFeeds[index] = current
                persistRSSFeedList()
                return outcome
            }

            let parsed = try RSSFeedParser.parse(response.data, baseURL: current.feedURL)
            if let title = parsed.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                current.title = title
            }
            if let siteURL = parsed.siteURL {
                current.siteURL = siteURL
            }
            if let iconURL = parsed.iconURL {
                current.iconURL = iconURL
            }
            current.etag = response.etag
            current.lastModified = response.lastModified
            current.lastSuccessAt = Date()

            let incoming = RSSItemMerge.makeItems(from: parsed.entries, feedID: current.id)
            let merge = RSSItemMerge.merge(
                existing: rssItemsByFeed[current.id] ?? [],
                incoming: incoming
            )
            cacheRSSContent(for: parsed.entries, itemIDs: Set(merge.insertedIDs), feedID: current.id)
            rssStore.deleteContent(itemIDs: merge.removedIDs)
            rssItemsByFeed[current.id] = merge.items
            current.itemCount = merge.items.count
            current.unreadCount = merge.items.count { !$0.isRead }
            rssFeeds[index] = current
            try? rssStore.saveItems(merge.items, feedID: current.id)
            persistRSSFeedList()

            if collectNewItems {
                let newIDs = Set(merge.insertedIDs)
                outcome.newItems = merge.items.filter { newIDs.contains($0.id) }
            }
        } catch {
            current.lastFetchedAt = Date()
            current.failureCount += 1
            current.lastErrorMessage = error.localizedDescription
            rssFeeds[index] = current
            persistRSSFeedList()
            outcome.failures[current.id] = error.localizedDescription
            JarvisLog.error(
                category: .network,
                event: "rss.feed.refreshFailed",
                error: error,
                fields: [
                    "failureCount": String(current.failureCount),
                    "host": current.feedURL.host ?? ""
                ]
            )
        }
        return outcome
    }

    // MARK: - 条目操作

    func markRSSItemRead(itemID: String, isRead: Bool) {
        guard let feedID = rssItemsByFeed.first(where: { $0.value.contains { $0.id == itemID } })?.key,
              var items = rssItemsByFeed[feedID],
              let index = items.firstIndex(where: { $0.id == itemID })
        else {
            return
        }
        guard items[index].isRead != isRead else { return }
        items[index].isRead = isRead
        persistRSSItems(items, feedID: feedID)
    }

    func toggleRSSStar(itemID: String) {
        guard let feedID = rssItemsByFeed.first(where: { $0.value.contains { $0.id == itemID } })?.key,
              var items = rssItemsByFeed[feedID],
              let index = items.firstIndex(where: { $0.id == itemID })
        else {
            return
        }
        items[index].isStarred.toggle()
        persistRSSItems(items, feedID: feedID)
    }

    func markAllRSSTemsRead(feedID: UUID?) {
        let targets = feedID.map { [$0] } ?? Array(rssItemsByFeed.keys)
        for target in targets {
            guard var items = rssItemsByFeed[target] else { continue }
            var changed = false
            for index in items.indices where !items[index].isRead {
                items[index].isRead = true
                changed = true
            }
            guard changed else { continue }
            persistRSSItems(items, feedID: target)
        }
    }

    /// 打开文章时优先给缓存的全文，没有全文就退回摘要。
    func rssArticleHTML(for item: RSSItem) -> String {
        if item.hasCachedContent, let cached = rssStore.loadContent(itemID: item.id) {
            return cached
        }
        return item.summaryHTML
    }

    // MARK: - 列表

    var rssFeedTitles: [UUID: String] {
        Dictionary(uniqueKeysWithValues: rssFeeds.map { ($0.id, $0.title) })
    }

    var rssUnreadTotal: Int {
        rssItemsByFeed.values.reduce(0) { total, items in
            total + items.count { !$0.isRead }
        }
    }

    func rssItems(forFeedID feedID: UUID?) -> [RSSItem] {
        if let feedID {
            return rssItemsByFeed[feedID] ?? []
        }
        return rssItemsByFeed.values.flatMap { $0 }.sorted { $0.sortDate > $1.sortDate }
    }

    func rssFilteredRSSItems() -> [RSSItem] {
        let query = rssSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return rssItems(forFeedID: rssSelectedFeedID).filter { item in
            guard rssFilter.matches(item) else { return false }
            guard !query.isEmpty else { return true }
            if item.title.localizedCaseInsensitiveContains(query) {
                return true
            }
            return RSSArticleRenderer.plainText(fromHTML: item.summaryHTML)
                .localizedCaseInsensitiveContains(query)
        }
    }

    func rssSelectedItem() -> RSSItem? {
        guard let itemID = rssSelectedItemID else { return nil }
        return rssItemsByFeed.values
            .first { $0.contains { $0.id == itemID } }?
            .first { $0.id == itemID }
    }

    func selectRSSItem(_ item: RSSItem) {
        rssSelectedItemID = item.id
    }

    // MARK: - 设置

    func updateRSSRefreshInterval(_ interval: RSSRefreshScheduler.Interval) {
        rssRefreshInterval = interval
        UserDefaults.standard.set(interval.rawValue, forKey: rssRefreshIntervalKey)
        startRSSRefreshScheduler()
    }

    func updateRSSNotificationsEnabled(_ isEnabled: Bool) {
        rssNotificationsEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: rssNotificationsEnabledKey)
        if isEnabled {
            Task { await rssNotifications.requestAuthorizationIfNeeded() }
        }
    }

    private func loadRSSRefreshInterval() -> RSSRefreshScheduler.Interval {
        guard let raw = UserDefaults.standard.string(forKey: rssRefreshIntervalKey),
              let interval = RSSRefreshScheduler.Interval(rawValue: raw)
        else {
            return .default
        }
        return interval
    }

    private func loadRSSNotificationsEnabled() -> Bool {
        guard UserDefaults.standard.object(forKey: rssNotificationsEnabledKey) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: rssNotificationsEnabledKey)
    }

    // MARK: - 内部

    private func updateRSSFeed(_ feedID: UUID, mutate: (inout RSSFeed) -> Void) {
        guard let index = rssFeeds.firstIndex(where: { $0.id == feedID }) else { return }
        mutate(&rssFeeds[index])
        rssFeeds.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        persistRSSFeedList()
    }

    /// 条目落盘的同时把订阅列表里的计数一起更新，否则角标会和列表对不上。
    private func persistRSSItems(_ items: [RSSItem], feedID: UUID) {
        rssItemsByFeed[feedID] = items
        if let index = rssFeeds.firstIndex(where: { $0.id == feedID }) {
            rssFeeds[index].itemCount = items.count
            rssFeeds[index].unreadCount = items.count { !$0.isRead }
        }
        do {
            try rssStore.saveItems(items, feedID: feedID)
        } catch {
            rssStorageError = error.localizedDescription
            JarvisLog.error(category: .storage, event: "rss.items.saveFailed", error: error)
        }
        persistRSSFeedList()
    }

    private func persistRSSFeedList() {
        do {
            try rssStore.saveFeeds(rssFeeds)
            try rssStore.saveGroups(rssGroups)
        } catch {
            rssStorageError = error.localizedDescription
            JarvisLog.error(category: .storage, event: "rss.feeds.saveFailed", error: error)
        }
    }

    /// 首屏抓取时每条正文都要写一个文件，限制一次写入的条数，避免导入 OPML 时
    /// 一口气砸下几千个文件。
    private func cacheRSSContent(for entries: [RSSParsedEntry], itemIDs: Set<String>, feedID: UUID) {
        let feedID = feedID
        var written = 0
        for entry in entries {
            guard written < Self.rssContentCacheLimitPerRefresh else { break }
            guard let content = entry.contentHTML, !content.isEmpty else { continue }
            let key = RSSItemIdentity.deduplicationKey(
                guid: entry.guid,
                link: entry.link,
                title: entry.title,
                publishedAt: entry.publishedAt
            )
            guard itemIDs.contains(key) else { continue }
            do {
                try rssStore.writeContent(content, itemID: key)
                written += 1
                if var items = rssItemsByFeed[feedID],
                   let index = items.firstIndex(where: { $0.id == key })
                {
                    items[index].hasCachedContent = true
                    rssItemsByFeed[feedID] = items
                }
            } catch {
                JarvisLog.error(category: .storage, event: "rss.content.writeFailed", error: error)
            }
        }
    }

    private static let rssContentCacheLimitPerRefresh = 150

    private func fetchAndParseRSSFeed(_ url: URL) async throws -> RSSParsedFeed {
        let response = try await rssClient.fetch(RSSFetchRequest(url: url))
        guard !response.notModified else {
            throw RSSFeedParserError.notAFeed
        }
        return try RSSFeedParser.parse(response.data, baseURL: url)
    }

    /// 先把输入当订阅源试，不像订阅源就当年网页去里面找；再不行试几个常见路径。
    private func discoverRSSFeedCandidates(startingAt url: URL) async -> [URL] {
        var candidates: [URL] = []
        do {
            let response = try await rssClient.fetch(RSSFetchRequest(url: url))
            if RSSFeedParser.looksLikeFeed(response.data) {
                return [url]
            }
            if RSSFeedDiscovery.looksLikeHTML(response.data) {
                let html = String(data: response.data, encoding: .utf8)
                    ?? String(data: response.data, encoding: .isoLatin1)
                    ?? ""
                candidates.append(contentsOf: RSSFeedDiscovery.feedURLs(inHTML: html, baseURL: url))
            }
        } catch {
            JarvisLog.notice(
                category: .network,
                event: "rss.discovery.probeFailed",
                result: "failed",
                fields: ["host": url.host ?? ""]
            )
        }
        candidates.append(contentsOf: RSSFeedDiscovery.fallbackFeedURLs(for: url))
        candidates.append(url)
        var seen: Set<String> = []
        return candidates.filter { seen.insert($0.absoluteString).inserted }
    }

    static func normalizedRSSInput(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            return (scheme == "http" || scheme == "https") ? url : nil
        }
        guard !trimmed.contains(" ") else { return nil }
        return URL(string: "https://\(trimmed)")
    }
}

/// 启动时一次性读出的 RSS 状态，跨线程传递用。
struct RSSSnapshot: Sendable {
    var feeds: [RSSFeed]
    var groups: [RSSGroup]
    var itemsByFeed: [UUID: [RSSItem]]
}
