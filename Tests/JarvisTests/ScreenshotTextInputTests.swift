import AppKit
@testable import Jarvis
import XCTest

/// 文本输入控件是自己搭的 `NSTextView` 子类。
///
/// 它崩过一次：`NSTextView` 的 `init(frame:)` 内部会调 `init(frame:textContainer:)`，
/// 而子类当时只写了自定义的 `init()`、没接上那两个指定初始化器——AppKit 一调就撞上
/// Swift 生成的「未实现」thunk（EXC_BREAKPOINT）。所以第一条测试就是让它真的被
/// 构造出来。
@MainActor
final class ScreenshotTextInputTests: XCTestCase {
    func testInputViewCanBeCreatedThroughEveryEntryPoint() {
        let byFrame = ScreenshotTextInputTextView(frame: NSRect(x: 0, y: 0, width: 80, height: 20))
        XCTAssertNotNil(byFrame.textContainer)

        // AppKit 内部走的就是这一条。
        let container = NSTextContainer(size: NSSize(width: 80, height: 20))
        let byContainer = ScreenshotTextInputTextView(frame: .zero, textContainer: container)
        XCTAssertNotNil(byContainer.textContainer)
    }

    /// 内边距归零是这个控件的存在意义：文字起点就是视图原点，光标才会和确认后的
    /// 文字落在同一处。
    func testInputViewHasZeroInsetsAndNoScrolling() {
        let view = ScreenshotTextInputTextView(frame: NSRect(x: 0, y: 0, width: 80, height: 20))

        XCTAssertEqual(view.textContainerInset, .zero)
        XCTAssertEqual(view.textContainer?.lineFragmentPadding, 0)
        XCTAssertEqual(view.textContainer?.maximumNumberOfLines, 1)
        XCTAssertFalse(view.isVerticallyResizable)
        XCTAssertFalse(view.drawsBackground)
    }

    /// 回车是确认，不是插入换行。
    func testEnterCommitsInsteadOfInsertingANewline() {
        let view = ScreenshotTextInputTextView(frame: .zero)
        var didCommit = false
        view.onCommit = { didCommit = true }

        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertTrue(didCommit, "回车应当走到确认，而不是插入换行")
    }
}
