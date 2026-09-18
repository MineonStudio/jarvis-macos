import AppKit
@testable import Jarvis
import XCTest

/// 网页模块那圈圆角是画在网页视图**上面**的一层（`JarvisWebPlatformCornerCoverView`），
/// 因为给 WKWebView 加遮罩会让打字卡顿、硬件视频层闪烁（见 `JarvisWebPlatformViews`
/// 里的说明）。
///
/// 这层原来只填四个角的三角区，填色又是面板底色：浅色模式下页面和面板都是白的，
/// 圆角就完全看不出来，面板像个直角矩形。描边是让它"看得出圆角"的那一笔。
@MainActor
final class JarvisWebPlatformCornerCoverTests: XCTestCase {
    private func coverPixels(_ appearance: NSAppearance) throws -> NSBitmapImageRep {
        let cover = JarvisWebPlatformCornerCoverView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
        cover.cornerRadius = JarvisMetrics.panelRadius
        cover.appearance = appearance
        let rep = try XCTUnwrap(cover.bitmapImageRepForCachingDisplay(in: cover.bounds))
        cover.cacheDisplay(in: cover.bounds, to: rep)
        return rep
    }

    func testCoverDrawsARoundedOutline() throws {
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            let rep = try coverPixels(appearance)
            // 角落最外一格是纯填色（三角区），拿它当基准。
            let fill = try XCTUnwrap(rep.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))

            // 沿对角线往里扫：不透明像素里出现"和填色不同"的，就是那圈描边。
            var outlinePixels = 0
            for step in 0 ..< 48 {
                guard let color = rep.colorAt(x: step, y: step)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.15
                else {
                    continue // 圆角以内是透空的（露出网页），不算
                }
                let differs = abs(color.redComponent - fill.redComponent) > 0.01
                    || abs(color.greenComponent - fill.greenComponent) > 0.01
                    || abs(color.blueComponent - fill.blueComponent) > 0.01
                if differs {
                    outlinePixels += 1
                }
            }

            XCTAssertGreaterThan(outlinePixels, 0, "\(appearanceName.rawValue)：圆角上没有描边，浅色模式下看不出圆角")
            XCTAssertLessThan(outlinePixels, 20, "\(appearanceName.rawValue)：描边过粗，像是把整个角都涂了")
        }
    }

    /// 角落那圈得带上面板的投影，不能只是一块平色。
    ///
    /// 面板的阴影在 `JarvisFloatingPanelModifier` 里画在网页视图底下、被盖住了；
    /// 别的模块（截图、壁纸、会议……）的圆角处能看见这层浅投影，这两个模块要是没有，
    /// 边角就对不上。判据：越靠近圆角（越靠近面板本体）越暗。
    func testCornerCarriesThePanelShadow() throws {
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            let rep = try coverPixels(appearance)
            // 视图不是 flipped，缓存位图第 0 行是顶部：左上角 = 矩形角，往里走靠近圆弧。
            let atCorner = try XCTUnwrap(rep.colorAt(x: 2, y: 2)?.usingColorSpace(.deviceRGB))
            let nearArc = try XCTUnwrap(rep.colorAt(x: 13, y: 13)?.usingColorSpace(.deviceRGB))

            XCTAssertGreaterThan(
                atCorner.brightness,
                nearArc.brightness + 0.005,
                "\(appearanceName.rawValue)：角落没有投影的渐变，像是只填了平色"
            )
        }
    }

    /// 圆角半径沿用面板的：和 `jarvisModulePanel()` / `jarvisFloatingPanel` 一致。
    func testDefaultCornerRadiusMatchesThePanel() {
        let cover = JarvisWebPlatformCornerCoverView(frame: .zero)

        XCTAssertEqual(cover.cornerRadius, JarvisMetrics.panelRadius, accuracy: 0.001)
    }
}

private extension NSColor {
    var brightness: CGFloat {
        guard let rgb = usingColorSpace(.deviceRGB) else { return 0 }
        return (rgb.redComponent + rgb.greenComponent + rgb.blueComponent) / 3
    }
}
