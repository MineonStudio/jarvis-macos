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

    func testStatusItemUsesStableNamespacedAutosaveName() async {
        let autosaveName = await JarvisMenuBarController.menuBarAutosaveName

        XCTAssertEqual(autosaveName, "com.jarvis.mac.primary-status-item")
    }

    @MainActor
    func testMenuBarUsesTemplateIconResourceWithAccessibleTitle() {
        XCTAssertEqual(JarvisMenuBarController.menuBarIconResourceName, "JarvisMenuBarIcon")
        XCTAssertEqual(JarvisMenuBarController.menuBarIconFileExtension, "png")
        XCTAssertEqual(JarvisMenuBarController.menuBarIconTintColor, .white)
        XCTAssertEqual(JarvisMenuBarController.menuBarTitle, "JARVIS")
    }
}
