import AppKit
import Foundation
@testable import Jarvis
import XCTest

final class AppIconTests: XCTestCase {
    func testAppIconExposesLightAndDarkAppearances() {
        XCTAssertEqual(JarvisAppIconAppearance.allCases, [.light, .dark])
    }

    func testDarkAppearanceInvertsTheLightIconPixels() {
        let sourcePixels: [UInt8] = [
            0, 0, 0, 255,
            255, 255, 255, 255
        ]
        guard let provider = CGDataProvider(data: Data(sourcePixels) as CFData),
              let sourceCGImage = CGImage(
                  width: 2,
                  height: 1,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: 8,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else {
            XCTFail("Expected a source icon")
            return
        }
        let source = NSImage(cgImage: sourceCGImage, size: NSSize(width: 2, height: 1))

        guard let darkImage = JarvisAppIconRenderer.renderedImage(source, appearance: .dark),
              let darkCGImage = darkImage.cgImage(
                  forProposedRect: nil,
                  context: nil,
                  hints: nil
              ),
              let data = darkCGImage.dataProvider?.data
        else {
            XCTFail("Expected a rendered dark icon")
            return
        }

        XCTAssertEqual([UInt8](data as Data), [255, 255, 255, 255, 0, 0, 0, 255])
    }
}
