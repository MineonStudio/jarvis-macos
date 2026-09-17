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

    func testTotalBytesCapEvictsOldest() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScreenshotHistoryStore(
            directoryURL: directory,
            maximumCount: 100,
            maximumTotalBytes: 3000
        )

        // 每张 1000 字节，上限 3000 → 只留三张，最早的那张被淘汰。
        var items: [ScreenshotHistoryItem] = []
        for index in 0 ..< 5 {
            let item = try XCTUnwrap(
                store.add(data: data(1000), date: Date().addingTimeInterval(TimeInterval(index)))
            )
            items.append(item)
        }

        let remaining = store.load()
        XCTAssertEqual(remaining.count, 3, "总字节上限没有生效")
        XCTAssertEqual(remaining.map(\.id), [items[4].id, items[3].id, items[2].id])

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".png") }
        XCTAssertEqual(files.count, 3, "淘汰掉的截图文件应当一并删除")
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

        let reloaded = ScreenshotHistoryStore(directoryURL: directory).load()

        XCTAssertEqual(reloaded.map(\.id), [kept.id], "被引用的截图必须留着")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: orphan.path),
            "没被索引引用的 PNG 应当被回收"
        )
    }
}
