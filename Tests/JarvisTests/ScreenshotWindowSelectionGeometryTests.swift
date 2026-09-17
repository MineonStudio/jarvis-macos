import CoreGraphics
@testable import Jarvis
import XCTest

/// 窗口命中的坐标换算。
///
/// 输入是 Quartz 全局坐标（原点是**主屏**左上角、y 向下），输出是覆盖层的视图坐标
/// （原点在该屏左下角、y 向上）。翻转基准必须是主屏高度——取「最高那块屏」的高度
/// 会在有屏排到主屏上方时整体平移，主屏上的高亮全部落空。
final class ScreenshotWindowSelectionGeometryTests: XCTestCase {
    private let mainHeight: CGFloat = 1080
    private let screenWidth: CGFloat = 1920
    private let screenHeight: CGFloat = 1080

    /// 屏的 Quartz 顶边（y 向下，主屏顶边为 0）。
    private func quartzTop(appKitMinY: CGFloat) -> CGFloat {
        mainHeight - (appKitMinY + screenHeight)
    }

    /// 该屏局部坐标（y 向上，原点在屏左下角）里,一个「从屏顶往下 top..top+height」的
    /// 窗口应当落在哪里。
    private func expectedLocalRect(
        quartzMinX: CGFloat,
        distanceFromScreenTop: CGFloat,
        size: CGSize
    ) -> CGRect {
        CGRect(
            x: quartzMinX,
            y: screenHeight - distanceFromScreenTop - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func localRect(
        quartzRect: CGRect,
        appKitMinY: CGFloat
    ) -> CGRect {
        WindowSelectionDetector.localRect(
            for: quartzRect,
            screenFrame: CGRect(x: 0, y: appKitMinY, width: screenWidth, height: screenHeight),
            desktopTop: mainHeight,
            screenBounds: CGRect(x: 0, y: 0, width: screenWidth, height: screenHeight)
        )
    }

    func testWindowOnMainScreenMapsToItsOwnLocalCoordinates() {
        let size = CGSize(width: 400, height: 300)
        let quartz = CGRect(
            x: 100,
            y: 300,
            width: size.width,
            height: size.height
        )

        XCTAssertEqual(
            localRect(quartzRect: quartz, appKitMinY: 0),
            expectedLocalRect(quartzMinX: 100, distanceFromScreenTop: 300, size: size)
        )
    }

    /// 副屏排在主屏**上方**——出问题的那个排布。
    func testWindowOnScreenAboveTheMainScreenMapsCorrectly() {
        let size = CGSize(width: 400, height: 300)
        let appKitMinY: CGFloat = 1080
        let quartz = CGRect(
            x: 100,
            y: quartzTop(appKitMinY: appKitMinY) + 300,
            width: size.width,
            height: size.height
        )

        XCTAssertEqual(
            localRect(quartzRect: quartz, appKitMinY: appKitMinY),
            expectedLocalRect(quartzMinX: 100, distanceFromScreenTop: 300, size: size)
        )
    }

    func testWindowOnScreenBelowTheMainScreenMapsCorrectly() {
        let size = CGSize(width: 400, height: 300)
        let appKitMinY: CGFloat = -1080
        let quartz = CGRect(
            x: 100,
            y: quartzTop(appKitMinY: appKitMinY) + 300,
            width: size.width,
            height: size.height
        )

        XCTAssertEqual(
            localRect(quartzRect: quartz, appKitMinY: appKitMinY),
            expectedLocalRect(quartzMinX: 100, distanceFromScreenTop: 300, size: size)
        )
    }

    /// 不变量：同一块屏上「从屏顶往下同样的距离」，在哪种排布下都要落到同一个
    /// 局部位置。这条正是被「取最高屏」破坏掉的性质。
    func testSameOffsetFromScreenTopLandsAtTheSameLocalPositionForEveryArrangement() {
        let size = CGSize(width: 400, height: 300)
        let results = [0, 1080, -1080].map { appKitMinY in
            localRect(
                quartzRect: CGRect(
                    x: 100,
                    y: quartzTop(appKitMinY: appKitMinY) + 300,
                    width: size.width,
                    height: size.height
                ),
                appKitMinY: CGFloat(appKitMinY)
            )
        }

        XCTAssertTrue(
            results.dropFirst().allSatisfy { $0 == results[0] },
            "不同排布下同一相对位置映射出了不同的局部矩形：\(results)"
        )
    }
}

extension ScreenshotWindowSelectionGeometryTests {
    /// 用 AppKit 侧的主屏高度交叉验证 Quartz 基准。
    ///
    /// AppKit 里主屏（带菜单栏那块）的 origin 恒为 (0,0)，它的 frame.height 就是
    /// 主屏高度；而 Quartz 的翻转基准必须等于这个值。如果有人改回「取所有屏里最高
    /// 那块」（`screens.map(\.frame.maxY).max()`），只要有一块屏排到主屏上方，这条
    /// 就会失败。
    func testQuartzDesktopTopMatchesTheMainScreenHeight() throws {
        let mainScreen = try XCTUnwrap(
            NSScreen.screens.first { $0.frame.origin == .zero },
            "找不到主屏"
        )
        XCTAssertEqual(
            WindowSelectionDetector.quartzDesktopTop,
            mainScreen.frame.height,
            accuracy: 0.5
        )
    }
}
