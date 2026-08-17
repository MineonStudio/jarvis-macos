import AppKit
@testable import Jarvis
import XCTest

final class AppIconTests: XCTestCase {
    func testAppIconExposesLightAndDarkAppearances() {
        XCTAssertEqual(JarvisAppIconAppearance.allCases, [.light, .dark])
    }

    func testAppIconAppearancesUseThemeSpecificAssetNames() {
        XCTAssertEqual(JarvisAppIconAppearance.light.assetName, "JarvisIconLight")
        XCTAssertEqual(JarvisAppIconAppearance.dark.assetName, "JarvisIconDark")
    }

    func testAppIconUsesStandardDockPointSize() {
        XCTAssertEqual(JarvisAppIconRenderer.standardDockIconSize, NSSize(width: 128, height: 128))
    }
}
