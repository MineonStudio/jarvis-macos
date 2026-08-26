import AppKit
@testable import Jarvis
import XCTest

final class MenuBarConfigurationTests: XCTestCase {
    func testConfiguredMenuItemsHaveExplicitControllerTargets() async {
        let controller = await JarvisMenuBarController()
        let menu = await controller.configuredMenuForTesting()
        let actionableItems = menu.items.filter { !$0.isSeparatorItem }

        XCTAssertFalse(actionableItems.isEmpty)
        for item in actionableItems {
            XCTAssertNotNil(item.action, item.title)
            XCTAssertIdentical(item.target, controller, item.title)
        }
    }

    func testStatusItemUsesStableNamespacedAutosaveName() async {
        let autosaveName = await JarvisMenuBarController.menuBarAutosaveName

        XCTAssertEqual(autosaveName, "com.jarvis.mac.primary-status-item")
        let preferredPosition = await JarvisMenuBarController.menuBarPreferredPosition
        XCTAssertGreaterThan(preferredPosition, 400)
    }

    func testTitleImageIsATemplateSoTheMenuBarCanInvertIt() {
        let image = JarvisMenuBarTitleImage.make()

        XCTAssertTrue(image.isTemplate)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        XCTAssertFalse(image.representations.isEmpty)
    }

    func testTitleImageMatchesTheMenuBarLabelAndUsesMenuSizedType() {
        let image = JarvisMenuBarTitleImage.make(title: JarvisMenuBarTitleImage.title)
        let expectedWidth =
            ceil(
                (JarvisMenuBarTitleImage.title as NSString).size(
                    withAttributes: [.font: JarvisMenuBarTitleImage.font]
                ).width
            ) + JarvisMenuBarTitleImage.horizontalPadding * 2

        XCTAssertEqual(JarvisMenuBarTitleImage.title, "JARVIS")
        XCTAssertEqual(JarvisMenuBarTitleImage.font.pointSize, 13)
        XCTAssertEqual(image.size.width, expectedWidth)
        XCTAssertGreaterThanOrEqual(image.size.height, NSStatusBar.system.thickness)
    }

