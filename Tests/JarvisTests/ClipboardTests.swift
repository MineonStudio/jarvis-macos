import AppKit
@testable import Jarvis
import XCTest

final class ClipboardTests: XCTestCase {
    func testClipboardIgnoresConcealedAndTransientPasteboardTypes() {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("JarvisClipboardPrivacy-\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        pasteboard.setString("secret-password", forType: .string)
        XCTAssertFalse(ClipboardPasteboardPrivacy.shouldIgnore(pasteboard))

        pasteboard.setString("1", forType: ClipboardPasteboardPrivacy.concealedType)
        XCTAssertTrue(ClipboardPasteboardPrivacy.shouldIgnore(pasteboard))

        pasteboard.clearContents()
        pasteboard.setString("token", forType: .string)
        pasteboard.setString("1", forType: ClipboardPasteboardPrivacy.transientType)
        XCTAssertTrue(ClipboardPasteboardPrivacy.shouldIgnore(pasteboard))
    }

    func testSensitiveContentDetectorCoversCredentialsWithoutMaskingNormalText() {
        XCTAssertEqual(
            SensitiveContentDetector.detect("api_key=sk-abcdefghijklmnopqrstuvwxyz123456"),
            .authentication
        )
        XCTAssertEqual(
            SensitiveContentDetector.detect("-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----"),
            .privateKey
        )
        XCTAssertEqual(
            SensitiveContentDetector.detect("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abcdefghijklmno.signaturevalue123"),
            .jsonWebToken
        )
        XCTAssertNil(SensitiveContentDetector.detect("这是普通的 Swift 代码和日志文本。"))
        XCTAssertNil(SensitiveContentDetector.detect("https://example.com/docs?query=swift"))
    }

    func testSensitivePresentationMasksOriginalTextUntilExplicitReveal() {
        let secret = "Authorization: Bearer sk-abcdefghijklmnopqrstuvwxyz123456"
        let masked = SensitiveContentDetector.presentation(for: secret)
        XCTAssertTrue(masked.requiresReveal)
        XCTAssertFalse(masked.displayText.contains("sk-abcdefghijklmnopqrstuvwxyz123456"))
        XCTAssertFalse(masked.accessibilityText.contains("sk-abcdefghijklmnopqrstuvwxyz123456"))

        let revealed = SensitiveContentDetector.presentation(for: secret, revealed: true)
        XCTAssertFalse(revealed.requiresReveal)
        XCTAssertEqual(revealed.displayText, secret)
        XCTAssertFalse(revealed.accessibilityText.contains("sk-abcdefghijklmnopqrstuvwxyz123456"))
        XCTAssertTrue(revealed.accessibilityText.contains("已临时显示"))
    }

    func testSensitiveClipboardPresentationDoesNotChangePersistedItem() throws {
        let item = ClipboardItem(kind: .text, text: "password=correct-horse-battery-staple")
        let encoded = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: encoded)

        XCTAssertEqual(decoded.resolvedText, item.resolvedText)
        XCTAssertEqual(decoded.clipboardSensitivity, .authentication)
        XCTAssertFalse(decoded.sensitivePresentation()?.displayText.contains("correct-horse") == true)
    }

    func testClipboardServiceExtractsAllFileURLsFromPasteboard() {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("JarvisClipboardTests-\(UUID().uuidString)")
        )
        let firstURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("first.txt")
        let secondURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("second.pdf")

