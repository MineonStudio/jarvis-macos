import Foundation
@testable import Jarvis
import XCTest

final class RSSItemIdentityTests: XCTestCase {
    func testGUIDWinsOverLink() {
        let key = RSSItemIdentity.deduplicationKey(
            guid: "post-1",
            link: URL(string: "https://example.com/a"),
            title: "标题",
            publishedAt: nil
        )
        XCTAssertEqual(key, "guid:post-1")
    }

    func testLinkGUIDIsCanonicalizedSoTrackingParametersDoNotForkItems() {
        let withTracking = RSSItemIdentity.deduplicationKey(
            guid: "https://example.com/post?utm_source=rss&utm_medium=feed",
            link: nil,
            title: "标题",
            publishedAt: nil
        )
        let plain = RSSItemIdentity.deduplicationKey(
            guid: "https://example.com/post",
            link: nil,
            title: "标题",
            publishedAt: nil
        )
        XCTAssertEqual(withTracking, plain)
    }

    func testCanonicalLinkStripsFragmentTrailingSlashAndTracking() throws {
        let canonical = try RSSItemIdentity.canonicalLink(
            XCTUnwrap(URL(string: "https://Example.com/Post/?utm_campaign=x&id=7#section"))
        )
        XCTAssertEqual(canonical, "https://example.com/Post?id=7")
    }

    func testFallsBackToTitleAndDateHashWhenNothingElseIsStable() {
        let first = RSSItemIdentity.deduplicationKey(guid: nil, link: nil, title: "无链接", publishedAt: nil)
        let second = RSSItemIdentity.deduplicationKey(guid: nil, link: nil, title: "无链接", publishedAt: nil)
        let other = RSSItemIdentity.deduplicationKey(guid: nil, link: nil, title: "另一篇", publishedAt: nil)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, other)
        XCTAssertTrue(first.hasPrefix("title:"))
    }

    func testRejectsNonHTTPLinks() throws {
        XCTAssertNil(try RSSItemIdentity.canonicalLink(XCTUnwrap(URL(string: "ftp://example.com/a"))))
    }
}

final class RSSItemMergeTests: XCTestCase {
    private let feedID = UUID()

    private func item(
        _ id: String,
        title: String = "标题",
        publishedAt: Date? = nil,
        isRead: Bool = false,
        isStarred: Bool = false
    ) -> RSSItem {
        RSSItem(
            id: id,
            feedID: feedID,
            title: title,
            publishedAt: publishedAt,
            isRead: isRead,
            isStarred: isStarred
        )
    }

    func testRefetchKeepsLocalReadAndStarState() {
        let existing = [item("guid:1", isRead: true, isStarred: true)]
        let incoming = [item("guid:1", title: "改过的标题")]

        let result = RSSItemMerge.merge(existing: existing, incoming: incoming)

        XCTAssertEqual(result.items.count, 1)
        XCTAssertTrue(result.items[0].isRead)
        XCTAssertTrue(result.items[0].isStarred)
        XCTAssertEqual(result.items[0].title, "改过的标题")
        XCTAssertTrue(result.insertedIDs.isEmpty)
    }

    func testNewItemsAreReportedOnce() {
        let result = RSSItemMerge.merge(
            existing: [item("guid:1")],
            incoming: [item("guid:1"), item("guid:2"), item("guid:3")]
        )

        XCTAssertEqual(Set(result.insertedIDs), ["guid:2", "guid:3"])
        XCTAssertEqual(result.items.count, 3)
    }

    func testTrimsOldestBeyondMaximumButNeverStarred() {
        let now = Date()
        var existing: [RSSItem] = []
        for index in 0 ..< 10 {
            existing.append(
                item(
                    "guid:\(index)",
                    publishedAt: now.addingTimeInterval(-Double(index) * 60),
                    isStarred: index == 9
                )
            )
        }

        let result = RSSItemMerge.merge(existing: existing, incoming: [], maximumItems: 3, now: now)

        XCTAssertTrue(result.items.contains { $0.id == "guid:9" })
        XCTAssertTrue(result.items.count >= 4)
        XCTAssertTrue(result.removedIDs.contains("guid:5"))
    }

    func testDropsItemsOlderThanMaximumAge() {
        let now = Date()
        let fresh = item("guid:fresh", publishedAt: now)
        let stale = item("guid:stale", publishedAt: now.addingTimeInterval(-91 * 24 * 60 * 60))

        let result = RSSItemMerge.merge(existing: [fresh, stale], incoming: [], now: now)

        XCTAssertEqual(result.items.map(\.id), ["guid:fresh"])
        XCTAssertEqual(result.removedIDs, ["guid:stale"])
    }

    func testStarredItemsSurviveAgeTrim() {
        let now = Date()
        let starredStale = item(
            "guid:starred",
            publishedAt: now.addingTimeInterval(-365 * 24 * 60 * 60),
            isStarred: true
        )

        let result = RSSItemMerge.merge(existing: [starredStale], incoming: [], now: now)

        XCTAssertEqual(result.items.map(\.id), ["guid:starred"])
        XCTAssertTrue(result.removedIDs.isEmpty)
    }

    func testOrderingPutsNewestFirst() {
        let now = Date()
        let older = item("guid:old", publishedAt: now.addingTimeInterval(-3600))
        let newer = item("guid:new", publishedAt: now)

        let result = RSSItemMerge.merge(existing: [older], incoming: [newer], now: now)

        XCTAssertEqual(result.items.map(\.id), ["guid:new", "guid:old"])
    }

