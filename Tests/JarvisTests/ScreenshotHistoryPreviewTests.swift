import AppKit
@testable import Jarvis
import XCTest

@MainActor
final class ScreenshotHistoryPreviewTests: XCTestCase {
    func testMouseZoomUsesBoundedTenPercentSteps() {
        let model = FullscreenMediaPreviewModel()

        XCTAssertEqual(model.zoom, 1)
        model.adjustZoom(by: 0.1)
        XCTAssertEqual(model.zoom, 1.1, accuracy: 0.001)

        model.adjustZoom(by: -0.1)
        XCTAssertEqual(model.zoom, 1, accuracy: 0.001)

        model.setZoom(0.2)
        XCTAssertEqual(model.zoom, 0.2, accuracy: 0.001)

        model.adjustZoom(by: -0.1)
        XCTAssertEqual(model.zoom, 0.2, accuracy: 0.001)

        model.setZoom(4)
        model.adjustZoom(by: 0.1)
        XCTAssertEqual(model.zoom, 4, accuracy: 0.001)
    }

    func testZoomAlwaysUsesTenPercentIncrements() {
        let model = FullscreenMediaPreviewModel()

        model.setZoom(1.55)

        XCTAssertEqual(model.zoom, 1.6, accuracy: 0.001)
    }

    func testZoomChangesTheImageLayoutSizeDirectly() {
        let model = FullscreenMediaPreviewModel()
        model.setZoom(1.5)

        XCTAssertEqual(
            model.displaySize(for: CGSize(width: 800, height: 600)),
            CGSize(width: 1200, height: 900)
        )
    }

    func testBorderlessPreviewSizingDoesNotReserveTitlebarSpace() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = screenFrame

        XCTAssertEqual(
            PreviewWindowSupport.maximumContentSize(
                for: screenFrame,
                topChromeHeight: 0
            ).height,
            screenFrame.height - PreviewWindowSupport.screenInset
        )
        XCTAssertEqual(
            PreviewWindowSupport.centeredFrame(
                contentSize: CGSize(width: 600, height: 400),
                visibleFrame: visibleFrame,
                topChromeHeight: 0
            ).midY,
            visibleFrame.midY,
            accuracy: 0.001
        )
    }

    func testBorderlessPreviewConfigurationRemovesWindowChrome() {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        defer { panel.close() }

        PreviewWindowSupport.configureBorderlessPreviewPanel(panel)

        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertFalse(panel.styleMask.contains(.titled))
        XCTAssertEqual(panel.title, "")
        XCTAssertEqual(panel.titleVisibility, .hidden)
        XCTAssertFalse(panel.styleMask.contains(.resizable))
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertFalse(panel.hasShadow)
    }

    func testDimmingPanelConsumesMouseEventsWithoutPassingThrough() {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        defer { panel.close() }

        PreviewWindowSupport.configureDimmingPanel(
            panel,
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.isMovableByWindowBackground)
    }
}
