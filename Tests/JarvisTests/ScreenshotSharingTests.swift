import AppKit
@testable import Jarvis
import UniformTypeIdentifiers
import XCTest

final class ScreenshotSharingTests: XCTestCase {
    func testScreenshotDragProviderPublishesPNGDataAndSuggestedName() {
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let provider = ScreenshotSharing.itemProvider(
            data: data,
            suggestedName: "capture.png"
        )

        XCTAssertEqual(provider.suggestedName, "capture.png")
        XCTAssertTrue(provider.registeredTypeIdentifiers.contains(UTType.png.identifier))

        let expectation = expectation(description: "PNG data representation loads")
        var loadedData: Data?
        provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, error in
            loadedData = data
            XCTAssertNil(error)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)
        XCTAssertEqual(loadedData, data)
    }

    func testScreenshotDragProviderAddsPNGExtensionWhenNameHasNone() {
        let provider = ScreenshotSharing.itemProvider(
            data: Data([1, 2, 3]),
            suggestedName: "capture"
        )

        XCTAssertEqual(provider.suggestedName, "capture.png")
    }

    func testClipboardTextProviderPublishesPlainText() {
        let item = ClipboardItem(kind: .text, text: "拖拽文本")
        let provider = ClipboardSharing.itemProvider(for: item)

        XCTAssertNotNil(provider)
        XCTAssertTrue(
            provider?.registeredTypeIdentifiers.contains(UTType.utf8PlainText.identifier) == true
        )
    }

    func testClipboardImageProviderPublishesPNG() throws {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-clipboard-image-\(UUID().uuidString).png")
        try data.write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }

        let item = ClipboardItem(
            kind: .image,
            imagePath: path.path,
            fileName: "图片.png"
        )
        let provider = ClipboardSharing.itemProvider(for: item)

        XCTAssertTrue(provider?.registeredTypeIdentifiers.contains(UTType.png.identifier) == true)
    }

    func testClipboardFileAndVideoProvidersUseStoredFile() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-clipboard-file-\(UUID().uuidString).dat")
        try Data([1, 2, 3]).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }

        for kind in [ClipboardKind.file, .video] {
            let item = ClipboardItem(
                kind: kind,
                filePath: path.path,
                fileName: path.lastPathComponent
            )
            XCTAssertNotNil(ClipboardSharing.itemProvider(for: item))
        }
    }
}
