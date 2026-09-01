import Foundation
@testable import Jarvis
import XCTest

final class AllSpacesWallpaperStoreTests: XCTestCase {
    func testStoreWritesTheSystemAllSpacesConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-all-spaces-wallpaper-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let indexURL = directory.appendingPathComponent("Index.plist")
        let oldConfiguration = try PropertyListSerialization.data(
            fromPropertyList: ["type": "imageFile", "url": ["relative": "file:///old.jpg"]],
            format: .binary,
            options: 0
        )
        let originalRoot: [String: Any] = [
            "SystemDefault": [
                "Desktop": [
                    "Content": [
                        "Choices": [[
                            "Configuration": oldConfiguration,
                            "Files": [Any](),
                            "Provider": "com.apple.wallpaper.choice.image"
                        ]]
                    ],
                    "Type": "individual"
                ]
            ],
            "UnrelatedValue": "preserved"
        ]
        let originalData = try PropertyListSerialization.data(
            fromPropertyList: originalRoot,
            format: .binary,
            options: 0
        )
        try originalData.write(to: indexURL)

        var restartCount = 0
        let store = AllSpacesWallpaperStore(indexURL: indexURL) {
            restartCount += 1
        }
        let imageURL = URL(fileURLWithPath: "/tmp/Jarvis Wallpaper.png")
        try store.apply(imageURL: imageURL)

        let updatedData = try Data(contentsOf: indexURL)
        let root = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: updatedData, format: nil) as? [String: Any]
        )
        let allSpaces = try XCTUnwrap(root["AllSpacesAndDisplays"] as? [String: Any])
        let desktop = try XCTUnwrap(allSpaces["Desktop"] as? [String: Any])
        let content = try XCTUnwrap(desktop["Content"] as? [String: Any])
        let choices = try XCTUnwrap(content["Choices"] as? [[String: Any]])
        let choice = try XCTUnwrap(choices.first)
        let configuration = try XCTUnwrap(choice["Configuration"] as? Data)
        let configurationRoot = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: configuration, format: nil) as? [String: Any]
        )
        let url = try XCTUnwrap(configurationRoot["url"] as? [String: Any])

        XCTAssertEqual(allSpaces["Type"] as? String, "desktop")
        XCTAssertEqual(choice["Provider"] as? String, "com.apple.wallpaper.choice.image")
        XCTAssertEqual(url["relative"] as? String, imageURL.absoluteString)
        XCTAssertEqual(root["UnrelatedValue"] as? String, "preserved")
        XCTAssertEqual(restartCount, 1)
    }
}
