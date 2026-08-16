import AppKit
@testable import Jarvis
import XCTest

final class AppIconTests: XCTestCase {
    func testAppIconColorsFollowRainbowOrder() {
        XCTAssertEqual(
            JarvisAppIconColor.allCases,
            [.red, .orange, .yellow, .green, .cyan, .blue, .purple]
        )
        XCTAssertEqual(
            JarvisAppIconColor.allCases.map(\.title),
            ["红色", "橙色", "黄色", "绿色", "青色", "蓝色", "紫色"]
        )
    }

    func testTintOnlyChangesDarkPixels() {
        let source = NSImage(size: NSSize(width: 2, height: 1))
        source.lockFocus()
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        NSColor.white.setFill()
        NSRect(x: 1, y: 0, width: 1, height: 1).fill()
        source.unlockFocus()

        var proposedRect = NSRect(origin: .zero, size: source.size)
        guard let tinted = JarvisAppIconRenderer.tintedImage(source, color: .red),
              let cgImage = tinted.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
              let providerData = cgImage.dataProvider?.data
        else {
            XCTFail("Expected a rendered tinted icon")
            return
        }

        let bitmapData = providerData as Data
        let pixels = [UInt8](bitmapData)
        let hasRedPixel = stride(from: 0, to: pixels.count, by: 4).contains { offset in
            pixels[offset] == 224 && pixels[offset + 1] == 31 && pixels[offset + 2] == 41
        }
        let hasWhitePixel = stride(from: 0, to: pixels.count, by: 4).contains { offset in
            pixels[offset] == 255 && pixels[offset + 1] == 255 && pixels[offset + 2] == 255
        }
        XCTAssertTrue(hasRedPixel)
        XCTAssertTrue(hasWhitePixel)
    }
}
