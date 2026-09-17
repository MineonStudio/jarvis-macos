@testable import Jarvis
import XCTest

/// 胶囊把内容裁掉是「看起来没坏、只是图标缺一角」的那种问题，改行高或内缩时很容易
/// 踩到，而且只有肉眼能发现。这里把几何关系钉住。
///
/// 左右两端不必各测一遍：内缩是一个 `.horizontal` 常量（没有分侧的常量），两端到
/// 各自圆头圆心的距离按对称性天然相等——真正会失效的是「内缩 < 圆头需要的下限」，
/// 那一条才是要钉的。
final class ScreenshotToolbarCapsuleTests: XCTestCase {
    private struct RowGeometry {
        let label: String
        let rowHeight: CGFloat
        let contentHeight: CGFloat
        let inset: CGFloat
    }

    private var rows: [RowGeometry] {
        [
            RowGeometry(
                label: "主按钮行",
                rowHeight: ScreenshotToolbarMetrics.mainRowHeight,
                contentHeight: ScreenshotToolbarMetrics.mainButtonSize,
                inset: ScreenshotToolbarMetrics.mainRowHorizontalPadding
            ),
            RowGeometry(
                label: "二级行",
                rowHeight: ScreenshotToolbarMetrics.secondaryRowHeight,
                contentHeight: ScreenshotToolbarMetrics.secondaryControlHeight,
                inset: ScreenshotToolbarMetrics.secondaryRowHorizontalPadding
            )
        ]
    }

    /// 圆头下限本身是个纯几何量：半径 r = 行高/2，内容角点到圆头圆心的距离不能超过 r。
    func testMinimumCapsuleInsetMatchesTheCircleGeometry() {
        // 64 高的胶囊（r=32）装 42 高的按钮：32 - √(32² - 21²) ≈ 7.86
        XCTAssertEqual(
            ScreenshotToolbarMetrics.minimumCapsuleInset(rowHeight: 64, contentHeight: 42),
            32 - (32 * 32 - 21 * 21).squareRoot(),
            accuracy: 0.001
        )
        // 内容与行等高时退化成分半径。
        XCTAssertEqual(
            ScreenshotToolbarMetrics.minimumCapsuleInset(rowHeight: 40, contentHeight: 40),
            20,
            accuracy: 0.001
        )
        // 内容比行还高（会被裁）时不能给出负数下限。
        XCTAssertGreaterThanOrEqual(
            ScreenshotToolbarMetrics.minimumCapsuleInset(rowHeight: 40, contentHeight: 80),
            0
        )
    }

    func testRowInsetsClearTheCapsuleCaps() {
        for row in rows {
            XCTAssertGreaterThanOrEqual(
                row.inset,
                ScreenshotToolbarMetrics.minimumCapsuleInset(
                    rowHeight: row.rowHeight,
                    contentHeight: row.contentHeight
                ),
                "\(row.label)的内缩小于圆头需要的下限，最外侧控件会被切角"
            )
        }
    }

    /// 内缩不只有下限：内容加上两侧内缩必须装得进面板的固定宽度，否则会被压扁。
    /// 这条同时把内缩的**上界**写进代码——只看「内缩够不够大」会让内缩一路加大到
    /// 把内容挤出面板。
    func testRowInsetsAlsoStayWithinThePanelWidth() {
        XCTAssertLessThanOrEqual(
            ScreenshotToolbarMetrics.mainRowContentWidth
                + (2 * ScreenshotToolbarMetrics.mainRowHorizontalPadding),
            ScreenshotToolbarMetrics.baseWidth,
            "主按钮行加内缩装不进面板宽度"
        )
    }

    func testRowContentFitsItsRow() {
        for row in rows {
            XCTAssertLessThanOrEqual(
                row.contentHeight,
                row.rowHeight,
                "\(row.label)的内容比行还高"
            )
        }
    }

    /// 这两个高度是交给面板窗口的尺寸，必须钉成具体数值：用公式互相验算等于什么也没验
    /// （两边同时改就一起漂），而窗口比内容矮一截会把胶囊顶边切掉。
    func testHeightsHandedToThePanelArePinned() {
        XCTAssertEqual(ScreenshotToolbarMetrics.mainRowHeight, 64, accuracy: 0.001)
        XCTAssertEqual(ScreenshotToolbarMetrics.secondaryRowHeight, 40, accuracy: 0.001)
        XCTAssertEqual(ScreenshotToolbarMetrics.pillSpacing, 6, accuracy: 0.001)
        XCTAssertEqual(ScreenshotToolbarMetrics.compactHeight, 64, accuracy: 0.001)
        XCTAssertEqual(ScreenshotToolbarMetrics.expandedHeight, 110, accuracy: 0.001)
    }

    /// 胶囊铺满窗口：窗口高度必须等于两条胶囊加中间那道缝，否则多出来的部分是
    /// 看得见截图却点不动的死区。
    func testWindowHeightLeavesNoDeadBand() {
        XCTAssertEqual(
            ScreenshotToolbarMetrics.expandedHeight,
            ScreenshotToolbarMetrics.compactHeight
                + ScreenshotToolbarMetrics.pillSpacing
                + ScreenshotToolbarMetrics.secondaryRowHeight,
            accuracy: 0.001
        )
    }
}
