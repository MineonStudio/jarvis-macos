@testable import Jarvis
import XCTest

/// 历史记录的容量与孤儿回收。
///
/// 原来只按**条数**封顶：单张截图 1-20MB 不等，100 张 Retina 全屏可以到 1-2GB，
/// 而用户完全看不到占用；索引写失败留下的 PNG 更是永远不会被淘汰。
final class ScreenshotHistoryCapacityTests: XCTestCase {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("JarvisHistoryCapacity-\(UUID().uuidString)", isDirectory: true)
    }

    private func data(_ bytes: Int) -> Data {
        Data(repeating: 0x41, count: bytes)
    }

    func testHistoryKeepsEveryScreenshotWithoutACountCap() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScreenshotHistoryStore(directoryURL: directory)

        var items: [ScreenshotHistoryItem] = []
        for index in 0 ..< 5 {
            let item = try XCTUnwrap(
                store.add(data: data(1000), date: Date().addingTimeInterval(TimeInterval(index)))
            )
            items.append(item)
        }

        let remaining = store.load()
        XCTAssertEqual(remaining.count, 5)
        XCTAssertEqual(remaining.map(\.id), items.reversed().map(\.id))
        XCTAssertEqual(store.storedUsage().fileCount, 5)
        XCTAssertEqual(store.storedUsage().bytes, 5000)
    }

    func testSharedCacheAdmissionRejectsWritesThatWouldExceedCapacity() {
        XCTAssertTrue(SharedCacheAdmission.allows(usedBytes: 80, capacityBytes: 100, incomingBytes: 20))
        XCTAssertFalse(SharedCacheAdmission.allows(usedBytes: 80, capacityBytes: 100, incomingBytes: 21))
        XCTAssertFalse(SharedCacheAdmission.allows(usedBytes: 100, capacityBytes: 100, incomingBytes: 1))
        XCTAssertFalse(SharedCacheAdmission.allows(usedBytes: 101, capacityBytes: 100, incomingBytes: 0))
    }

    func testScreenshotSaveCountsHistoryAndLatestCopies() {
        XCTAssertTrue(
            SharedCacheAdmission.screenshotSaveFits(
                clipboardBytes: 10,
                historyBytes: 0,
                replacingHistoryBytes: 0,
                imageBytes: 30,
                capacityBytes: 100
            )
        )
        XCTAssertFalse(
            SharedCacheAdmission.screenshotSaveFits(
                clipboardBytes: 0,
                historyBytes: 40,
                replacingHistoryBytes: 0,
                imageBytes: 40,
                capacityBytes: 100
            )
        )
        XCTAssertTrue(
            SharedCacheAdmission.screenshotSaveFits(
                clipboardBytes: 0,
                historyBytes: 40,
                replacingHistoryBytes: 40,
                imageBytes: 40,
                capacityBytes: 100
            )
        )
        XCTAssertFalse(
            SharedCacheAdmission.screenshotSaveFits(
                clipboardBytes: 0,
                historyBytes: 200,
                replacingHistoryBytes: 0,
                imageBytes: 1,
                capacityBytes: 100
            )
        )
    }

    func testAgeCleanupRemovesOnlyOlderScreenshots() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScreenshotHistoryStore(directoryURL: directory)
        let old = try XCTUnwrap(
            store.add(data: data(10), date: Date().addingTimeInterval(-10000))
        )
        let recent = try XCTUnwrap(store.add(data: data(10), date: Date()))

        let removed = store.delete(olderThan: Date().addingTimeInterval(-100))

        XCTAssertEqual(removed, 1)
        XCTAssertEqual(store.load().map(\.id), [recent.id])
        XCTAssertFalse(store.load().contains { $0.id == old.id })

        let edited = try XCTUnwrap(
            store.add(data: data(10), date: Date().addingTimeInterval(-10000))
        )
        let refreshed = try XCTUnwrap(store.update(edited, data: data(12), date: Date()))
        XCTAssertEqual(store.delete(olderThan: Date().addingTimeInterval(-100)), 0)
        XCTAssertEqual(store.load().map(\.id).contains(refreshed.id), true)
    }

    func testLatestScreenshotOlderThanCutoffIsRemoved() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("latest-screenshot.png")
        let store = ScreenshotCacheStore(fileURL: file)
        XCTAssertTrue(store.save(data(32)))
        XCTAssertFalse(store.removeIfModified(before: Date().addingTimeInterval(-60)))
        XCTAssertEqual(store.storedBytes(), 32)

        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-3600)],
            ofItemAtPath: file.path
        )
        XCTAssertTrue(store.removeIfModified(before: Date().addingTimeInterval(-60)))
        XCTAssertEqual(store.storedBytes(), 0)
        XCTAssertFalse(store.removeIfModified(before: Date()))
    }

    /// 索引写失败时不能再留孤儿：那张 PNG 进不了索引，也永远不会被淘汰。
    func testIndexWriteFailureLeavesNoOrphanFile() throws {
        let directory = makeDirectory()
        let metadata = directory.appendingPathComponent("metadata.json")
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: metadata.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = ScreenshotHistoryStore(directoryURL: directory)
        _ = try XCTUnwrap(store.add(data: data(128)))

        // 索引文件标记成不可变：PNG 还能新建，metadata.json 写不进去。
        // （用 chmod 挡不住：原子写走的是写临时文件再 rename，不需要目标文件的写权限。）
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: metadata.path)

        let secondAdd = store.add(data: data(128))
        XCTAssertNil(secondAdd, "索引写不进去时不该报告成功")

        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: metadata.path)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".png") }
        XCTAssertEqual(files.count, 1, "失败的那张 PNG 应当被收回，而不是留在磁盘上")
    }

    /// 目录里没被索引引用的 PNG（历史遗留、索引损坏后失去引用）要在启动时清掉。
    func testOrphanedScreenshotsAreCollected() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let store = ScreenshotHistoryStore(directoryURL: directory)
        let kept = try XCTUnwrap(store.add(data: data(64)))

        let orphan = directory.appendingPathComponent("screenshot-\(UUID().uuidString).png")
        try data(64).write(to: orphan)
        // 刚写出来的文件有宽限期（可能索引还没落盘），这里把它做旧。
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-3600)],
            ofItemAtPath: orphan.path
        )

        let reloaded = ScreenshotHistoryStore(directoryURL: directory).load()

        XCTAssertEqual(reloaded.map(\.id), [kept.id], "被引用的截图必须留着")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: orphan.path),
            "没被索引引用的 PNG 应当被回收"
        )
    }
}

extension ScreenshotHistoryCapacityTests {
    /// 索引损坏时**绝不能**把截图删光。
    ///
    /// `readOrDefault` 会把「读不出来」和「还没有」都变成空数组，于是孤儿回收会
    /// 认为所有 PNG 都没人引用——那恰好把 quarantine 想保住的东西销毁掉。
    func testCorruptIndexDoesNotDeleteScreenshots() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScreenshotHistoryStore(directoryURL: directory)
        _ = try XCTUnwrap(store.add(data: data(64)))
        _ = try XCTUnwrap(store.add(data: data(64)))

        // 模拟写到一半掉电/磁盘错误留下的坏索引。
        try Data("{ 这不是 JSON".utf8)
            .write(to: directory.appendingPathComponent("metadata.json"))

        let reloaded = ScreenshotHistoryStore(directoryURL: directory)
        _ = reloaded.load()

        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(
            contents.filter { $0.hasSuffix(".png") }.count,
            2,
            "索引读不出来时不能把截图当成孤儿删掉"
        )
        XCTAssertTrue(
            contents.contains { $0.contains(".corrupt-") },
            "坏索引应当被隔离留证"
        )
    }
}
