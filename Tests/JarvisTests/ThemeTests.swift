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

    func testSystemThemeResolvesToTheCurrentSystemScheme() {
        XCTAssertEqual(JarvisTheme.system.resolvedColorScheme(system: .dark), .dark)
        XCTAssertEqual(JarvisTheme.system.resolvedColorScheme(system: .light), .light)
        XCTAssertEqual(JarvisTheme.light.resolvedColorScheme(system: .dark), .light)
        XCTAssertEqual(JarvisTheme.dark.resolvedColorScheme(system: .light), .dark)
    }
}
