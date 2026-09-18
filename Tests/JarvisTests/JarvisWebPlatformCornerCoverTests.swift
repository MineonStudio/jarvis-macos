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
    /// 把一个 64×64 的圆角盖板画进一张 1x 离屏位图。
    ///
    /// 两个坑：
    /// - 不走 `cacheDisplay`：这个视图是 layer-backed 的，没挂窗口时缓存出来可能是
    ///   空的（本地碰巧过得去，CI 上暗色那一轮就什么都没画）。
    /// - 位图固定 1x（`rep.size` 就是像素数）：采样落在确定的像素网格上，不随机器的
    ///   屏幕缩放变，判据里的计数才有可比性。
    private func coverPixels(_ appearance: NSAppearance) throws -> NSBitmapImageRep {
        let size = NSSize(width: 64, height: 64)
        let cover = JarvisWebPlatformCornerCoverView(frame: NSRect(origin: .zero, size: size))
        cover.cornerRadius = JarvisMetrics.panelRadius
        cover.appearance = appearance
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 64,
            pixelsHigh: 64,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        cover.draw(cover.bounds)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    func testCoverDrawsARoundedOutline() throws {
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            let rep = try coverPixels(appearance)
            // 角落最外一格是纯填色（三角区），拿它当基准。
            let fill = try XCTUnwrap(rep.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))

            // 在圆角那一块里找"和填色反差很大"的像素：描边用的是 `labelColor`
            // （浅色下近黑、深色下近白），而填色自己的抗锯齿边缘只会保持填色本身，
            // 所以反差大的只可能是描边。
            //
            // 原来沿对角线逐点扫是量不到的：描边在 45° 上只覆盖采样点的一小部分，
            // 整像素不透明度约 0.016，被"不透明"那道门槛滤掉；真正被判成描边的是
            // 填色自己的边缘像素——它和角落填色的差在浅色下勉强过线、深色下没有，
            // 于是同一条测试在 CI 的暗色那轮报 0。
            var outlinePixels = 0
            for y in 0 ..< 24 {
                for x in 0 ..< 24 {
                    guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                          color.alphaComponent > 0.02
                    else {
                        continue // 圆角以内是透空的（露出网页），不算
                    }
                    let difference = max(
                        max(
                            abs(color.redComponent - fill.redComponent),
                            abs(color.greenComponent - fill.greenComponent)
                        ),
                        abs(color.blueComponent - fill.blueComponent)
                    )
                    if difference > 0.3 {
                        outlinePixels += 1
                    }
                }
            }

            XCTAssertGreaterThan(outlinePixels, 0, "\(appearanceName.rawValue)：圆角上没有描边，浅色模式下看不出圆角")
            XCTAssertLessThan(outlinePixels, 80, "\(appearanceName.rawValue)：描边过粗，像是把整个角都涂了")
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
