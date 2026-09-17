@testable import Jarvis
import XCTest

/// 「保存」不结束编辑会话，所以要记住这次落在历史里的哪一条；「完成」「贴图」
/// 结束会话，清空即可。
///
/// 原来收官函数无条件清空 `editingHistoryID`：新截图第一次保存时它本来就是空的，
/// 于是点保存（新增一条）之后再点完成（又新增一条），历史里多出一模一样的两条。
final class ScreenshotHistorySessionTests: XCTestCase {
    private let existingID = UUID()
    private let createdID = UUID()

    func testSavingKeepsTheSessionAndRemembersTheEntry() {
        XCTAssertEqual(
            AppModel.editingHistoryIDAfterFinalize(
                endsSession: false,
                resolvedID: createdID,
                current: nil
            ),
            createdID,
            "新截图保存后应当记住刚创建的那条，否则下次保存会再新增"
        )
        XCTAssertEqual(
            AppModel.editingHistoryIDAfterFinalize(
                endsSession: false,
                resolvedID: existingID,
                current: existingID
            ),
            existingID,
            "更新已有条目时应当保持指向它"
        )
    }

    func testFinishingClearsTheSession() {
        XCTAssertNil(
            AppModel.editingHistoryIDAfterFinalize(
                endsSession: true,
                resolvedID: existingID,
                current: existingID
            )
        )
    }

    /// 落盘失败（resolvedID 为 nil）时不要把手上的 id 弄丢。
    func testFailedWriteKeepsTheCurrentEntry() {
        XCTAssertEqual(
            AppModel.editingHistoryIDAfterFinalize(
                endsSession: false,
                resolvedID: nil,
                current: existingID
            ),
            existingID
        )
        XCTAssertNil(
            AppModel.editingHistoryIDAfterFinalize(
                endsSession: false,
                resolvedID: nil,
                current: nil
            )
        )
    }
}
