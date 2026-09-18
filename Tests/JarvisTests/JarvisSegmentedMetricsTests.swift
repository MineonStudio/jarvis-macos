import AppKit
@testable import Jarvis
import SwiftUI
import XCTest

/// 组合容器的几何：**容器四边留等宽内边距，选中项填满这一圈以内，形状是胶囊**。
///
/// 这条规则曾经在同一个 app 里有五种口径（2 / 3 / 8 / 11 / 20，还有一个干脆没有），
/// 截图工具栏二级行横向留 20、纵向留 7 就是其中最显眼的一处：选中药丸从行胶囊的
/// 圆头上歪出来。这里把内边距的唯一来源钉住，并且真的渲染一次量一遍。
final class JarvisSegmentedMetricsTests: XCTestCase {
    /// 内边距由容器高度和选项高度反推，四边同值。
    func testPaddingIsHalfTheHeightDifference() {
        XCTAssertEqual(
            JarvisSegmentedMetrics.padding(containerHeight: 40, itemHeight: 26),
            7,
            accuracy: 0.001
        )
        XCTAssertEqual(
            JarvisSegmentedMetrics.padding(containerHeight: 64, itemHeight: 42),
            11,
            accuracy: 0.001
        )
        // 选项比容器还高时不给出负数（那会让内边距变成反向出血）。
        XCTAssertEqual(JarvisSegmentedMetrics.padding(containerHeight: 26, itemHeight: 40), 0)
    }

    /// 每个容器用的横向内边距，必须就是那条公式算出来的数——不能是手写的第二套。
    func testEveryContainerTakesItsInsetFromTheFormula() {
        XCTAssertEqual(
            ScreenshotToolbarMetrics.mainRowHorizontalPadding,
            JarvisSegmentedMetrics.padding(
                containerHeight: ScreenshotToolbarMetrics.mainRowHeight,
                itemHeight: ScreenshotToolbarMetrics.mainButtonSize
            ),
            accuracy: 0.001,
            "截图工具栏主行的左右内缩和上下内缩对不上，选中胶囊不会与行胶囊同心"
        )
        XCTAssertEqual(
            ScreenshotToolbarMetrics.secondaryRowHorizontalPadding,
            JarvisSegmentedMetrics.padding(
                containerHeight: ScreenshotToolbarMetrics.secondaryRowHeight,
                itemHeight: ScreenshotToolbarMetrics.secondaryControlHeight
            ),
            accuracy: 0.001,
            "截图工具栏二级行的左右内缩和上下内缩对不上"
        )
        XCTAssertEqual(
            JarvisSegmentedMetrics.toolbarGroupPadding,
            JarvisSegmentedMetrics.padding(
                containerHeight: JarvisToolbarMetrics.controlSize,
                itemHeight: JarvisSegmentedMetrics.compactItemHeight
            ),
            accuracy: 0.001
        )
    }

    /// 等宽之外还有一条下限：内容不能给自绘胶囊的圆头切掉。
    ///
    /// 只对**我们自己画成胶囊**的容器成立。窗口工具栏里的成组控件不算——那圈的形状是
    /// 系统给的分组底（圆角远小于半高），拿胶囊的下限去卡它会得出一个虚高的数（32 高
    /// 的容器装 26 高的选项，胶囊下限是 6.7，而实际需要的只是 3）。
    func testInsetsClearTheCapsTheyAreDrawnWith() {
        let rows: [(String, CGFloat, CGFloat, CGFloat)] = [
            (
                "截图工具栏主行",
                ScreenshotToolbarMetrics.mainRowHeight,
                ScreenshotToolbarMetrics.mainButtonSize,
                ScreenshotToolbarMetrics.mainRowHorizontalPadding
            ),
            (
                "截图工具栏二级行",
                ScreenshotToolbarMetrics.secondaryRowHeight,
                ScreenshotToolbarMetrics.secondaryControlHeight,
                ScreenshotToolbarMetrics.secondaryRowHorizontalPadding
            )
        ]

        for (label, containerHeight, itemHeight, inset) in rows {
            let minimum = ScreenshotToolbarMetrics.minimumCapsuleInset(
                rowHeight: containerHeight,
                contentHeight: itemHeight
            )
            XCTAssertGreaterThanOrEqual(inset, minimum, "\(label)：内缩不够，内容会被圆头切到")
        }
    }
}

