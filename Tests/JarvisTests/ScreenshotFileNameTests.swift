import AppKit
@testable import Jarvis
import XCTest

/// 图片落盘用的名字：只有时间戳，三个出口（保存面板、历史拖拽、剪贴板拖拽）一套。
final class ScreenshotFileNameTests: XCTestCase {
    /// 2026-09-18 12:31:00 +08:00
    private let reference = Date(timeIntervalSince1970: 1_789_705_860)

    private func timeZone(_ identifier: String) throws -> TimeZone {
        try XCTUnwrap(TimeZone(identifier: identifier))
    }

    func testTimestampedNameHasNoApplicationName() throws {
        let name = try ScreenshotFileName.timestamped(
            at: reference,
            timeZone: timeZone("Asia/Shanghai")
        )

        XCTAssertEqual(name, "20260918-123100.png")
        XCTAssertFalse(name.contains("贾维斯"), "文件名里不该再有应用名")
    }

    /// 形状固定成 `yyyyMMdd-HHmmss.png`：换时区只改数字，不改形状。
    func testNameShapeHoldsAcrossTimeZones() throws {
        for identifier in ["UTC", "Asia/Shanghai", "America/Los_Angeles"] {
            let name = try ScreenshotFileName.timestamped(
                at: reference,
                timeZone: timeZone(identifier)
            )
            XCTAssertNotNil(
                name.range(of: #"^\d{8}-\d{6}\.png$"#, options: .regularExpression),
                "\(identifier) 下得到的是 \(name)"
            )
        }
    }

    /// 名字不跟系统区域走。
    ///
    /// 灯下黑过一次：进程的当前区域在测试里换不掉（本机是公历），只断言输出形状的话，
    /// 把 `en_US_POSIX` 那行删掉测试照样绿。所以钉两头——生产用的 formatter 确实固定
    /// 在 `en_US_POSIX`，以及同一份格式串跟着区域走真的会变样（泰历的年份是 2569）。
    func testNameDoesNotFollowTheSystemLocale() throws {
        let formatter = try ScreenshotFileName.makeFormatter(
            timeZone: timeZone("Asia/Shanghai")
        )
        XCTAssertEqual(formatter.locale.identifier, "en_US_POSIX")

        let localeFollowing = DateFormatter()
        localeFollowing.locale = try XCTUnwrap(Locale(identifier: "th_TH"))
        localeFollowing.timeZone = try timeZone("Asia/Shanghai")
        localeFollowing.dateFormat = "yyyyMMdd-HHmmss"
        XCTAssertNotEqual(
            localeFollowing.string(from: reference),
            "20260918-123100",
            "跟着区域走的 formatter 应当变样；这条反例不变说明测试没在测区域"
        )
    }
}

extension ScreenshotFileNameTests {
    /// 从历史里拖到 Finder：用时间戳，不是内部那串 UUID。
    ///
    /// 两边都用生产默认的 `TimeZone.current`（不钉死某个时区，否则在 UTC 的 CI 上必红）。
    func testHistoryItemSuggestsATimestampedName() {
        let item = ScreenshotHistoryItem(
            id: UUID(),
            createdAt: reference.addingTimeInterval(-3600),
            updatedAt: reference,
            fileName: "screenshot-\(UUID().uuidString).png"
        )

        let suggested = item.suggestedFileName

        XCTAssertNotNil(
            suggested.range(of: #"^\d{8}-\d{6}\.png$"#, options: .regularExpression),
            "落盘名是 \(suggested)"
        )
        // 时间取 updatedAt（界面显示的是它，文件内容也是那一次写进去的），不是 createdAt。
        XCTAssertEqual(suggested, ScreenshotFileName.timestamped(at: reference))
        XCTAssertNotEqual(suggested, ScreenshotFileName.timestamped(at: item.createdAt))
    }

    /// 拖拽真正走的那个出口（视图 `onDrag` 里调的函数）也得给出时间戳名。
    func testHistoryDragProviderSuggestsTheTimestampedName() {
        let item = ScreenshotHistoryItem(
            id: UUID(),
            createdAt: reference.addingTimeInterval(-3600),
            updatedAt: reference,
            fileName: "screenshot-\(UUID().uuidString).png"
        )

        let provider = ScreenshotSharing.itemProvider(for: item, data: Data([0x89, 0x50, 0x4E, 0x47]))

        XCTAssertEqual(provider.suggestedName, ScreenshotFileName.timestamped(at: reference))
    }
}

extension ScreenshotFileNameTests {
    /// 剪贴板里的图片拖出去：按复制时间命名，两次不同的复制不会撞名。
    func testClipboardImageDragNameFollowsTheCopyTime() throws {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        let bitmap = try XCTUnwrap(try NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-clipboard-image-\(UUID().uuidString).png")
        try data.write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }

        var names: [String] = []
        for offset in [0.0, 90.0] {
            let item = ClipboardItem(
                createdAt: reference.addingTimeInterval(offset),
                kind: .image,
                imagePath: path.path,
                fileName: nil
            )
            let provider = ClipboardSharing.itemProvider(for: item)
            XCTAssertNotNil(provider?.suggestedName, "图片项没有给出落盘名")
            try names.append(XCTUnwrap(provider?.suggestedName))
        }

        XCTAssertNotEqual(names[0], names[1], "两次复制拖出来的名字一样，到 Finder 里会撞名")
        XCTAssertEqual(names[0], ScreenshotFileName.timestamped(at: reference))
        XCTAssertFalse(names.contains("图片.png"), "不该再是那个固定名")
    }
}
