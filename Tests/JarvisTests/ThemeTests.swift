@testable import Jarvis
import SwiftUI
import XCTest

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

    func testAppIconAppearanceResolvesSystemVariant() {
        XCTAssertEqual(
            JarvisAppIconAppearance.allCases.map(\.rawValue),
            ["system", "light", "dark"]
        )
        XCTAssertEqual(
            JarvisAppIconAppearance.system.resolvedVariant(isSystemDark: true),
            .dark
        )
        XCTAssertEqual(
            JarvisAppIconAppearance.system.resolvedVariant(isSystemDark: false),
            .light
        )
    }

    func testAccentColorPreferencesExposeRequestedPalette() {
        XCTAssertEqual(
            JarvisAccentColor.allCases.map(\.rawValue),
            ["system", "blue", "purple", "pink", "red", "orange", "yellow", "green", "graphite"]
        )
        XCTAssertEqual(JarvisAccentColor.system.title, "跟随系统")
        XCTAssertEqual(JarvisAccentColor.graphite.title, "石墨色")
    }
}
