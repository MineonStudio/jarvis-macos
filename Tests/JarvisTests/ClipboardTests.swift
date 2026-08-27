import AppKit
@testable import Jarvis
import XCTest

final class ClipboardTests: XCTestCase {
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
        XCTAssertEqual(HistoryGridMetrics.clipboardGridSpacing, 14)
    }

    func testHistoryGridPaginationKeepsEachPageToCompleteRows() {
        let fiveColumnWidth = HistoryGridMetrics.clipboardGridWidth(for: 5)
        XCTAssertEqual(HistoryGridMetrics.columnCount(for: fiveColumnWidth), 5)
        XCTAssertEqual(
            HistoryGridMetrics.pageSize(
                for: fiveColumnWidth,
                availableHeight: 700,
                itemCount: 100,
                verticalInset: 0
            ),
            25
        )

        let fourColumnWidth = HistoryGridMetrics.clipboardGridWidth(for: 4)
        XCTAssertEqual(HistoryGridMetrics.columnCount(for: fourColumnWidth), 4)
        XCTAssertEqual(
            HistoryGridMetrics.pageSize(
                for: fourColumnWidth,
                availableHeight: 500,
                itemCount: 100,
                verticalInset: 0
            ),
            12
        )
    }

    func testHistoryGridRowsAdaptToAvailableHeight() {
        let rowHeight = HistoryGridMetrics.clipboardCardHeight
        let rowSpacing = HistoryGridMetrics.clipboardGridSpacing

        XCTAssertEqual(HistoryGridMetrics.rowCount(for: rowHeight), 1)
        XCTAssertEqual(
            HistoryGridMetrics.rowCount(for: rowHeight * 4 + rowSpacing * 3),
            4
        )
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
