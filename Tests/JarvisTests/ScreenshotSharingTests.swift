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

    func testClipboardShareItemsPreserveTextPayload() {
        let item = ClipboardItem(kind: .text, text: "分享文本")
        let items = ClipboardSharing.shareItems(for: item)

        XCTAssertEqual(items?.count, 1)
        XCTAssertEqual(items?.first as? NSString, "分享文本")
    }
}
