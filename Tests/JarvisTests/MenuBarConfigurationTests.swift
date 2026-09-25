import AppKit
@testable import Jarvis
import XCTest

@MainActor
final class MenuBarConfigurationTests: XCTestCase {
    func testApplicationUsesRegularPolicySoTheDockIconRemainsVisible() {
        XCTAssertEqual(JarvisApplicationPresentation.activationPolicy, .regular)
    }

    func testClosingLastWindowKeepsTheMenuBarApplicationRunning() {
        XCTAssertFalse(JarvisApplicationPresentation.terminateAfterLastWindowClosed)
    }

    func testConfiguredMenuItemsHaveExplicitControllerTargets() {
        let controller = JarvisMenuBarController()
        let menu = controller.configuredMenuForTesting()
        let actionableItems = menu.items.filter { !$0.isSeparatorItem }

        XCTAssertEqual(actionableItems.count, 5 + WindowLayout.allCases.count)
        for item in actionableItems {
            XCTAssertNotNil(item.action, item.title)
            XCTAssertIdentical(item.target, controller, item.title)
            XCTAssertTrue(item.isEnabled, item.title)
        }
    }

    func testWindowLayoutMenuItemsExposeTheirShortcuts() throws {
        let controller = JarvisMenuBarController()
        let menu = controller.configuredMenuForTesting()
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

    func testStatusItemUsesStableNamespacedAutosaveName() {
        let autosaveName = JarvisMenuBarController.menuBarAutosaveName

        XCTAssertEqual(
            autosaveName,
            "\(JarvisAppIdentity.bundleIdentifier).primary-status-item"
        )
    }

    func testMenuBarUsesVectorMascotIconWithAccessibleTitle() {
        let image = JarvisMenuBarController.makeMenuBarIcon()

        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, JarvisMenuBarController.menuBarIconPointSize)
        XCTAssertEqual(
            JarvisMenuBarController.menuBarTitle,
            "JARVIS"
        )
    }
}
