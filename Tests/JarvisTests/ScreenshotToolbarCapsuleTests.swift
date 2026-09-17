@testable import Jarvis
import XCTest

/// 胶囊形状把内容裁掉是「看起来没坏、只是图标缺一角」的那种问题，改内缩或行高时
/// 很容易踩到。这里把那两端的圆头换算成约束钉住：行高决定半径，内缩必须让最外侧
/// 控件的角落在圆头里。
final class ScreenshotToolbarCapsuleTests: XCTestCase {
    /// 行高 h 的胶囊，两端的圆头半径是 h/2，左上圆头的圆心在 (h/2, h/2)。
    private func isInsideCap(x: CGFloat, y: CGFloat, rowHeight: CGFloat) -> Bool {
        let radius = rowHeight / 2
        let dx = x - radius
        let dy = y - radius
        return (dx * dx + dy * dy) <= radius * radius
    }

    func testMainRowButtonsStayInsideTheCapsuleCaps() {
        let rowHeight = ScreenshotToolbarMetrics.mainRowHeight
        let buttonSize = ScreenshotToolbarMetrics.mainButtonSize
        let inset = ScreenshotToolbarMetrics.mainRowHorizontalPadding
        let top = (rowHeight - buttonSize) / 2

        // 最左边按钮的左上角与最右边按钮的右下角是离圆头最近的四个点里最危险的两个。
        XCTAssertTrue(
            isInsideCap(x: inset, y: top, rowHeight: rowHeight),
            "左侧按钮的角落在胶囊外面：内缩 \(inset) 太小，行高 \(rowHeight) 需要更大的内缩"
        )
        XCTAssertTrue(
            isInsideCap(x: inset, y: top + buttonSize, rowHeight: rowHeight),
            "左侧按钮的角落在胶囊外面"
        )
        XCTAssertTrue(
            isInsideCap(x: inset + buttonSize, y: top, rowHeight: rowHeight),
            "按钮内侧的角也不该越出圆头"
        )
    }

    func testSecondaryRowContentStaysInsideTheCapsuleCaps() {
        let rowHeight = ScreenshotToolbarMetrics.secondaryRowHeight
        let inset = ScreenshotToolbarMetrics.secondaryRowHorizontalPadding
        let contentHeight = ScreenshotToolbarMetrics.secondaryContentHeight
        let top = (rowHeight - contentHeight) / 2

        XCTAssertTrue(
            isInsideCap(x: inset, y: top, rowHeight: rowHeight),
            "二级控件的角落在胶囊外面：内缩 \(inset) 太小"
        )
        XCTAssertTrue(
            isInsideCap(x: inset, y: top + contentHeight, rowHeight: rowHeight),
            "二级控件的角落在胶囊外面"
        )
    }

    /// 上下两块之间要留缝，否则贴在一起看起来还是一条被切开的整块。
    func testPillsAreSeparatedAndAccountedForInHeight() {
        XCTAssertGreaterThan(ScreenshotToolbarMetrics.pillSpacing, 0)
        XCTAssertEqual(
            ScreenshotToolbarMetrics.compactHeight,
            ScreenshotToolbarMetrics.mainRowHeight + ScreenshotToolbarMetrics.pillBottomPadding,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ScreenshotToolbarMetrics.expandedHeight,
            ScreenshotToolbarMetrics.mainRowHeight
                + ScreenshotToolbarMetrics.pillSpacing
                + ScreenshotToolbarMetrics.secondaryRowHeight
                + ScreenshotToolbarMetrics.pillBottomPadding,
            accuracy: 0.001
        )
    }
}
