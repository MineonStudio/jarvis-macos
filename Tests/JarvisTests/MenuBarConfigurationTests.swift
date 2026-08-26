@testable import Jarvis
import XCTest

final class MenuBarConfigurationTests: XCTestCase {
    func testStatusItemUsesStableNamespacedAutosaveName() async {
        let autosaveName = await JarvisMenuBarController.menuBarAutosaveName

        XCTAssertEqual(autosaveName, "com.jarvis.mac.primary-status-item")
    }
}
