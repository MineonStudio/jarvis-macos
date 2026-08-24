import AppKit
@testable import Jarvis
import XCTest

final class ScreenshotCoordinateSpaceTests: XCTestCase {
    func testScreenshotCacheRoundTrip() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-cache-test-\(UUID().uuidString).png")
        let cache = ScreenshotCacheStore(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let data = Data([0x89, 0x50, 0x4E, 0x47])
        XCTAssertNil(cache.load())

        cache.save(data)
        XCTAssertEqual(cache.load(), data)

        cache.clear()
        XCTAssertNil(cache.load())
    }

    func testScreenshotHistorySupportsUpdateAndDelete() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-history-test-(UUID().uuidString)", isDirectory: true)
        let history = ScreenshotHistoryStore(directoryURL: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstData = Data([1, 2, 3])
        let secondData = Data([4, 5, 6])
        let firstDate = Date(timeIntervalSince1970: 100)
        let secondDate = Date(timeIntervalSince1970: 200)

        guard let first = history.add(data: firstData, date: firstDate),
              let second = history.add(data: secondData, date: secondDate)
        else {
            XCTFail("Unable to create screenshot history")
            return
        }
        XCTAssertEqual(history.load().map(\.id), [second.id, first.id])
        XCTAssertEqual(history.data(for: first), firstData)
        XCTAssertEqual(history.fileSize(for: first), Int64(firstData.count))

        let editedData = Data([7, 8, 9])
        let edited = history.update(first, data: editedData, date: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(edited?.id, first.id)
        XCTAssertEqual(history.data(for: first), editedData)
        XCTAssertEqual(history.load().first?.id, first.id)

        history.delete(second)
        XCTAssertEqual(history.load().map(\.id), [first.id])
    }

    func testCanvasAndOutputRectRoundTrip() {
        let space = ScreenshotCoordinateSpace(
            screenFrame: CGRect(x: 20, y: 30, width: 1440, height: 900),
            canvasSize: CGSize(width: 1440, height: 900)
        )
        let canvasRect = CGRect(x: 120, y: 180, width: 480, height: 260)

        let outputRect = space.outputRect(fromCanvasRect: canvasRect)
        let restored = space.canvasRect(fromOutputRect: outputRect)

        XCTAssertEqual(restored.minX, canvasRect.minX, accuracy: 0.001)
        XCTAssertEqual(restored.minY, canvasRect.minY, accuracy: 0.001)
        XCTAssertEqual(restored.width, canvasRect.width, accuracy: 0.001)
        XCTAssertEqual(restored.height, canvasRect.height, accuracy: 0.001)
        XCTAssertEqual(
            space.screenRect(fromOutputRect: outputRect),
            CGRect(x: 140, y: 490, width: 480, height: 260)
        )
    }

    func testPixelGeometryPreservesRetinaScale() {
        let geometry = ScreenshotPixelGeometry(
            canvasSize: CGSize(width: 1000, height: 800),
            pixelSize: CGSize(width: 2000, height: 1600)
        )
        let canvasRect = CGRect(x: 100, y: 120, width: 300, height: 240)

        XCTAssertEqual(
            geometry.pixelRect(fromCanvasRect: canvasRect),
            CGRect(x: 200, y: 240, width: 600, height: 480)
        )
        XCTAssertEqual(
            geometry.pixelSize(forCanvasRect: canvasRect),
            CGSize(width: 600, height: 480)
        )
    }

    func testSmallSelectionIsRejectedAndValidSelectionIsClamped() {
        let space = ScreenshotCoordinateSpace(
            screenFrame: .zero,
            canvasSize: CGSize(width: 800, height: 600)
        )

        XCTAssertNil(space.clampedCanvasRect(CGRect(x: 0, y: 0, width: 10, height: 30)))
        XCTAssertEqual(
            space.clampedCanvasRect(CGRect(x: -20, y: -10, width: 200, height: 180)),
            CGRect(x: 0, y: 0, width: 180, height: 170)
        )
    }
}

extension ScreenshotCoordinateSpaceTests {
    func testRenderPipelineProducesPNGForAnnotation() {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 160,
            pixelsHigh: 120,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            XCTFail("Unable to create test bitmap")
            return
        }
        bitmap.size = CGSize(width: 160, height: 120)
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        let annotation = ScreenshotAnnotation(
            kind: .arrow,
            points: [CGPoint(x: 20, y: 20), CGPoint(x: 130, y: 90)],
            text: nil,
            brushSize: 5,
            color: .red,
            lineWidth: 5,
            arrowHeadSize: 20,
            arrowHeadStyle: .filled
        )

