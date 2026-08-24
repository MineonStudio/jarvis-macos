import Foundation
@testable import Jarvis
import XCTest

final class AIConversationDownloadsTests: XCTestCase {
    func testDestinationUsesSuggestedFilenameAndAvoidsOverwriting() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-download-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appendingPathComponent("report.pdf")
        FileManager.default.createFile(atPath: original.path, contents: Data())

        let destination = AIConversationDownloadFileName.destination(
            in: directory,
            suggestedFilename: "report.pdf"
        )

        XCTAssertEqual(destination.lastPathComponent, "report (2).pdf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testDestinationDoesNotEscapeDownloadsDirectoryForPathLikeNames() {
        let directory = URL(fileURLWithPath: "/tmp/jarvis-download-test")

        let destination = AIConversationDownloadFileName.destination(
            in: directory,
            suggestedFilename: "../report.txt"
        )

        XCTAssertEqual(destination.deletingLastPathComponent().path, directory.path)
        XCTAssertEqual(destination.lastPathComponent, "report.txt")
    }
}
