@testable import Jarvis
import XCTest

final class AppIconTests: XCTestCase {
    func testAppIconChoicesAreStaticDefaultAndInvertedAssets() {
        XCTAssertEqual(
            JarvisAppIcon.allCases.map(\.rawValue),
            ["AppIcon", "AppIconInverted"]
        )
        XCTAssertEqual(JarvisAppIcon.allCases.map(\.title), ["默认", "反色"])
    }
}
