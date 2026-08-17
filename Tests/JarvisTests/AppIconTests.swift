import AppKit
@testable import Jarvis
import XCTest

final class AppIconTests: XCTestCase {
    func testAppIconExposesLightAndDarkAppearances() {
        XCTAssertEqual(JarvisAppIconAppearance.allCases, [.light, .dark])
    }

    func testAppIconAppearancesUseThemeSpecificAssetNames() {
        XCTAssertEqual(JarvisAppIconAppearance.light.iconResourceName, "AppIcon")
        XCTAssertEqual(JarvisAppIconAppearance.dark.iconResourceName, "AppIconDark")
    }
}
