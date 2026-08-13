import SwiftUI
import XCTest
@testable import Jarvis

final class ThemeTests: XCTestCase {
    func testThemePreferencesExposeAllDisplayModes() {
        XCTAssertEqual(
            JarvisTheme.allCases.map(\.rawValue),
            ["system", "light", "dark"]
        )
    }

    func testThemePreferencesMapToColorSchemes() {
        XCTAssertNil(JarvisTheme.system.preferredColorScheme)
        XCTAssertEqual(JarvisTheme.light.preferredColorScheme, .light)
        XCTAssertEqual(JarvisTheme.dark.preferredColorScheme, .dark)
    }
}
