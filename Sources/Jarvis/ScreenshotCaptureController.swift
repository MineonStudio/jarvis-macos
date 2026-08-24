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
    case translateRequested(Data)
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
    let translationProgress: ScreenshotTranslationProgress
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

@MainActor
final class ScreenshotTranslationProgress: ObservableObject {
    @Published var isTranslating = false
}

enum ScreenshotToolbarMetrics {
    static let baseWidth: CGFloat = 440
    static let compactHeight: CGFloat = 70
    static let expandedHeight: CGFloat = 111
    static let gap: CGFloat = 16
    static let screenHorizontalInset: CGFloat = 12
    static let availableWidthInset: CGFloat = screenHorizontalInset * 2
}

@MainActor
final class ScreenshotCaptureController {
    let screenshotService = ScreenshotService()
    let translationProgress = ScreenshotTranslationProgress()
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
}
