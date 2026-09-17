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
        // 授权状态只存在系统里，重启后必须重新问一次，否则通知会静默地全部丢掉。
        Task { [weak self] in
            await self?.rssNotifications.refreshAuthorizationState()
        }
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
            guard added > 0 else { return }
            if rssNotificationsEnabled {
                await rssNotifications.requestAuthorizationIfNeeded()
            }
            // 抓取和通知开关无关：关掉通知也得把导入的订阅拉一遍，否则列表是空的。
            await refreshAllRSSFeeds(manual: true)
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
        guard let snapshot = rssFeeds.first(where: { $0.id == feed.id }) else {
            return RSSRefreshOutcome()
        }
        let feedID = feed.id
        var outcome = RSSRefreshOutcome()

        do {
            let response = try await rssClient.fetch(
                RSSFetchRequest(
                    url: snapshot.feedURL,
                    etag: snapshot.etag,
                    lastModified: snapshot.lastModified
                )
            )

            if response.notModified {
                updateRSSFeedRecord(feedID) { current in
                    current.lastFetchedAt = Date()
                    current.lastSuccessAt = Date()
                    current.failureCount = 0
                    current.lastErrorMessage = nil
                    current.etag = response.etag
                    current.lastModified = response.lastModified
                }
                return outcome
            }

            // 解析放在后台队列：上限 10 MB 的 XML 不能压在主线程上，否则订阅一个
            // 大 feed 就是一次界面卡死。
            let data = response.data
            let baseURL = snapshot.feedURL
            let parsed = try await Task.detached(priority: .utility) {
                try RSSFeedParser.parse(data, baseURL: baseURL)
            }.value

            let existing = rssItemsByFeed[feedID] ?? []
            let merge = RSSItemMerge.merge(
                existing: existing,
                incoming: RSSItemMerge.makeItems(from: parsed.entries, feedID: feedID)
            )
            let insertedIDs = Set(merge.insertedIDs)
            let pendingContent = Self.rssContentToCache(
                entries: parsed.entries,
                feedID: feedID,
                insertedIDs: insertedIDs
            )

            // 正文写盘与淘汰也在后台做，回主线程只更新标记。
            let store = rssStore
            let removedIDs = merge.removedIDs
            let cachedIDs = await Task.detached(priority: .utility) { () -> Set<String> in
                store.deleteContent(itemIDs: removedIDs)
                var written: Set<String> = []
                for entry in pendingContent {
                    do {
                        try store.writeContent(entry.html, itemID: entry.itemID)
                        written.insert(entry.itemID)
                    } catch {
                        // 写不进去只是这一篇退回摘要渲染，但失败必须留下记录。
                        JarvisLog.error(
                            category: .storage,
                            event: "rss.content.writeFailed",
                            error: error
                        )
                    }
                }
                return written
            }.value

            var items = merge.items
            if !cachedIDs.isEmpty {
                for index in items.indices where cachedIDs.contains(items[index].id) {
                    items[index].hasCachedContent = true
                }
            }
            persistRSSItems(items, feedID: feedID)
            updateRSSFeedRecord(feedID) { current in
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
                current.lastFetchedAt = Date()
                current.lastSuccessAt = Date()
                // 只有整条链路（抓取 + 解析 + 合并）都成功才清零，否则一个一直返回
                // 错误页面的 feed 会永远停在第 1 次失败，退避永远不升级。
                current.failureCount = 0
                current.lastErrorMessage = nil
            }

            if collectNewItems {
                outcome.newItems = items.filter { insertedIDs.contains($0.id) }
            }
        } catch {
            updateRSSFeedRecord(feedID) { current in
                current.lastFetchedAt = Date()
                current.failureCount += 1
                current.lastErrorMessage = error.localizedDescription
            }
            outcome.failures[feedID] = error.localizedDescription
            JarvisLog.error(
                category: .network,
                event: "rss.feed.refreshFailed",
                error: error,
                fields: ["host": snapshot.feedURL.host ?? ""]
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

    /// 抓取流程专用的更新：按 ID 定位，且不重排列表。
    ///
    /// 网络等待期间用户可能删掉订阅、订阅新的源或者改名，拿 `await` 之前记下的
    /// 下标去写会写到别的订阅上，列表变短时还会直接越界崩溃。
    private func updateRSSFeedRecord(_ feedID: UUID, mutate: (inout RSSFeed) -> Void) {
        guard let index = rssFeeds.firstIndex(where: { $0.id == feedID }) else { return }
        mutate(&rssFeeds[index])
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

    /// 挑出本轮要缓存正文的新条目。纯函数，写盘交给调用方在后台做。
    ///
    /// 只缓存新增条目并设上限：首轮导入 OPML 时一口气能来几千条，全写下去既慢又
    /// 没必要——旧条目退回摘要渲染就够了。
    static func rssContentToCache(
        entries: [RSSParsedEntry],
        feedID: UUID,
        insertedIDs: Set<String>
    ) -> [(itemID: String, html: String)] {
        var pending: [(itemID: String, html: String)] = []
        for entry in entries {
            guard pending.count < rssContentCacheLimitPerRefresh else { break }
            guard let html = entry.contentHTML, !html.isEmpty else { continue }
            let itemID = RSSItemIdentity.itemID(
                feedID: feedID,
                key: RSSItemIdentity.deduplicationKey(
                    guid: entry.guid,
                    link: entry.link,
                    title: entry.title,
                    publishedAt: entry.publishedAt
                )
            )
            guard insertedIDs.contains(itemID) else { continue }
            pending.append((itemID: itemID, html: html))
        }
        return pending
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
