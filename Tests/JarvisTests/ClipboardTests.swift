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
        XCTAssertNil(item.thumbnailPath)
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
        XCTAssertEqual(HistoryGridMetrics.pageSize(for: fiveColumnWidth), 15)

        let fourColumnWidth = HistoryGridMetrics.clipboardGridWidth(for: 4)
        XCTAssertEqual(HistoryGridMetrics.columnCount(for: fourColumnWidth), 4)
        XCTAssertEqual(HistoryGridMetrics.pageSize(for: fourColumnWidth), 12)
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
        store.updateMaximumBytes(ClipboardCacheStore.minimumMaximumBytes)
        XCTAssertNotNil(store.storeData(Data(repeating: 1, count: 128), fileExtension: "png"))

        let usage = store.usage()
        XCTAssertEqual(usage.usedBytes, 128)
        XCTAssertEqual(usage.fileCount, 1)
        XCTAssertEqual(usage.capacityBytes, ClipboardCacheStore.minimumMaximumBytes)
    }
}