extension JarvisSegmentedMetricsTests {
    /// 真渲染一次：选中胶囊到容器左 / 上 / 下三条边的距离必须一样。
    ///
    /// 算术断言只能保证"我们用的是同一个数"，量像素才能发现"那个数没有真的落到视图上"
    /// （被别的 modifier 吃掉、或者两条边各走各的布局）。分组选择器是这条规则最干净的
    /// 样本：容器是它自己的一圈留白，选中态是一枚实心胶囊。
    @MainActor
    func testSelectedPillIsInsetEquallyOnEverySide() throws {
        let canvas = CGSize(width: 360, height: 44)
        // 用显式的 sRGB 灰：`NSColor.systemGray` 经 `Color(nsColor:)` 渲染出来会
        // 亮一档还带一点蓝，按它去找容器会很脆。
        let containerGray: CGFloat = 0.5
        let containerColor = Color(red: containerGray, green: containerGray, blue: containerGray)
        /// 选**第一项**：只有它贴着容器左边，左内缩才和上/下同义（第 2 项以后的左边
        /// 是前一项，量出来的不是容器内边距——参考图里也是第一项选中）。
        func render(selected: EntertainmentPlatform) throws -> NSBitmapImageRep {
            let content = ZStack {
                Color.white
                // 标题留空：选中项的字体是 semibold、未选中是 medium，带文字时
                // 容器宽度会跟着两张图不一样，diff 里就混进了容器边缘。这里只量几何。
                // 用 `toolbarContainer`（不带玻璃那一层）：离屏渲染看不到 glass。
                JarvisToolbarGroupedPicker(
                    items: EntertainmentPlatform.allCases,
                    selection: .constant(selected),
                    title: { _ in "" },
                    icon: { _, _ in Color.clear.frame(width: 16, height: 16) }
                )
                .toolbarContainer
                .background(containerColor, in: Capsule())
            }
            .frame(width: canvas.width, height: canvas.height)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            return try NSBitmapImageRep(cgImage: XCTUnwrap(renderer.cgImage))
        }

        let first = try render(selected: .x)
        let last = try render(selected: .twitch)
        let scale = CGFloat(first.pixelsWide) / canvas.width

        // 选中色是**用户的**系统强调色（`selectionPillTint` = accentColor），不能按
        // 颜色去找它——pink / graphite 这些设置下蓝色判定根本匹配不到。改量"两张图
        // 哪里不一样"：唯一变化的就是那枚会挪位置的选中胶囊。
        let container = try XCTUnwrap(
            // 认"中性灰"而不是认某个具体值：`Color(red:0.5…)` 经渲染落在 0.57
            // （色彩空间转换），钉死数值会很脆；灰的三通道相等且不是纯白，够用了。
            bounds(of: first) { _, color in
                guard let rgb = color.usingColorSpace(.deviceRGB) else { return false }
                let r = rgb.redComponent, g = rgb.greenComponent, b = rgb.blueComponent
                return abs(r - g) < 0.03 && abs(g - b) < 0.03 && r > 0.3 && r < 0.85
            },
            "没找到容器底色"
        )
        let moved = try XCTUnwrap(
            bounds(of: first) { index, _ in
                first.pixelColor(atFlat: index) != last.pixelColor(atFlat: index)
            },
            "两张图完全一样，选中胶囊没画出来"
        )
        // 变化横跨两处（第一项和最后一项），只取左半边的那个 = 第一项的胶囊。
        let pillLeftHalf = try XCTUnwrap(
            bounds(of: first) { index, _ in
                let x = index % first.pixelsWide
                return x < first.pixelsWide / 2
                    && first.pixelColor(atFlat: index) != last.pixelColor(atFlat: index)
            },
            "左边那枚胶囊没找着"
        )

        let left = (pillLeftHalf.minX - container.minX) / scale
        let top = (pillLeftHalf.minY - container.minY) / scale
        let bottom = (container.maxY - pillLeftHalf.maxY) / scale

        XCTAssertEqual(left, top, accuracy: 1, "左内缩 \(left) 与上内缩 \(top) 不一致")
        XCTAssertEqual(left, bottom, accuracy: 1, "左内缩 \(left) 与下内缩 \(bottom) 不一致")
        XCTAssertEqual(left, JarvisSegmentedMetrics.toolbarGroupPadding, accuracy: 1, "内缩不是公式给的那个数")
        XCTAssertEqual(
            pillLeftHalf.height / scale,
            JarvisSegmentedMetrics.compactItemHeight,
            accuracy: 1.5,
            "选中胶囊的高度不对"
        )
        XCTAssertGreaterThan(moved.width, pillLeftHalf.width, "另一枚胶囊没跟着动")
    }

    /// 满足条件的像素包围盒（画布坐标）。
    private func bounds(
        of rep: NSBitmapImageRep,
        matching: (_ flatIndex: Int, _ color: NSColor) -> Bool
    ) -> CGRect? {
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                let index = y * rep.pixelsWide + x
                guard let color = rep.colorAt(x: x, y: y), matching(index, color) else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX <= maxX else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

private extension NSBitmapImageRep {
    func pixelColor(atFlat index: Int) -> UInt32? {
        let x = index % pixelsWide
        let y = index / pixelsWide
        return colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)?.rgbPacked
    }
}

private extension NSColor {
    /// 三通道打包成一个整数，用来比较"这一像素变没变"。
    var rgbPacked: UInt32 {
        let r = UInt32((redComponent * 255).rounded())
        let g = UInt32((greenComponent * 255).rounded())
        let b = UInt32((blueComponent * 255).rounded())
        return (r << 16) | (g << 8) | b
    }
}
