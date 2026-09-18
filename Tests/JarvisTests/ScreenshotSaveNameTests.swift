import Foundation
@testable import Jarvis
import XCTest

/// 保存截图时的默认文件名：只有时间戳，没有「贾维斯-」前缀。
final class ScreenshotSaveNameTests: XCTestCase {
    /// 2026-09-18 12:31:00 +08:00
    private let reference = Date(timeIntervalSince1970: 1_789_705_860)

    private func timeZone(_ identifier: String) throws -> TimeZone {
        try XCTUnwrap(TimeZone(identifier: identifier))
    }

    func testDefaultNameIsJustTheTimestamp() throws {
        let name = try ScreenshotSaveName.defaultName(
            at: reference,
            timeZone: timeZone("Asia/Shanghai")
        )

        XCTAssertEqual(name, "20260918-123100.png")
        XCTAssertFalse(name.contains("贾维斯"), "文件名里不该再有应用名")
    }

    /// 形状固定成 `yyyyMMdd-HHmmss.png`：换时区只改数字，不改形状。
    func testNameShapeHoldsAcrossTimeZones() throws {
        for identifier in ["UTC", "Asia/Shanghai", "America/Los_Angeles"] {
            let name = try ScreenshotSaveName.defaultName(
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
        let formatter = try ScreenshotSaveName.makeFormatter(
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
