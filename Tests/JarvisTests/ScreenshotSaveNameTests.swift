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

    /// 形状固定成 `yyyyMMdd-HHmmss.png`：只跟本地时区变，不跟系统区域变。
    func testNameShapeDoesNotDependOnTheSystemLocale() throws {
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
}
