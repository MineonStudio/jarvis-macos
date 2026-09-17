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

/// 一级编辑栏里所有图标的视觉尺寸基准。
///
/// 只把字号写成同一个数是不够的：21pt 下 `arrow.up.right` 的墨迹只有 15.5pt 高，
/// 而 `square.and.arrow.down` 有 22.25pt、马赛克自绘图形是 24pt——并排放在一行里
/// 参差不齐一眼就能看出来。这里按实测的墨迹高度反推每颗图标各自的字号，让它们的
/// 墨迹高度统一落在 `targetInkHeight` 上。数字由 `ScreenshotToolbarIconTests`
/// 复测，改了字号或换了符号会被测出来。
enum ScreenshotToolbarIconMetrics {
    /// 所有一级图标统一的墨迹高度。
    static let targetInkHeight: CGFloat = 18
    /// 图标画框：比墨迹大一圈，宽图标才不会被裁。
    static let box: CGFloat = 24
    /// 量基准时用的字号。
    private static let referencePointSize: CGFloat = 21

    /// 符号名 → 在 `referencePointSize` 下的实测墨迹高度。
    private static let measuredInkHeights: [String: CGFloat] = [
        "arrow.up.right": 15.50,
        "rectangle": 19.25,
        "character.bubble": 21.75,
        "arrow.uturn.backward": 19.75,
        "arrow.uturn.forward": 19.75,
        "square.and.arrow.down": 22.25,
        "xmark": 16.75,
        "checkmark": 17.75
    ]

    /// 某个符号要用的字号。
    static func pointSize(for symbol: String) -> CGFloat {
        guard let inkHeight = measuredInkHeights[symbol], inkHeight > 0 else {
            return referencePointSize
        }
        return referencePointSize * targetInkHeight / inkHeight
    }

    /// 文字工具那个衬线 "T" 的字号（24pt 下墨迹 17.25pt 高）。
    static let textPointSize: CGFloat = 24 * targetInkHeight / 17.25
}

enum ScreenshotToolbarMetrics {
    static let baseWidth: CGFloat = 520
    static let translationWidth: CGFloat = 520
    /// 主按钮行的高度。
    static let mainRowHeight: CGFloat = 64
    /// 二级控件行的高度。
    static let secondaryRowHeight: CGFloat = 40
    /// 两条胶囊之间的缝。上下分成两块之后这里不再画分隔线。
    static let pillSpacing: CGFloat = 6
    /// 胶囊底部的留白：玻璃效果贴着面板边缘会显得被切掉。
    static let pillBottomPadding: CGFloat = 6
    /// 主按钮行里每颗按钮的边长。
    static let mainButtonSize: CGFloat = 42
    /// 二级行里最高控件的高度（次要按钮），用来核算内缩够不够躲开圆头。
    static let secondaryContentHeight: CGFloat = 32
    /// 主按钮行的左右内缩。胶囊两端的圆头半径是行高的一半，内缩不够会把
    /// 最外侧按钮的图标切掉。`ScreenshotToolbarCapsuleTests` 钉着这个约束。
    static let mainRowHorizontalPadding: CGFloat = 11
    static let secondaryRowHorizontalPadding: CGFloat = 14

    static var compactHeight: CGFloat {
        mainRowHeight + pillBottomPadding
    }

    static var expandedHeight: CGFloat {
        mainRowHeight + pillSpacing + secondaryRowHeight + pillBottomPadding
    }

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
    var sessionPhase: ScreenshotSessionPhase = .idle
    var activeSessionID: UUID?
    var didPushCrosshairCursor = false
}
