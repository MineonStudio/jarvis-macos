@testable import Jarvis
import XCTest

/// 四个存储现在共用同一份读写实现，它自己的契约值得单独钉住：各存储的测试只覆盖
/// 自己用到的路径，这里覆盖所有存储共享的那部分。
final class JarvisJSONFileTests: XCTestCase {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-json-file-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeFile(in directory: URL) -> JarvisJSONFile<[String]> {
        JarvisJSONFile(directoryURL: directory, fileName: "items.json", logDomain: "test.items")
    }

    func testMissingFileReadsAsDefaultRatherThanFailing() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = makeFile(in: directory)
        XCTAssertEqual(file.readOrDefault([]), [])
        // 首次运行没有文件，写入应当照常进行。
        XCTAssertEqual(try file.readForWriting(default: []), [])
    }

    func testRoundTripsValues() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = makeFile(in: directory)
        XCTAssertTrue(file.write(["a", "b"]))
        XCTAssertEqual(file.readOrDefault([]), ["a", "b"])
    }

    func testWriteCarriesOwnerOnlyPermissions() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = makeFile(in: directory)
        XCTAssertTrue(file.write(["a"]))

        let attributes = try FileManager.default.attributesOfItem(atPath: file.fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    // MARK: - 版本号

    func testStaleRevisionIsDiscarded() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = makeFile(in: directory)
        XCTAssertTrue(file.write(["newer"], revision: 2))
        XCTAssertTrue(file.write(["older"], revision: 1))
        XCTAssertEqual(file.readOrDefault([]), ["newer"])
    }

    // MARK: - 写入失败

    /// `write` 的返回值很容易被丢掉，那样失败的保存会报告成功。需要告知用户的调用
    /// 方必须拿到一个抛出。
    func testWriteOrThrowSurfacesWriteFailures() throws {
        let directory = makeDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let file = makeFile(in: directory)
        // 目录只读，原子写连临时文件都建不出来。
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)

        XCTAssertFalse(file.write(["a", "b"]), "只读目录下写入不该报告成功")
        XCTAssertThrowsError(try file.writeOrThrow(["a", "b"])) { error in
            XCTAssertEqual(error as? JarvisJSONFileError, .writeFailed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.fileURL.path))
    }

    // MARK: - 损坏

    /// 读不出来时必须留证据，否则紧接着的一次写入会把损坏内容连同用户数据一起覆盖。
    func testUnreadableContentIsQuarantinedAndPreserved() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let file = makeFile(in: directory)
        let corrupt = Data("{ not json".utf8)
        try corrupt.write(to: file.fileURL)

        XCTAssertEqual(file.readOrDefault([]), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.fileURL.path))

        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        let quarantined = try XCTUnwrap(
            entries.first { $0.lastPathComponent.hasPrefix("items.corrupt-") },
            "损坏内容没有被留证"
        )
        XCTAssertEqual(try Data(contentsOf: quarantined), corrupt)
        // 留证之后原路径腾空，写入可以正常继续。
        XCTAssertEqual(try file.readForWriting(default: []), [])
    }

    /// 挪不动损坏文件时必须拒绝写入：照常写下去就是把它整份覆盖掉。
    func testWriteIsRefusedWhenUnreadableContentCannotBeQuarantined() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let corrupt = Data("{ not json".utf8)
        let fileURL = directory.appendingPathComponent("items.json")
        try corrupt.write(to: fileURL)

        let file = JarvisJSONFile<[String]>(
            directoryURL: directory,
            fileName: "items.json",
            logDomain: "test.items",
            fileManager: MoveFailingFileManager()
        )

        XCTAssertThrowsError(try file.readForWriting(default: [])) { error in
            XCTAssertEqual(error as? JarvisJSONFileError, .unreadable)
        }
        // 原文件原样留着，现场没丢。
        XCTAssertEqual(try Data(contentsOf: fileURL), corrupt)
    }
}

/// 让损坏内容的留证动作必定失败，用来验证「拒绝写入」那条分支。
final class MoveFailingFileManager: FileManager {
    override func moveItem(at _: URL, to _: URL) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}
