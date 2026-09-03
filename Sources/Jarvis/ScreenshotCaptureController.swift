import AppKit
import Combine
import SwiftUI

enum ScreenshotAction {
    case saveRequested
    case confirmRequested
    case save(Data)
    case confirm(Data)
    case pin(Data)
    case cancel
    case tool(ScreenshotTool)
    case undo
    case redo
    case delete
    case duplicate
    case translation
    case startTranslation
    case cancelTranslation
    case toggleTranslationVisibility
}

struct ScreenshotEditingSession: Sendable {
    let id: UUID
    let frozenScreen: ScreenshotCapture
    let selectionRect: CGRect
    let initialCapture: ScreenshotCapture

    var selectionFrame: CGRect {
        initialCapture.screenFrame
    }
}

struct ScreenshotPresentation {
    let session: ScreenshotEditingSession
    let capture: ScreenshotCapture
    let image: NSImage
    let editor: ScreenshotEditorModel
    let onAction: (ScreenshotAction) -> Void
}

struct ScreenshotPresentationPanels {
    let imagePanel: NSPanel
    let toolbarPanel: NSPanel
    let toolbarLayout: ScreenshotToolbarLayoutModel
}

enum ScreenshotTool: CaseIterable {
    case arrow
    case rectangle
    case mosaic
    case text

    var icon: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .mosaic: "checkerboard.rectangle"
        case .text: "textformat"
        }
    }

    var title: String {
        switch self {
        case .arrow: "箭头"
        case .rectangle: "框选"
        case .mosaic: "马赛克"
        case .text: "文字"
        }
    }
}

@MainActor
final class ScreenshotToolbarLayoutModel: ObservableObject {
    @Published var width: CGFloat

    init(width: CGFloat) {
        self.width = width
    }
}

enum ScreenshotToolbarMetrics {
    static let baseWidth: CGFloat = 520
    static let translationWidth: CGFloat = 520
    static let compactHeight: CGFloat = 70
    static let expandedHeight: CGFloat = 111
    static let gap: CGFloat = 16
    static let screenHorizontalInset: CGFloat = 12
    static let availableWidthInset: CGFloat = screenHorizontalInset * 2
    static let overlayInset: CGFloat = 12
}

enum ScreenshotToolbarPlacement {
    static func frame(
        for imageFrame: CGRect,
        in visibleFrame: CGRect,
        height: CGFloat,
        width requestedWidth: CGFloat
    ) -> CGRect {
        let availableWidth = max(1, visibleFrame.width - ScreenshotToolbarMetrics.availableWidthInset)
        let toolbarWidth = min(max(requestedWidth, 1), availableWidth)
        let minX = visibleFrame.minX + ScreenshotToolbarMetrics.screenHorizontalInset
        let maxX = visibleFrame.maxX - toolbarWidth - ScreenshotToolbarMetrics.screenHorizontalInset
        let x = minX <= maxX
            ? min(max(imageFrame.midX - toolbarWidth / 2, minX), maxX)
            : visibleFrame.minX

        let minY = visibleFrame.minY
        let maxY = visibleFrame.maxY - height
        let belowY = imageFrame.minY - height - ScreenshotToolbarMetrics.gap
        let aboveY = imageFrame.maxY + ScreenshotToolbarMetrics.gap
        let y: CGFloat
        if belowY >= minY {
            y = belowY
        } else if aboveY <= maxY {
            y = aboveY
        } else {
            let visibleImage = imageFrame.intersection(visibleFrame)
            let base = visibleImage.isNull || visibleImage.isEmpty ? visibleFrame : visibleImage
            y = min(base.minY + ScreenshotToolbarMetrics.overlayInset, maxY)
        }

        let clampedY = maxY >= minY ? min(max(y, minY), maxY) : minY
        return CGRect(x: x, y: clampedY, width: toolbarWidth, height: height)
    }
}

@MainActor
final class ScreenshotCaptureController {
    let screenshotService = ScreenshotService()
    var selectionWindows: [SelectionOverlayWindow] = []
    var resultWindow: NSPanel?
    var toolbarWindow: NSPanel?
    var activeEditor: ScreenshotEditorModel?
    var editorObservation: AnyCancellable?
    var toolbarLayout: ScreenshotToolbarLayoutModel?
    var selectionCompletionDelivered = false
    var pinNextSelectionResult = false
    var pinnedItems: [UUID: PinnedScreenshotItem] = [:]
    var selectedPinnedID: UUID?
    var activeCaptureScreenFrame: CGRect?
    var previousFrontmostApplication: NSRunningApplication?
    var sessionPhase: ScreenshotSessionPhase = .idle
    var activeSessionID: UUID?
    var didPushCrosshairCursor = false
}
