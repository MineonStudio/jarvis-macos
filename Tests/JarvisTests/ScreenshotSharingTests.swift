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
}
