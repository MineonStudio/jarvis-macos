import AppKit
@testable import Jarvis
import XCTest

@MainActor
final class ScreenshotSelectionBehaviorTests: XCTestCase {
    private func makeController(sessionID: UUID) -> ScreenshotCaptureController {
        let controller = ScreenshotCaptureController()
        controller.activeSessionID = sessionID
        controller.selectionCompletionDelivered = false
        return controller
    }

    /// 在空白桌面上点一下会送来一个 0×0 的选区。它不该把整场截图销毁——遮罩和
    /// 冻结帧都还在，用户只是想重新拖。
    func testTinySelectionKeepsTheSessionAlive() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let sessionID = UUID()
        let controller = makeController(sessionID: sessionID)
        var completionResult: Result<ScreenshotEditingSession, Error>?
        var completionCallCount = 0

        controller.finishSelection(
            CGRect(x: 100, y: 100, width: 0, height: 0),
            frozenScreen: ScreenshotCapture(
                data: Data(),
                screenFrame: CGRect(origin: .zero, size: screen.frame.size)
            ),
            on: screen,
            sessionID: sessionID
        ) { result in
            completionCallCount += 1
            completionResult = result
        }

        XCTAssertEqual(completionCallCount, 0, "小选区不该结束这次会话")
        XCTAssertNil(completionResult)
        XCTAssertFalse(controller.selectionCompletionDelivered, "会话应当仍是活的")
        XCTAssertEqual(controller.activeSessionID, sessionID)
    }

    /// 反过来也要成立：正常大小的选区必须照常交付，别把守卫写成永远返回。
    func testUsableSelectionStillCompletes() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let sessionID = UUID()
        let controller = makeController(sessionID: sessionID)
        var completionCallCount = 0
        var didSucceed = false

        try controller.finishSelection(
            CGRect(x: 50, y: 50, width: 300, height: 200),
            frozenScreen: ScreenshotCapture(
                data: makePNGData(size: CGSize(width: 400, height: 300)),
                screenFrame: CGRect(origin: .zero, size: screen.frame.size)
            ),
            on: screen,
            sessionID: sessionID
        ) { result in
            completionCallCount += 1
            if case .success = result {
                didSucceed = true
            }
        }

        XCTAssertEqual(completionCallCount, 1, "正常选区应当交付会话")
        XCTAssertTrue(didSucceed)
        XCTAssertTrue(controller.selectionCompletionDelivered)
    }

    private func makePNGData(size: CGSize) throws -> Data {
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width),
                pixelsHigh: Int(size.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
