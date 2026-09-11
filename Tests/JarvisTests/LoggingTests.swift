import Foundation
@testable import Jarvis
import XCTest

final class LoggingTests: XCTestCase {
    func testLogFacadeWritesContextAndRedactsFields() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JarvisLogFacadeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = JarvisLocalLogStore(directoryURL: directory)
        JarvisLog.configure(localStore: store, debugEnabled: true)
        for _ in 0 ..< 2 {
            JarvisLog.info(
                category: .clipboard,
                event: "test.facade.(index)",
                operationID: "operation",
                fields: [
                    "clipboardText": "private clipboard body",
                    "path": "/Volumes/Private/secret.txt"
                ]
            )
        }

        let file = try XCTUnwrap(store.eventFileURLs.first)
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        let line = try XCTUnwrap(lines.first)
        let event = try JSONDecoder().decode(JarvisLogEvent.self, from: Data(line.utf8))

        XCTAssertEqual(event.category, .clipboard)
        XCTAssertEqual(event.operationID, "operation")
        XCTAssertEqual(event.fields["clipboardText"], "<redacted>")
        XCTAssertFalse(event.fields["path"]?.contains("secret.txt") == true)
        XCTAssertFalse(event.sessionID.isEmpty)
        XCTAssertGreaterThan(event.processID, 0)
    }

    func testRedactorRemovesClipboardSensitiveValues() {
        let secret = "password=correct-horse-battery-staple"
        let values = JarvisLogRedactor.fields([
            "message": secret,
            "clipboardText": "ordinary clipboard text",
            "url": "https://example.com/private?token=abc",
            "email": "person@example.com",
            "opaque": "abcdefghijklmnopqrstuvwxyz123456"
        ])

        XCTAssertFalse(values.values.contains { $0.contains("correct-horse") })
        XCTAssertFalse(values.values.contains { $0.contains("https://") })
        XCTAssertFalse(values.values.contains { $0.contains("person@example.com") })
        XCTAssertFalse(values.values.contains { $0.contains("abcdefghijklmnopqrstuvwxyz123456") })
        XCTAssertEqual(values["clipboardText"], "<redacted>")
    }

    func testPathRedactorKeepsApplicationSupportShapeAndHidesExternalPath() {
        let appSupportPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Jarvis/Clipboard/item-123.png")
            .path
        let externalPath = "/Volumes/Private/secret-document.pdf"

        XCTAssertTrue(JarvisLogRedactor.path(appSupportPath).hasPrefix("~/Library/Application Support/"))
        XCTAssertFalse(JarvisLogRedactor.path(externalPath).contains("secret-document"))
        XCTAssertTrue(JarvisLogRedactor.path(externalPath).hasPrefix("<external-file>.pdf#"))
    }

    func testLocalLogStoreWritesJSONLinesWithPermissionsAndRotates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JarvisLoggingTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = JarvisLocalLogStore(
            directoryURL: directory,
            maximumFileBytes: 500,
            maximumFileCount: 3
        )
        for index in 0 ..< 24 {
            store.append(
                JarvisLogEvent(
                    schemaVersion: 1,
                    timestamp: "2026-09-11T00:00:00Z",
                    level: .info,
                    category: .storage,
                    event: "test.event",
                    sessionID: "session",
                    operationID: "operation-\(index)",
                    processID: 1,
                    bundleID: "com.jarvis.mac",
                    bundlePath: "<app>",
                    appVersion: "1.2.20",
                    build: "254",
                    durationMilliseconds: nil,
                    result: "success",
                    fields: ["payload": String(repeating: "x", count: 140)]
                )
            )
        }

        let files = store.eventFileURLs
        XCTAssertLessThanOrEqual(files.count, 3)
        XCTAssertTrue(files.contains { $0.lastPathComponent == "events.ndjson" })

        for file in files {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            let lines = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n")
            XCTAssertFalse(lines.isEmpty)
            for line in lines {
                XCTAssertNoThrow(try JSONDecoder().decode(JarvisLogEvent.self, from: Data(line.utf8)))
            }
        }

        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testClipboardCacheAuditCountsMissingReferencesWithoutChangingItems() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JarvisClipboardAuditTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "JarvisClipboardAudit-\(UUID().uuidString)"))
        defaults.set(directory.path, forKey: "jarvis.clipboard.cache.directory")
        let store = ClipboardCacheStore(defaults: defaults)
        let existingPath = directory.appendingPathComponent("item-existing.png")
        try Data([1, 2, 3]).write(to: existingPath)

        let existing = ClipboardItem(
            kind: .image,
            imagePath: existingPath.path,
            isStoredCopy: true
        )
        let missing = ClipboardItem(
            kind: .image,
            imagePath: directory.appendingPathComponent("item-missing.png").path,
            isStoredCopy: true
        )
        let inlineText = ClipboardItem(
            kind: .text,
            text: "safe inline text",
            textPath: directory.appendingPathComponent("item-missing.txt").path,
            isStoredCopy: true
        )

        let audit = store.audit(items: [existing, missing, inlineText])

        XCTAssertEqual(audit.historyCount, 3)
        XCTAssertEqual(audit.referenceCount, 3)
        XCTAssertEqual(audit.missingReferenceCount, 2)
        XCTAssertEqual(audit.missingByKind[ClipboardKind.image.rawValue], 1)
        XCTAssertEqual(audit.missingByKind[ClipboardKind.text.rawValue], 1)
        XCTAssertEqual(audit.missingByReferenceType["imagePath"], 1)
        XCTAssertEqual(audit.missingByReferenceType["textPath"], 1)
        XCTAssertEqual(audit.unusableRecordCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingPath.path))
        XCTAssertEqual(missing.imagePath, directory.appendingPathComponent("item-missing.png").path)
    }
}