        XCTAssertTrue(pasteboard.writeObjects([firstURL as NSURL, secondURL as NSURL]))
        XCTAssertEqual(
            ClipboardService.fileURLs(from: pasteboard),
            [firstURL, secondURL]
        )
    }

    func testClipboardTextItemsCanOpenTheSharedFullscreenPreview() {
        let textItem = ClipboardItem(kind: .text, text: "可预览的文本")
        let emptyText = ClipboardItem(kind: .text, text: nil)
        let fileItem = ClipboardItem(kind: .file, filePath: "/tmp/file.pdf")

        XCTAssertEqual(textItem.resolvedText, "可预览的文本")
        XCTAssertTrue(textItem.canFullscreenPreview)
        XCTAssertFalse(emptyText.canFullscreenPreview)
        XCTAssertFalse(fileItem.canFullscreenPreview)
    }

    func testClipboardItemRoundTripsVideoMetadataAndPin() throws {
        let item = ClipboardItem(
            kind: .video,
            filePath: "/tmp/example.mov",
            thumbnailPath: "/tmp/example-thumbnail.png",
            fileName: "example.mov",
            fileSize: 2048,
            fileUTI: "com.apple.quicktime-movie",
            fingerprintValue: "source|2048",
            isStoredCopy: true,
            isPinned: true
        )

        let encoded = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: encoded)

        XCTAssertEqual(decoded, item)
        XCTAssertEqual(decoded.kind, .video)
        XCTAssertTrue(decoded.isPinned)
        XCTAssertTrue(decoded.isStoredCopy)
        XCTAssertEqual(decoded.thumbnailPath, "/tmp/example-thumbnail.png")
    }

    func testClipboardItemDecodesHistoryWrittenByOlderBuild() throws {
        let id = UUID()
        let json = Data("""
        {
          "id": "\(id.uuidString)",
          "createdAt": 0,
          "kind": "image",
          "text": null,
          "imagePath": "/tmp/legacy-image.png"
        }
        """.utf8)

        let item = try JSONDecoder().decode(ClipboardItem.self, from: json)
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.kind, .image)
        XCTAssertFalse(item.isPinned)
        XCTAssertFalse(item.isStoredCopy)
        XCTAssertNil(item.textPath)
        XCTAssertNil(item.thumbnailPath)
    }

    func testClipboardTextCacheMetadataRoundTrips() throws {
        let item = ClipboardItem(
            kind: .text,
            text: "缓存文本",
            textPath: "/tmp/item-text.txt",
            fileSize: 15,
            isStoredCopy: true
        )

        let encoded = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: encoded)

        XCTAssertEqual(decoded.textPath, item.textPath)
        XCTAssertEqual(decoded.cachePaths, ["/tmp/item-text.txt"])
        XCTAssertTrue(decoded.isStoredCopy)
    }

    /// 去抖写入可能带着调度时观察到的旧状态晚到，不能让它覆盖用户随后做的收藏或删除。
    func testClipboardStoreDiscardsWriteWithStaleRevision() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-clipboard-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ClipboardStore(directoryURL: directory)
        XCTAssertTrue(store.save([ClipboardItem(kind: .text, text: "收藏后的状态")], revision: 2))
        XCTAssertTrue(store.save([ClipboardItem(kind: .text, text: "调度时的旧状态")], revision: 1))

        XCTAssertEqual(store.load().map(\.text), ["收藏后的状态"])
    }

    func testClipboardStoreAppliesWriteWithNewerRevisionAndWithoutOne() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-clipboard-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ClipboardStore(directoryURL: directory)
        XCTAssertTrue(store.save([ClipboardItem(kind: .text, text: "第一次")], revision: 1))
        XCTAssertTrue(store.save([ClipboardItem(kind: .text, text: "第二次")], revision: 2))
        XCTAssertEqual(store.load().map(\.text), ["第二次"])

        // 不带版本号的写入（迁移、启动路径）照旧无条件落盘。
        XCTAssertTrue(store.save([ClipboardItem(kind: .text, text: "无条件写入")]))
        XCTAssertEqual(store.load().map(\.text), ["无条件写入"])
    }

    /// 后台写入者必须与 AppModel 共用同一个 store，否则文件锁和版本号会各持一份，
    /// 双写入者的覆盖问题就会回来。
    func testClipboardHistoryWriterSharesItsStore() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-clipboard-writer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ClipboardStore(directoryURL: directory)
        let writer = ClipboardHistoryWriter(store: store)
        let saved = await writer.save([ClipboardItem(kind: .text, text: "经写入者落盘")], revision: 1)
        XCTAssertTrue(saved)

        // 写入者写进了这个 store 的文件。
        XCTAssertEqual(store.load().map(\.text), ["经写入者落盘"])

        // 版本号也是共享的：写入者用掉的版本，store 侧认得出来并丢弃更旧的写入。
        XCTAssertTrue(store.save([ClipboardItem(kind: .text, text: "过期快照")], revision: 0))
        XCTAssertEqual(store.load().map(\.text), ["经写入者落盘"])
    }

    func testClipboardOrderingKeepsNewestFirstRegardlessOfPinState() {
        let older = ClipboardItem(
            createdAt: Date(timeIntervalSince1970: 100),
            kind: .text,
            text: "older",
            isPinned: true
        )
        let newer = ClipboardItem(
            createdAt: Date(timeIntervalSince1970: 200),
            kind: .text,
            text: "newer"
        )

        XCTAssertEqual(
            ClipboardOrdering.newestFirst([older, newer]),
            [newer, older]
        )
    }

    func testVideoThumbnailGeneratorFailsSafelyForMissingFile() {
        let expectation = expectation(description: "Missing video returns no thumbnail")
        ClipboardVideoThumbnailGenerator.makeCGImageAsync(
            for: URL(fileURLWithPath: "/tmp/jarvis-missing-video.mov")
        ) { image in
            XCTAssertNil(image)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testClipboardFilterLogicKeepsSearchAndTypeFilteringConsistent() {
        let text = ClipboardItem(kind: .text, text: "Swift quality audit")
        let image = ClipboardItem(kind: .image, imagePath: "/tmp/a.png")
        let video = ClipboardItem(kind: .video, filePath: "/tmp/demo.mov")

        let items = [text, image, video]
        XCTAssertEqual(
            ClipboardFilterLogic.filteredItems(
                from: items,
                searchText: "quality",
                filter: .all
            ),
            [text]
        )
        XCTAssertEqual(
            ClipboardFilterLogic.filteredItems(
                from: items,
                searchText: "",
                filter: .image
            ),
            [image]
        )
        XCTAssertEqual(ClipboardFilterLogic.count(for: .text, in: items), 1)

        let counts = ClipboardFilterLogic.counts(in: items)
        XCTAssertEqual(counts[.all], 3)
        XCTAssertEqual(counts[.text], 1)
        XCTAssertEqual(counts[.image], 1)
        XCTAssertEqual(counts[.video], 1)
    }

    func testClipboardTimeFilterUsesCreatedAtAndCombinesWithCategory() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recentText = ClipboardItem(
            createdAt: now.addingTimeInterval(-2 * 24 * 60 * 60),
            kind: .text,
            text: "recent"
        )
        let oldText = ClipboardItem(
            createdAt: now.addingTimeInterval(-8 * 24 * 60 * 60),
            kind: .text,
            text: "old"
        )
        let recentImage = ClipboardItem(
            createdAt: now.addingTimeInterval(-2 * 24 * 60 * 60),
            kind: .image,
            imagePath: "/tmp/recent.png"
        )

        XCTAssertEqual(
            ClipboardTimeFilterLogic.filteredItems(
                from: [recentText, oldText, recentImage],
                filter: .sevenDays,
                now: now
            ),
            [recentText, recentImage]
        )
        XCTAssertEqual(
            ClipboardFilterLogic.filteredItems(
                from: [recentText, oldText, recentImage],
                searchText: "",
                timeFilter: .sevenDays,
                category: .text,
                now: now
            ),
            [recentText]
        )
    }

    func testClipboardGridUsesOneUniformCardSize() {
        XCTAssertEqual(HistoryGridMetrics.clipboardCardWidth, 211.2, accuracy: 0.001)
        XCTAssertEqual(HistoryGridMetrics.clipboardCardHeight, 118.8, accuracy: 0.001)
        XCTAssertEqual(HistoryGridMetrics.clipboardPreviewHeight, 118.8, accuracy: 0.001)
        XCTAssertEqual(
            HistoryGridMetrics.clipboardCardHeight,
            HistoryGridMetrics.clipboardCardWidth * 9 / 16,
            accuracy: 0.001
        )
        XCTAssertEqual(HistoryGridMetrics.clipboardActionButtonSize, 32)
        XCTAssertEqual(HistoryGridMetrics.clipboardPreviewHoverScale, 1.08)
        XCTAssertEqual(HistoryGridMetrics.clipboardCornerRadius, 12)
        XCTAssertEqual(HistoryGridMetrics.clipboardGridSpacing, 10)
    }

    func testHistoryGridZoomLevelsAdjustCardSizeAndKeepAspectRatio() {
        XCTAssertEqual(HistoryGridZoomLevel.allCases.count, 5)
        XCTAssertEqual(
            HistoryGridZoomLevel.regular.cardWidth,
            HistoryGridMetrics.clipboardCardWidth,
            accuracy: 0.001
        )

        for level in HistoryGridZoomLevel.allCases {
            XCTAssertEqual(level.cardHeight, level.cardWidth * 9 / 16, accuracy: 0.001)
        }

        XCTAssertFalse(HistoryGridZoomLevel.compact.canZoomOut)
        XCTAssertTrue(HistoryGridZoomLevel.compact.canZoomIn)
        XCTAssertEqual(HistoryGridZoomLevel.regular.zoomedOut, .small)
        XCTAssertEqual(HistoryGridZoomLevel.regular.zoomedIn, .large)
        XCTAssertTrue(HistoryGridZoomLevel.extraLarge.canZoomOut)
        XCTAssertFalse(HistoryGridZoomLevel.extraLarge.canZoomIn)
    }

    func testClipboardTimestampUsesSlashDateAndTimeFormat() {
        let item = ClipboardItem(
            createdAt: Date(timeIntervalSince1970: 1_757_296_000),
            kind: .text,
            text: "date"
        )

        XCTAssertTrue(
            item.shortTimestamp.range(
                of: #"^\d{4}/\d{2}/\d{2} \d{2}:\d{2}$"#,
                options: .regularExpression
            ) != nil
        )
    }

    func testClipboardCacheStoreUsesConfiguredDirectoryAndReportsUsage() throws {
        let suiteName = "jarvis-clipboard-cache-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-clipboard-cache-test-\(UUID().uuidString)", isDirectory: true)
        defaults.set(directory.path, forKey: "jarvis.clipboard.cache.directory")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let store = ClipboardCacheStore(defaults: defaults)
        XCTAssertEqual(store.currentDirectoryURL, directory)
        store.updateMaximumBytes(1_073_741_824 + 70_000_000)
        XCTAssertEqual(store.currentMaximumBytes, 1_073_741_824)
        store.updateMaximumBytes(ClipboardCacheStore.minimumMaximumBytes)
        XCTAssertNotNil(store.storeData(Data(repeating: 1, count: 128), fileExtension: "png"))

        let usage = store.usage()
        XCTAssertEqual(usage.usedBytes, 128)
        XCTAssertEqual(usage.fileCount, 1)
        XCTAssertEqual(usage.capacityBytes, ClipboardCacheStore.minimumMaximumBytes)
    }

    func testClipboardCacheUsageFillsTheBarAtAndAboveCapacity() {
        let capacity = ClipboardCacheStore.defaultMaximumBytes
        XCTAssertEqual(
            ClipboardCacheUsage(usedBytes: capacity, capacityBytes: capacity, fileCount: 1).fraction,
            1
        )
        XCTAssertEqual(
            ClipboardCacheUsage(usedBytes: capacity + 1, capacityBytes: capacity, fileCount: 1).fraction,
            1
        )
        XCTAssertEqual(ClipboardCacheStore.defaultMaximumBytes, 5 * 1024 * 1024 * 1024)
    }

    func testClipboardCacheCategoriesMatchTheirMediaKinds() {
        let text = ClipboardItem(kind: .text, text: "text")
        let image = ClipboardItem(kind: .image, imagePath: "/tmp/image.png", isStoredCopy: true)
        let video = ClipboardItem(kind: .video, filePath: "/tmp/video.mov", isStoredCopy: true)
        let file = ClipboardItem(kind: .file, filePath: "/tmp/file.pdf", isStoredCopy: true)
        let favorite = ClipboardItem(kind: .text, text: "favorite", isPinned: true)

        XCTAssertTrue(ClipboardCacheCategory.text.matches(text))
        XCTAssertTrue(ClipboardCacheCategory.image.matches(image))
        XCTAssertFalse(ClipboardCacheCategory.image.matches(video))
        XCTAssertTrue(ClipboardCacheCategory.video.matches(video))
        XCTAssertTrue(ClipboardCacheCategory.file.matches(file))
        XCTAssertTrue(ClipboardCacheCategory.all.matches(image))
        XCTAssertTrue(ClipboardCacheCategory.favorites.matches(favorite))
        XCTAssertEqual(
            ClipboardCacheCategory.allCases.map(\.rawValue),
            ["all", "favorites", "text", "image", "file", "video"]
        )
    }

    func testClipboardCacheRemovalHandlesLegacyStoredPathWithoutStoredCopyFlag() throws {
        let suiteName = "jarvis-clipboard-cache-removal-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-clipboard-cache-removal-\(UUID().uuidString)", isDirectory: true)
        defaults.set(directory.path, forKey: "jarvis.clipboard.cache.directory")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let store = ClipboardCacheStore(defaults: defaults)
        let path = try XCTUnwrap(store.storeData(Data(repeating: 1, count: 16), fileExtension: "png"))
        let legacyItem = ClipboardItem(
            kind: .image,
            imagePath: path,
            isStoredCopy: false
        )

        XCTAssertTrue(store.hasManagedFiles(for: legacyItem))
        XCTAssertTrue(store.removeManagedFiles(for: [legacyItem]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        XCTAssertEqual(store.usage().usedBytes, 0)
    }

    func testClipboardCacheCleanupRecognizesMissingManagedReferences() throws {
        let suiteName = "jarvis-clipboard-cache-stale-reference-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-clipboard-cache-stale-reference-\(UUID().uuidString)", isDirectory: true)
        defaults.set(directory.path, forKey: "jarvis.clipboard.cache.directory")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let store = ClipboardCacheStore(defaults: defaults)
        let path = try XCTUnwrap(store.storeData(Data(repeating: 1, count: 16), fileExtension: "png"))
        let item = ClipboardItem(kind: .image, imagePath: path, isStoredCopy: true)
        try FileManager.default.removeItem(atPath: path)

        XCTAssertFalse(store.hasManagedFiles(for: item))
        XCTAssertTrue(store.hasManagedReferences(for: item))
        XCTAssertTrue(store.removeManagedFiles(for: [item]))
    }

    func testClipboardCacheRemovalHandlesTextCache() throws {
        let suiteName = "jarvis-clipboard-cache-text-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-clipboard-cache-text-\(UUID().uuidString)", isDirectory: true)
        defaults.set(directory.path, forKey: "jarvis.clipboard.cache.directory")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let store = ClipboardCacheStore(defaults: defaults)
        let text = "缓存文本"
        let path = try XCTUnwrap(store.storeData(Data(text.utf8), fileExtension: "txt"))
        let item = ClipboardItem(
            kind: .text,
            text: text,
            textPath: path,
            isStoredCopy: true
        )

        XCTAssertTrue(store.hasManagedFiles(for: item))
        XCTAssertEqual(store.usage().usedBytes, Int64(Data(text.utf8).count))
        XCTAssertTrue(store.removeManagedFiles(for: [item]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        XCTAssertEqual(store.usage().usedBytes, 0)
    }

    func testClipboardCacheRemovalDoesNotDeleteExternalSourceFile() throws {
        let suiteName = "jarvis-clipboard-cache-external-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-clipboard-cache-external-\(UUID().uuidString)", isDirectory: true)
        defaults.set(directory.path, forKey: "jarvis.clipboard.cache.directory")
        let externalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-external-\(UUID().uuidString).png")
        try Data(repeating: 1, count: 16).write(to: externalURL)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: externalURL)
        }

        let store = ClipboardCacheStore(defaults: defaults)
        let externalItem = ClipboardItem(
            kind: .image,
            imagePath: externalURL.path,
            isStoredCopy: false
        )

        XCTAssertFalse(store.hasManagedFiles(for: externalItem))
        XCTAssertFalse(store.hasManagedReferences(for: externalItem))
        XCTAssertTrue(store.removeManagedFiles(for: [externalItem]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalURL.path))
    }

    func testClipboardCacheCleanupPeriodsUseExpectedDurations() {
        XCTAssertEqual(ClipboardCacheCleanupPeriod.threeDays.interval, 3 * 24 * 60 * 60)
        XCTAssertEqual(ClipboardCacheCleanupPeriod.sevenDays.interval, 7 * 24 * 60 * 60)
        XCTAssertEqual(ClipboardCacheCleanupPeriod.oneMonth.interval, 30 * 24 * 60 * 60)
        XCTAssertEqual(ClipboardCacheCleanupPeriod.halfYear.interval, 182 * 24 * 60 * 60)
    }
}
