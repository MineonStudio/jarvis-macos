import AppKit
@testable import Jarvis
import SwiftUI
import XCTest

/// 一级编辑栏的 SF Symbol 共用一个字号，墨迹必须落在画框里。
///
/// 字号一致时笔画粗细一致，叉、勾不会比箭头更粗，图钉也不会被单独缩小。
/// 新符号不用再量墨迹、登记字号；装不进画框时这组测试会失败。
@MainActor
final class ScreenshotToolbarIconTests: XCTestCase {
    /// 允许的偏差：半像素级。再大肉眼就能看出高低不齐。
    private let tolerance: CGFloat = 1.0

    private let symbols = [
        "arrow.up.right",
        "rectangle",
        "pencil.tip",
        "translate",
        "arrow.uturn.backward",
        "arrow.uturn.forward",
        "square.and.arrow.down",
        "pin",
        "xmark",
        "checkmark"
    ]

    func testSymbolsShareOnePointSize() {
        for symbol in symbols {
            XCTAssertEqual(
                ScreenshotToolbarIconMetrics.pointSize(for: symbol),
                ScreenshotToolbarIconMetrics.symbolPointSize,
                "\(symbol) 不该再单独调字号"
            )
        }
    }

    func testSymbolInkFitsInTheSharedBox() throws {
        for symbol in symbols {
            let box = try inkBox(of: symbolImage(symbol))
            XCTAssertLessThanOrEqual(
                box.width,
                ScreenshotToolbarIconMetrics.box,
                "\(symbol) 的墨迹宽度超出画框，会被裁"
            )
            XCTAssertLessThanOrEqual(
                box.height,
                ScreenshotToolbarIconMetrics.box,
                "\(symbol) 的墨迹高度超出画框，会被裁"
            )
            XCTAssertGreaterThan(box.height, 8, "\(symbol) 没有画出来")
        }
    }

    private func symbolImage(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(
                .system(
                    size: ScreenshotToolbarIconMetrics.pointSize(for: symbol),
                    weight: .medium
                )
            )
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

        let translation = try inkBox(of: ScreenshotTranslationIcon(isSelected: false))
        XCTAssertLessThanOrEqual(translation.width, ScreenshotToolbarIconMetrics.box)
        XCTAssertLessThanOrEqual(translation.height, ScreenshotToolbarIconMetrics.box)
        XCTAssertGreaterThan(translation.height, 8, "翻译图标没有画出来")
    }

    // MARK: - 测量

    private func inkHeight(of content: some View) throws -> CGFloat {
        try inkBox(of: content).height
    }

    private func inkBox(of content: some View) throws -> CGSize {
        let scale: CGFloat = 4
        // 画框放得比图标大，裁切之前先量到真实墨迹。装在 24pt 框里再量的话，
        // 被切掉的部分量不出来，超框测试会一律通过。
        let renderer = ImageRenderer(
            content: content
                .foregroundStyle(Color.black)
                .frame(width: 80, height: 80)
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
