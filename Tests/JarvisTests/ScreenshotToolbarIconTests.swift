import AppKit
@testable import Jarvis
import SwiftUI
import XCTest

/// 一级编辑栏的图标必须**看起来**一样大。
///
/// 光把字号写成同一个数做不到这一点：21pt 下 `arrow.up.right` 的墨迹只有 15.5pt，
/// `square.and.arrow.down` 有 22.25pt，并排一行参差不齐。所以这里把每个图标真实
/// 渲染出来量墨迹包围盒，钉住「墨迹高度一致」这个可见结果，而不是字号这个中间量。
@MainActor
final class ScreenshotToolbarIconTests: XCTestCase {
    /// 允许的偏差：半像素级。再大肉眼就能看出高低不齐。
    private let tolerance: CGFloat = 1.0

    func testSymbolIconsShareTheSameInkHeight() throws {
        let symbols = [
            "arrow.up.right",
            "rectangle",
            "character.bubble",
            "arrow.uturn.backward",
            "arrow.uturn.forward",
            "square.and.arrow.down",
            "xmark",
            "checkmark"
        ]

        for symbol in symbols {
            let inkHeight = try inkHeight(
                of: Image(systemName: symbol)
                    .font(
                        .system(
                            size: ScreenshotToolbarIconMetrics.pointSize(for: symbol),
                            weight: .medium
                        )
                    )
            )
            XCTAssertEqual(
                inkHeight,
                ScreenshotToolbarIconMetrics.targetInkHeight,
                accuracy: tolerance,
                "\(symbol) 的墨迹高度是 \(inkHeight)pt，与同排其它图标不一致"
            )
        }
    }

    func testCustomIconsMatchTheSymbols() throws {
        let mosaic = try inkHeight(of: MosaicToolIcon(color: .black))
        XCTAssertEqual(
            mosaic,
            ScreenshotToolbarIconMetrics.targetInkHeight,
            accuracy: tolerance,
            "马赛克自绘图标与同排符号不一致"
        )

        let text = try inkHeight(
            of: Text("T")
                .font(
                    .system(
                        size: ScreenshotToolbarIconMetrics.textPointSize,
                        weight: .regular,
                        design: .serif
                    )
                )
        )
        XCTAssertEqual(
            text,
            ScreenshotToolbarIconMetrics.targetInkHeight,
            accuracy: tolerance,
            "文字工具的 T 与同排符号不一致"
        )

        let translation = try inkHeight(of: ScreenshotTranslationIcon(isSelected: false))
        XCTAssertEqual(
            translation,
            ScreenshotToolbarIconMetrics.targetInkHeight,
            accuracy: tolerance,
            "翻译图标与同排符号不一致"
        )
    }

    /// 图标不能被画框裁掉：墨迹宽度和高度都得留得住。
    func testIconsFitInsideTheirBox() throws {
        for symbol in ["arrow.up.right", "rectangle", "character.bubble", "square.and.arrow.down"] {
            let box = try inkBox(
                of: Image(systemName: symbol)
                    .font(
                        .system(
                            size: ScreenshotToolbarIconMetrics.pointSize(for: symbol),
                            weight: .medium
                        )
                    )
            )
            XCTAssertLessThanOrEqual(
                box.width,
                ScreenshotToolbarIconMetrics.box,
                "\(symbol) 的墨迹宽度超出画框，会被裁"
            )
            XCTAssertLessThanOrEqual(box.height, ScreenshotToolbarIconMetrics.box, symbol)
        }
    }

    // MARK: - 测量

    private func inkHeight(of content: some View) throws -> CGFloat {
        try inkBox(of: content).height
    }

    private func inkBox(of content: some View) throws -> CGSize {
        let scale: CGFloat = 4
        let renderer = ImageRenderer(
            content: content
                .foregroundStyle(Color.black)
                .frame(
                    width: ScreenshotToolbarIconMetrics.box,
                    height: ScreenshotToolbarIconMetrics.box
                )
        )
        renderer.scale = scale
        let cgImage = try XCTUnwrap(renderer.cgImage, "离屏渲染失败")
        let rep = NSBitmapImageRep(cgImage: cgImage)

        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.08 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX <= maxX else { return .zero }
        return CGSize(
            width: CGFloat(maxX - minX + 1) / scale,
            height: CGFloat(maxY - minY + 1) / scale
        )
    }
}
