import AppKit
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

    func testAccentPresetsMatchSystemSettingsSwatches() {
        assertSwatch(.blue, light: "0091FF", dark: "0091FF")
        assertSwatch(.purple, light: "A756A7", dark: "B669B6")
        assertSwatch(.pink, light: "FB6BAE", dark: "FB6BAE")
        assertSwatch(.red, light: "E8504F", dark: "FF6B6A")
        assertSwatch(.orange, light: "FA9521", dark: "FA9521")
        assertSwatch(.yellow, light: "FFCF30", dark: "FFCF00")
        assertSwatch(.green, light: "72C358", dark: "72C358")
        assertSwatch(.graphite, light: "A8A8A8", dark: "9E9E9E")
        XCTAssertNotEqual(
            Self.hex(JarvisAccentColor.graphite.nsColor, appearance: .aqua),
            Self.hex(NSColor.systemGray, appearance: .aqua)
        )
    }

    private func assertSwatch(
        _ accent: JarvisAccentColor,
        light: String,
        dark: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(Self.hex(accent.nsColor, appearance: .aqua), light, file: file, line: line)
        XCTAssertEqual(Self.hex(accent.nsColor, appearance: .darkAqua), dark, file: file, line: line)
    }

    private static func hex(_ color: NSColor, appearance name: NSAppearance.Name) -> String {
        guard let appearance = NSAppearance(named: name) else { return "" }
        var text = ""
        appearance.performAsCurrentDrawingAppearance {
            let resolved = color.usingColorSpace(.sRGB) ?? color
            let red = Int((resolved.redComponent * 255).rounded())
            let green = Int((resolved.greenComponent * 255).rounded())
            let blue = Int((resolved.blueComponent * 255).rounded())
            text = String(format: "%02X%02X%02X", red, green, blue)
        }
        return text
    }
}
