import XCTest
@testable import Jarvis

final class ClipboardTests: XCTestCase {
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
        let json = """
        {
          "id": "\(id.uuidString)",
          "createdAt": 0,
          "kind": "image",
          "text": null,
          "imagePath": "/tmp/legacy-image.png"
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(ClipboardItem.self, from: json)
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.kind, .image)
        XCTAssertFalse(item.isPinned)
        XCTAssertFalse(item.isStoredCopy)
        XCTAssertNil(item.thumbnailPath)
    }

    func testVideoThumbnailGeneratorFailsSafelyForMissingFile() {
        let image = ClipboardVideoThumbnailGenerator.makePNGData(
            for: URL(fileURLWithPath: "/tmp/jarvis-missing-video.mov")
        )

        XCTAssertNil(image)
    }
}
