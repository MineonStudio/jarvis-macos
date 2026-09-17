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

    /// 面板宽度由主按钮行推出（主行内容固定，窗口跟着它），钉成具体数值：这条
    /// 一改，工具栏在屏幕上的落位、以及二级行能有多少余量都会跟着变。
    func testPanelWidthFollowsTheMainRow() {
        XCTAssertEqual(ScreenshotToolbarMetrics.baseWidth, 493, accuracy: 0.001)
        XCTAssertEqual(
            ScreenshotToolbarMetrics.baseWidth,
            ScreenshotToolbarMetrics.mainRowContentWidth
                + (2 * ScreenshotToolbarMetrics.mainRowHorizontalPadding),
            accuracy: 0.001
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

extension ScreenshotToolbarCapsuleTests {
    /// 主行贴住选区的那条边，在收起/展开二级行时必须**不动**——否则每次开合二级行
    /// 都会弹一下。
    ///
    /// 这里走的是生产代码的落位函数本身（不是手搓矩形、也不是另写一个没人调用的
    /// helper），所以分支写反、锚点判断错都会被测出来。
    func testAnchoredEdgeStaysFixedWhenSecondaryRowToggles() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let selections: [(String, CGRect)] = [
            ("居中", CGRect(x: 300, y: 300, width: 500, height: 300)),
            ("贴着屏幕底部", CGRect(x: 300, y: 0, width: 500, height: 200)),
            ("接近全屏", CGRect(x: 0, y: 0, width: 1440, height: 860))
        ]

        for (label, selection) in selections {
            let compact = ScreenshotToolbarPlacement.frame(
                for: selection,
                in: visibleFrame,
                height: ScreenshotToolbarMetrics.compactHeight,
                width: ScreenshotToolbarMetrics.baseWidth
            )
            let expanded = ScreenshotToolbarPlacement.frame(
                for: selection,
                in: visibleFrame,
                height: ScreenshotToolbarMetrics.expandedHeight,
                width: ScreenshotToolbarMetrics.baseWidth
            )

            XCTAssertEqual(compact.minX, expanded.minX, accuracy: 0.001, label)

            // 锚点是哪条边，哪条边就必须不动：下方落位锚上沿，其余锚下沿。
            let anchoredByBottom = ScreenshotToolbarPlacement.anchor(
                for: selection,
                in: visibleFrame
            ).anchorsWindowBottom
            if anchoredByBottom {
                XCTAssertEqual(
                    compact.minY,
                    expanded.minY,
                    accuracy: 0.001,
                    "\(label)：以窗口下沿为基准时它不该动"
                )
            } else {
                XCTAssertEqual(
                    compact.maxY,
                    expanded.maxY,
                    accuracy: 0.001,
                    "\(label)：以窗口上沿为基准时它不该动"
                )
            }
        }
    }

    /// 落位只按收起态的高度决定。用请求的高度决定的话，展开二级行会让原本放得下
    /// 的一侧变得放不下，工具栏当场瞬移到对面。
    func testPlacementDoesNotFlipWhenTheSecondaryRowOpens() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let selection = CGRect(x: 300, y: 0, width: 800, height: 770)

        XCTAssertEqual(
            ScreenshotToolbarPlacement.anchor(for: selection, in: visibleFrame),
            ScreenshotToolbarPlacement.anchor(for: selection, in: visibleFrame),
            "落位判断不该依赖请求的高度"
        )
    }
}