        let data = ScreenshotRenderPipeline().renderFullCanvas(.init(
            image: image,
            canvasSize: image.size,
            pixelScale: 1,
            annotations: [annotation],
            blurredImage: nil,
            pixelatedImage: nil
        ))

        XCTAssertNotNil(data)
        XCTAssertEqual(data?.prefix(8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }

    func testRectangleAnnotationSupportsDefaultAndDashedStyles() {
        XCTAssertEqual(ScreenshotLineStyle.solid.dashPattern, [])
        XCTAssertEqual(ScreenshotLineStyle.dashed.dashPattern, [10, 6])

        let annotation = ScreenshotAnnotation(
            kind: .rectangle,
            points: [CGPoint(x: 20, y: 20), CGPoint(x: 130, y: 90)],
            text: nil,
            brushSize: 5,
            color: .red,
            lineWidth: 5,
            lineStyle: .dashed
        )
        XCTAssertEqual(annotation.lineWidth, 5)
        XCTAssertEqual(annotation.color, .red)
        XCTAssertEqual(annotation.lineStyle, .dashed)

        let image = NSImage(size: CGSize(width: 160, height: 120))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 160, height: 120).fill()
        image.unlockFocus()
        let data = ScreenshotRenderPipeline().renderFullCanvas(.init(
            image: image,
            canvasSize: image.size,
            pixelScale: 1,
            annotations: [annotation],
            blurredImage: nil,
            pixelatedImage: nil
        ))
        XCTAssertNotNil(data)
    }