    func testMakeItemsUsesStableDeduplicationKeys() {
        let entry = RSSParsedEntry(
            guid: nil,
            title: "标题",
            link: URL(string: "https://example.com/a"),
            author: nil,
            publishedAt: nil,
            summaryHTML: "摘要",
            contentHTML: nil,
            enclosureURL: nil,
            enclosureType: nil
        )

        let first = RSSItemMerge.makeItems(from: [entry], feedID: feedID)
        let second = RSSItemMerge.makeItems(from: [entry], feedID: feedID)

        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.first?.feedID, feedID)
    }
}

final class RSSRefreshBackoffTests: XCTestCase {
    func testDelayGrowsAndCaps() {
        let base: TimeInterval = 1800
        XCTAssertEqual(RSSRefreshBackoff.delay(failureCount: 0, baseInterval: base), base)
        XCTAssertEqual(RSSRefreshBackoff.delay(failureCount: 1, baseInterval: base), base * 2)
        XCTAssertEqual(RSSRefreshBackoff.delay(failureCount: 2, baseInterval: base), base * 4)
        XCTAssertEqual(
            RSSRefreshBackoff.delay(failureCount: 20, baseInterval: base),
            RSSRefreshBackoff.maximumDelay
        )
    }

    func testDueRespectsDisabledFeedsAndBackoffWindow() throws {
        let now = Date()
        let base: TimeInterval = 1800

        var feed = try RSSFeed(title: "A", feedURL: XCTUnwrap(URL(string: "https://a.example.com/feed")))
        feed.isEnabled = false
        XCTAssertFalse(RSSRefreshBackoff.isDue(feed: feed, now: now, baseInterval: base))

        feed.isEnabled = true
        XCTAssertTrue(RSSRefreshBackoff.isDue(feed: feed, now: now, baseInterval: base))

        feed.lastFetchedAt = now.addingTimeInterval(-60)
        feed.failureCount = 3
        XCTAssertFalse(RSSRefreshBackoff.isDue(feed: feed, now: now, baseInterval: base))

        feed.failureCount = 0
        feed.lastFetchedAt = now.addingTimeInterval(-base - 1)
        XCTAssertTrue(RSSRefreshBackoff.isDue(feed: feed, now: now, baseInterval: base))
    }
}

final class RSSItemFilterTests: XCTestCase {
    func testFilterMatchingAndCounting() {
        let feedID = UUID()
        let items = [
            RSSItem(id: "a", feedID: feedID, title: "未读"),
            RSSItem(id: "b", feedID: feedID, title: "已读", isRead: true),
            RSSItem(id: "c", feedID: feedID, title: "星标", isRead: true, isStarred: true)
        ]

        XCTAssertEqual(RSSFilterLogic.count(for: .all, in: items), 3)
        XCTAssertEqual(RSSFilterLogic.count(for: .unread, in: items), 1)
        XCTAssertEqual(RSSFilterLogic.count(for: .starred, in: items), 1)
    }
}

final class RSSFeedStoreTests: XCTestCase {
    private func makeStore() -> (RSSFeedStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JarvisRSSStoreTests-\(UUID().uuidString)", isDirectory: true)
        return (RSSFeedStore(directoryURL: directory), directory)
    }

    func testRoundTripsFeedsGroupsAndItems() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let feedID = UUID()

        let group = RSSGroup(title: "技术", order: 0)
        let feed = try RSSFeed(title: "示例", feedURL: XCTUnwrap(URL(string: "https://example.com/feed")), groupID: group.id)
        try store.saveGroups([group])
        try store.saveFeeds([feed])

        let item = RSSItem(id: "guid:1", feedID: feedID, title: "标题", summaryHTML: "<p>摘要</p>")
        try store.saveItems([item], feedID: feedID)

        XCTAssertEqual(store.loadGroups().map(\.title), ["技术"])
        XCTAssertEqual(store.loadFeeds().map(\.title), ["示例"])
        XCTAssertEqual(store.loadItems(feedID: feedID).map(\.id), ["guid:1"])

        for file in ["feeds.json", "groups.json", "items-\(feedID.uuidString).json"] {
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(file).path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600, file)
        }
    }

    func testMissingFilesReadAsEmptyInsteadOfThrowing() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertTrue(store.loadFeeds().isEmpty)
        XCTAssertTrue(store.loadGroups().isEmpty)
        XCTAssertTrue(store.loadItems(feedID: UUID()).isEmpty)
        XCTAssertNil(store.loadContent(itemID: "missing"))
    }

    func testContentRoundTripAndHashedFileNames() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let trickyID = "link:https://example.com/../../etc/passwd"
        try store.writeContent("<p>正文</p>", itemID: trickyID)

        XCTAssertEqual(store.loadContent(itemID: trickyID), "<p>正文</p>")

        let url = store.contentFileURL(itemID: trickyID)
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "content")
        XCTAssertFalse(url.lastPathComponent.contains(".."))
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".html"))

        store.deleteContent(itemIDs: [trickyID])
        XCTAssertNil(store.loadContent(itemID: trickyID))
    }

    func testDeletingFeedRemovesItsItemFile() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let feedID = UUID()

        try store.saveItems([RSSItem(id: "a", feedID: feedID, title: "标题")], feedID: feedID)
        XCTAssertFalse(store.loadItems(feedID: feedID).isEmpty)

        store.deleteItems(feedID: feedID)
        XCTAssertTrue(store.loadItems(feedID: feedID).isEmpty)
    }

    func testItemsAreSortedNewestFirstOnLoad() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let feedID = UUID()
        let now = Date()

        try store.saveItems(
            [
                RSSItem(id: "old", feedID: feedID, title: "旧", publishedAt: now.addingTimeInterval(-3600)),
                RSSItem(id: "new", feedID: feedID, title: "新", publishedAt: now)
            ],
            feedID: feedID
        )

        XCTAssertEqual(store.loadItems(feedID: feedID).map(\.id), ["new", "old"])
    }
}
