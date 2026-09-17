import AppKit
@testable import Jarvis
import XCTest

/// 导出裁剪：先在整幅画布上渲染，再直接从位图上切出选区。
///
/// 这里用四象限配色验证切的是**正确的那一块**——CGImage 的坐标是左上角原点、
/// y 向下，而输出矩形是 AppKit 那套 y 向上的；方向搞反就会取到镜像位置的画面
/// （预览里是左上、导出却是左下），而尺寸断言对此毫无察觉。
@MainActor
final class ScreenshotExportCropTests: XCTestCase {
    private let canvas = CGSize(width: 200, height: 200)

    /// 左上红、右上绿、左下蓝、右下白。
    private func makeQuadrantImage() throws -> (NSImage, Data) {
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(canvas.width),
                pixelsHigh: Int(canvas.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let bitmap = try XCTUnwrap(rep.bitmapData)
        let colors: [(r: UInt8, g: UInt8, b: UInt8)] = [
            (255, 0, 0), // 左上
            (0, 255, 0), // 右上
            (0, 0, 255), // 左下
            (255, 255, 255) // 右下
        ]
        let size = Int(canvas.width)
        for y in 0 ..< size {
            for x in 0 ..< size {
                // 位图第 0 行是图像顶部。
                let quadrant = (y < size / 2 ? 0 : 2) + (x < size / 2 ? 0 : 1)
                let color = colors[quadrant]
                let offset = (y * size + x) * 4
                bitmap[offset] = color.r
                bitmap[offset + 1] = color.g
                bitmap[offset + 2] = color.b
                bitmap[offset + 3] = 255
            }
        }
        rep.size = canvas
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        return try (XCTUnwrap(NSImage(data: data)), data)
    }

    private func makeEditor() throws -> ScreenshotEditorModel {
        let (image, data) = try makeQuadrantImage()
        return ScreenshotEditorModel(
            image: image,
            data: data,
            outputData: data,
            canvasSize: canvas
        )
    }

    private func sampleTopLeft(_ png: Data) throws -> NSColor {
        let exported = try XCTUnwrap(NSBitmapImageRep(data: png))
        return try XCTUnwrap(exported.colorAt(x: 10, y: 10)?.usingColorSpace(.deviceRGB))
    }

    func testCroppedExportTakesTheSelectedRegionNotItsMirror() async throws {
        let editor = try makeEditor()
        // 画布坐标（左上角原点）里选**左上**那象限。
        editor.updateSelectionRect(CGRect(x: 0, y: 0, width: 100, height: 100))

        let rendered = await editor.renderedPNGData()
        let data = try XCTUnwrap(rendered)
        let exported = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(exported.pixelsWide, 100)
        XCTAssertEqual(exported.pixelsHigh, 100)

        let sampled = try sampleTopLeft(data)
        XCTAssertGreaterThan(sampled.redComponent, 0.8, "应当取到左上角的红色")
        XCTAssertLessThan(sampled.blueComponent, 0.2, "不该取到左下角的蓝色（镜像）")
    }

    func testCroppedExportTakesTheBottomQuadrantWhenSelected() async throws {
        let editor = try makeEditor()
        editor.updateSelectionRect(CGRect(x: 0, y: 100, width: 100, height: 100))

        let rendered = await editor.renderedPNGData()
        let data = try XCTUnwrap(rendered)
        let sampled = try sampleTopLeft(data)

        XCTAssertGreaterThan(sampled.blueComponent, 0.8, "应当取到左下角的蓝色")
        XCTAssertLessThan(sampled.redComponent, 0.2)
    }

    /// 没有选区时导出整幅，尺寸不能变。
    func testFullCanvasExportKeepsTheWholeCanvas() async throws {
        let editor = try makeEditor()

        let rendered = await editor.renderedPNGData()
        let data = try XCTUnwrap(rendered)
        let exported = try XCTUnwrap(NSBitmapImageRep(data: data))

        XCTAssertEqual(exported.pixelsWide, 200)
        XCTAssertEqual(exported.pixelsHigh, 200)
    }
}