    func testMenuOpensFromTheBottomOfAnUnflippedStatusItem() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 60, height: 24))

        XCTAssertFalse(view.isFlipped)
        XCTAssertEqual(JarvisMenuBarTitleImage.menuOrigin(in: view), .zero)
    }

    func testMenuOpensFromTheBottomOfAFlippedStatusItem() {
        let view = FlippedStubView(frame: NSRect(x: 0, y: 0, width: 60, height: 24))

        XCTAssertEqual(
            JarvisMenuBarTitleImage.menuOrigin(in: view),
            NSPoint(x: 0, y: 24)
        )
    }

    func testExtraTintFollowsTheViewAppearanceNotAFixedColor() {
        let view = NSView(frame: .zero)
        view.appearance = NSAppearance(named: .darkAqua)
        XCTAssertEqual(JarvisMenuBarTitleImage.tintColor(for: view), .white)

        view.appearance = NSAppearance(named: .aqua)
        XCTAssertEqual(JarvisMenuBarTitleImage.tintColor(for: view), .black)
    }

    func testControlCenterRepairRemovesJarvisFromDisallowedChatGPTRecord() {
        var entries: [Any] = [
            ["bundle": ["_0": "com.openai.codex"]],
            [
                "location": ["bundle": ["_0": "com.openai.codex"]],
                "menuItemLocations": [
                    ["bundle": ["_0": "com.openai.codex"]],
                    ["bundle": ["_0": "com.jarvis.mac"]]
                ],
                "isAllowed": false
            ],
            ["bundle": ["_0": "com.jarvis.mac"]],
            [
                "location": ["bundle": ["_0": "com.jarvis.mac"]],
                "menuItemLocations": [
                    ["bundle": ["_0": "com.jarvis.mac"]]
                ],
                "isAllowed": true
            ]
        ]

        let result = JarvisControlCenterMenuBarRepair.repairTrackedApplications(&entries)

        XCTAssertEqual(result.removedForeignReferences, 1)
        XCTAssertFalse(result.forcedAllowed)
        XCTAssertTrue(result.didChange)

        let chatgpt = entries[1] as? [String: Any]
        let chatgptLocations = chatgpt?["menuItemLocations"] as? [Any]
        XCTAssertEqual(chatgptLocations?.count, 1)
        XCTAssertEqual(
            JarvisControlCenterMenuBarRepair.bundleIdentifier(from: chatgptLocations?.first),
            "com.openai.codex"
        )

        let jarvis = entries[3] as? [String: Any]
        let jarvisLocations = jarvis?["menuItemLocations"] as? [Any]
        XCTAssertEqual(jarvisLocations?.count, 1)
        XCTAssertEqual(
            JarvisControlCenterMenuBarRepair.bundleIdentifier(from: jarvisLocations?.first),
            "com.jarvis.mac"
        )
        XCTAssertEqual(jarvis?["isAllowed"] as? Bool, true)
    }

    func testControlCenterRepairForcesJarvisAllowedAndLeavesUnrelatedEntries() {
        var entries: [Any] = [
            ["bundle": ["_0": "com.tencent.xinWeChat"]],
            [
                "location": ["bundle": ["_0": "com.tencent.xinWeChat"]],
                "menuItemLocations": [
                    ["bundle": ["_0": "com.tencent.xinWeChat"]]
                ],
                "isAllowed": false
            ],
            ["bundle": ["_0": "com.jarvis.mac"]],
            [
                "location": ["bundle": ["_0": "com.jarvis.mac"]],
                "menuItemLocations": [
                    ["bundle": ["_0": "com.jarvis.mac"]]
                ],
                "isAllowed": false
            ],
            [
                "adhocBinary": ["_0": ["relative": "file:///tmp/swift-frontend"]]
            ]
        ]

        let result = JarvisControlCenterMenuBarRepair.repairTrackedApplications(&entries)

        XCTAssertEqual(result.removedForeignReferences, 0)
        XCTAssertTrue(result.forcedAllowed)
        XCTAssertEqual((entries[1] as? [String: Any])?["isAllowed"] as? Bool, false)
        XCTAssertEqual((entries[3] as? [String: Any])?["isAllowed"] as? Bool, true)
    }

    func testControlCenterRepairRewritesNestedTrackedApplicationsData() throws {
        let fixture: [Any] = [
            ["bundle": ["_0": "com.openai.codex"]],
            [
                "location": ["bundle": ["_0": "com.openai.codex"]],
                "menuItemLocations": [
                    ["bundle": ["_0": "com.openai.codex"]],
                    ["bundle": ["_0": "com.jarvis.mac"]]
                ],
                "isAllowed": false
            ]
        ]
        let inner = try PropertyListSerialization.data(
            fromPropertyList: fixture,
            format: .binary,
            options: 0
        )
        let outer: [String: Any] = [
            "trackedApplications": inner,
            "showSiri": true
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-controlcenter-\(UUID().uuidString).plist")
        try PropertyListSerialization.data(
            fromPropertyList: outer,
            format: .binary,
            options: 0
        ).write(to: url)

        let result = try JarvisControlCenterMenuBarRepair.repairPreferences(at: url)
        XCTAssertEqual(result.removedForeignReferences, 1)

        let repaired = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: url),
            options: [],
            format: nil
        ) as? [String: Any]
        let trackedData = try XCTUnwrap(repaired?["trackedApplications"] as? Data)
        let entries = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: trackedData, options: [], format: nil) as? [Any]
        )
        let locations = (entries[1] as? [String: Any])?["menuItemLocations"] as? [Any]
        XCTAssertEqual(locations?.count, 1)
        XCTAssertEqual(repaired?["showSiri"] as? Bool, true)
    }
}

private final class FlippedStubView: NSView {
    override var isFlipped: Bool {
        true
    }
}