    func testRenderedCanvasAndDirectCropUseTheSameSelectionCoordinates() throws {
        let canvasSize = CGSize(width: 100, height: 80)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 100,
            pixelsHigh: 80,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            XCTFail("Unable to create test bitmap")
            return
        }
        bitmap.size = canvasSize
        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            XCTFail("Unable to create test graphics context")
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 100, height: 40)).fill()
        NSColor.systemRed.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 40, width: 100, height: 40)).fill()
        graphicsContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: canvasSize)
        image.addRepresentation(bitmap)
        guard let sourceData = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Unable to encode test bitmap")
            return
        }
        let selection = CGRect(x: 20, y: 8, width: 50, height: 24)
        let service = ScreenshotService()
        let direct = try service.crop(
            ScreenshotCapture(data: sourceData, screenFrame: CGRect(origin: .zero, size: canvasSize)),
            to: selection,
            on: CGRect(origin: .zero, size: canvasSize)
        )
        guard let renderedData = ScreenshotRenderPipeline().renderFullCanvas(.init(
            image: image,
            canvasSize: canvasSize,
            pixelScale: 1,
            annotations: [],
            blurredImage: nil,
            pixelatedImage: nil
        )) else {
            XCTFail("Unable to render test canvas")
            return
        }
        let renderedCrop = try service.crop(
            ScreenshotCapture(data: renderedData, screenFrame: CGRect(origin: .zero, size: canvasSize)),
            to: selection,
            on: CGRect(origin: .zero, size: canvasSize)
        )

        XCTAssertEqual(colorAtPNGData(direct.data, x: 25, y: 12), colorAtPNGData(renderedCrop.data, x: 25, y: 12))
    }

    func testRetinaCropUsesLogicalSourceRect() throws {
        let canvasSize = CGSize(width: 100, height: 80)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 200,
            pixelsHigh: 160,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            XCTFail("Unable to create Retina test bitmap")
            return
        }
        bitmap.size = canvasSize
        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            XCTFail("Unable to create Retina test graphics context")
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 100, height: 40)).fill()
        NSColor.systemRed.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 40, width: 100, height: 40)).fill()
        graphicsContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let sourceData = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Unable to encode Retina test bitmap")
            return
        }
        let selection = CGRect(x: 20, y: 24, width: 50, height: 8)
        let cropped = try ScreenshotService().crop(
            ScreenshotCapture(data: sourceData, screenFrame: CGRect(origin: .zero, size: canvasSize)),
            to: selection,
            on: CGRect(origin: .zero, size: canvasSize)
        )

        guard let representation = NSBitmapImageRep(data: cropped.data),
              let color = representation.colorAt(x: representation.pixelsWide / 2, y: representation.pixelsHigh / 2),
              let rgb = color.usingColorSpace(.deviceRGB)
        else {
            XCTFail("Unable to inspect Retina crop")
            return
        }
        XCTAssertGreaterThan(rgb.blueComponent, 0.7)
        XCTAssertLessThan(rgb.redComponent, 0.3)
        XCTAssertEqual(representation.pixelsWide, 100)
        XCTAssertEqual(representation.pixelsHigh, 16)
    }

    func testEditedRetinaExportKeepsTheSelectedRegionAligned() throws {
        let canvasSize = CGSize(width: 100, height: 80)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 200,
            pixelsHigh: 160,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            XCTFail("Unable to create edited Retina bitmap")
            return
        }
        bitmap.size = canvasSize
        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            XCTFail("Unable to create edited Retina graphics context")
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 100, height: 40)).fill()
        NSColor.systemRed.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 40, width: 100, height: 40)).fill()
        graphicsContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: canvasSize)
        image.addRepresentation(bitmap)
        let annotation = ScreenshotAnnotation(
            kind: .arrow,
            points: [CGPoint(x: 10, y: 8), CGPoint(x: 80, y: 16)],
            text: nil,
            brushSize: 5,
            color: .red,
            lineWidth: 5,
            arrowHeadSize: 20,
            arrowHeadStyle: .filled
        )
        guard let renderedData = ScreenshotRenderPipeline().renderFullCanvas(.init(
            image: image,
            canvasSize: canvasSize,
            pixelScale: 2,
            annotations: [annotation],
            blurredImage: nil,
            pixelatedImage: nil
        )) else {
            XCTFail("Unable to render edited Retina canvas")
            return
        }

        let selection = CGRect(x: 20, y: 24, width: 50, height: 8)
        let cropped = try ScreenshotService().crop(
            ScreenshotCapture(data: renderedData, screenFrame: CGRect(origin: .zero, size: canvasSize)),
            to: selection,
            on: CGRect(origin: .zero, size: canvasSize)
        )
        guard let representation = NSBitmapImageRep(data: cropped.data),
              let color = representation.colorAt(x: representation.pixelsWide / 2, y: representation.pixelsHigh / 2),
              let rgb = color.usingColorSpace(.deviceRGB)
        else {
            XCTFail("Unable to inspect edited Retina crop")
            return
        }
        XCTAssertGreaterThan(rgb.blueComponent, 0.7)
        XCTAssertLessThan(rgb.redComponent, 0.3)
        XCTAssertEqual(representation.pixelsWide, 100)
        XCTAssertEqual(representation.pixelsHigh, 16)
    }

    private func colorAtPNGData(_ data: Data, x: Int, y: Int) -> NSColor? {
        guard let representation = NSBitmapImageRep(data: data),
              let color = representation.colorAt(x: x, y: y)
        else {
            return nil
        }
        return color.usingColorSpace(.deviceRGB)
    }
}
