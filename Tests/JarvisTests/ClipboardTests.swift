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
}
