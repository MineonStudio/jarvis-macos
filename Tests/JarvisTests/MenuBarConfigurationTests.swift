import AppKit
@testable import Jarvis
import XCTest

final class MenuBarConfigurationTests: XCTestCase {
    func testApplicationUsesRegularPolicySoTheDockIconRemainsVisible() {
        XCTAssertEqual(JarvisApplicationPresentation.activationPolicy, .regular)
    }

    func testConfiguredMenuItemsHaveExplicitControllerTargets() async {
        let controller = await JarvisMenuBarController()
        let menu = await controller.configuredMenuForTesting()
        let actionableItems = menu.items.filter { !$0.isSeparatorItem }

        XCTAssertEqual(actionableItems.count, 4 + WindowLayout.allCases.count)
        for item in actionableItems {
            XCTAssertNotNil(item.action, item.title)
            XCTAssertIdentical(item.target, controller, item.title)
            XCTAssertTrue(item.isEnabled, item.title)
        }
    }

    func testWindowLayoutMenuItemsExposeTheirShortcuts() async throws {
        let controller = await JarvisMenuBarController()
        let menu = await controller.configuredMenuForTesting()
        let layoutTitles = Set(WindowLayout.allCases.map(\.title))
        let layoutItems = menu.items.filter { layoutTitles.contains($0.title) }

        XCTAssertEqual(layoutItems.count, WindowLayout.allCases.count)

        let itemsByTitle = Dictionary(uniqueKeysWithValues: layoutItems.map { ($0.title, $0) })
        for layout in WindowLayout.allCases {
            let item = try XCTUnwrap(itemsByTitle[layout.title])
            XCTAssertEqual(item.keyEquivalent, layout.menuKeyEquivalent, layout.title)
            XCTAssertEqual(
                item.keyEquivalentModifierMask,
                WindowLayout.menuShortcutModifierFlags,
                layout.title
            )
        }
    }

    func testStatusItemUsesStableNamespacedAutosaveName() async {
        let autosaveName = await JarvisMenuBarController.menuBarAutosaveName

        XCTAssertEqual(
            autosaveName,
            "\(JarvisAppIdentity.bundleIdentifier).primary-status-item"
        )
    }

    @MainActor
    func testMenuBarUsesConfiguredIconResourceWithAccessibleTitle() {
        XCTAssertEqual(JarvisMenuBarController.menuBarIconResourceName, "JarvisMenuBarIcon")
        XCTAssertEqual(JarvisMenuBarController.menuBarIconFileExtension, "png")
        XCTAssertEqual(
            JarvisMenuBarController.menuBarIconPointSize,
            NSSize(width: 18, height: 18)
        )
        XCTAssertEqual(JarvisMenuBarController.menuBarTitle, "JARVIS")
    }
}
