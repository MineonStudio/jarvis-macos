import Foundation
@testable import Jarvis
import XCTest

final class LoggingTests: XCTestCase {
    /// `JarvisLog` 的运行时的存储是进程级的：这里的测试把它指向临时目录，必须还原，
    /// 否则后面所有测试的日志都会写进一个已经删掉的目录，还会继承 `debugEnabled`
    /// （测试报告里记过的 L-47）。
    override func tearDown() {
        JarvisLog.configure(localStore: JarvisLocalLogStore(), debugEnabled: false)
        super.tearDown()
    }

    private func makeTemporaryDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeEvent(
        event: String = "test.event",
        operationID: String? = "operation",
        fields: [String: String] = [:]
    ) -> JarvisLogEvent {
        JarvisLogEvent(
            schemaVersion: JarvisLogEvent.currentSchemaVersion,
            timestamp: "2026-09-11T00:00:00Z",
            level: .info,
            category: .storage,
            event: event,
            sessionID: "session",
            operationID: operationID,
            processID: 1,
            bundleID: "com.jarvis.mac",
            bundlePath: "<app>",
            appVersion: "1.3.6",
            build: "333",
            durationMilliseconds: nil,
            result: "success",
            fields: fields
        )
    }

    func testLogFacadeWritesContextAndRedactsFields() throws {
        let directory = makeTemporaryDirectory("JarvisLogFacadeTests")
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
        // 日志写入是异步批量的，读文件前先落盘。
        JarvisLog.flush()

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

    /// 逐条钉住六种脱敏。规则编译失败时会被静默跳过（与 `replacingOccurrences` 遇到
    /// 无效模式的行为一致），所以模式写错不会崩、只会悄悄放过敏感内容——这个测试就是
    /// 防止那种沉默。
    func testEveryRedactionRuleStillApplies() {
        let cases: [(name: String, input: String, placeholder: String)] = [
            ("url", "见 https://example.com/a?b=c 完成", "<url>"),
            ("email", "联系 person@example.com 处理", "<email>"),
            ("credential", "api_key: sk-live-0123456789abcdef", "<credential>"),
            ("path", "读 /Users/someone/Documents/secret.txt 失败", "<path>"),
            (
                "jwt",
                "token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1g 过期",
                "<jwt>"
            ),
            ("opaque", "值 abcdefghijklmnopqrstuvwxyz123456 无效", "<opaque>")
        ]

        for (name, input, placeholder) in cases {
            let redacted = JarvisLogRedactor.text(input)
            XCTAssertTrue(
                redacted.contains(placeholder),
                "\(name) 规则没有生效：\(redacted)"
            )
        }
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
        let directory = makeTemporaryDirectory("JarvisLoggingTests")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = JarvisLocalLogStore(
            directoryURL: directory,
            maximumFileBytes: 500,
            maximumFileCount: 3
        )
        for index in 0 ..< 24 {
            store.append([
                makeEvent(
                    operationID: "operation-\(index)",
                    fields: ["payload": String(repeating: "x", count: 140)]
                )
            ])
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

    /// 异步批量写入不能丢事件，也不能打乱顺序：卡顿日志本来就是成串产生的。
    func testLogFacadeFlushKeepsEveryEventInOrder() throws {
        let directory = makeTemporaryDirectory("JarvisLogBatchTests")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = JarvisLocalLogStore(directoryURL: directory, maximumFileBytes: 10 * 1024 * 1024)
        JarvisLog.configure(localStore: store, debugEnabled: true)
        for index in 0 ..< 40 {
            JarvisLog.info(
                category: .performance,
                event: "test.batch",
                fields: ["index": String(index)]
            )
        }
        JarvisLog.flush()

        let file = try XCTUnwrap(store.eventFileURLs.first)
        let events = try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n")
            .map { try JSONDecoder().decode(JarvisLogEvent.self, from: Data($0.utf8)) }
        XCTAssertEqual(events.count, 40)
        XCTAssertEqual(
            events.compactMap { $0.fields["index"] },
            (0 ..< 40).map(String.init)
        )
    }

    func testLocalLogStoreBatchAppendWritesEveryEvent() throws {
        let directory = makeTemporaryDirectory("JarvisLogStoreBatchTests")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = JarvisLocalLogStore(directoryURL: directory, maximumFileBytes: 10 * 1024 * 1024)
        let events = (0 ..< 5).map { index in
            makeEvent(event: "test.batch.store", operationID: "operation-\(index)")
        }
        store.append(events)

        let file = try XCTUnwrap(store.eventFileURLs.first)
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 5)
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
