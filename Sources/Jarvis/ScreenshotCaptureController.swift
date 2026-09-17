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
    /// 工具栏整体在选区上方时，二级行排在主行**上面**。
    ///
    /// 窗口是按贴着选区的那条边定位的：放下方时贴的是窗口上沿，主行正好在顶部，
    /// 所以收起二级行主行不动；放上方时贴的是窗口下沿，主行若还在顶部，窗口一变矮
    /// 它就会跟着弹一下。把二级行挪到上面、主行贴着下沿，两边就都不动了。
    @Published var placesSecondaryRowAboveMain = false

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
    /// 面板宽度 = 主按钮行的宽度。主行内容固定，窗口就跟着它；二级行按内容
    /// 自适应，在窗口里居中显示。
    static var baseWidth: CGFloat {
        mainRowContentWidth + (2 * mainRowHorizontalPadding)
    }

    /// 主按钮行的高度。
    static let mainRowHeight: CGFloat = 64
    /// 二级控件行的高度。
    static let secondaryRowHeight: CGFloat = 40
    /// 两条胶囊之间的缝。上下分成两块之后这里不再画分隔线。
    static let pillSpacing: CGFloat = 6
    /// 主按钮行里每颗按钮的边长。
    static let mainButtonSize: CGFloat = 42
    /// 二级行里控件（选项药丸、下拉芯片、文字按钮）的统一高度。
    ///
    /// 二级行本身已经是一条大胶囊，里面的控件不再各自套容器——它们只用这一点
    /// 高度上的药丸底表示选中，不再多叠一层圆角。
    static let secondaryControlHeight: CGFloat = 26

    /// 主按钮行的左右内缩。胶囊两端的圆头半径是行高的一半，内缩不够会把
    /// 最外侧按钮的图标切掉。下限由 `minimumCapsuleInset` 推出，
    /// `ScreenshotToolbarCapsuleTests` 钉着这个约束。
    static let mainRowHorizontalPadding: CGFloat = 11
    /// 二级行的左右内缩。**含**各控件自己的内边距——一处内缩只有一个来源，
    /// 否则测试算的是胶囊内缩、实际生效的是它加上控件内边距。
    static let secondaryRowHorizontalPadding: CGFloat = 20

    /// 主按钮行的内容宽度：10 颗按钮，加 3 组分隔线（1pt 线 + 两侧各 8pt 留白）。
    /// 它和面板的固定宽度一起决定内缩的**上界**——内缩不是越大越好。
    static var mainRowContentWidth: CGFloat {
        (10 * mainButtonSize) + (3 * (1 + 2 * 8))
    }

    /// 行高 `rowHeight` 的胶囊要容下高 `contentHeight` 的内容，两端圆头至少要
    /// 留出多少内缩。胶囊的圆头半径是行高的一半，圆心在 (r, r)，内容角点
    /// (inset, (rowHeight - contentHeight) / 2) 到圆心的距离不能超过 r。
    static func minimumCapsuleInset(rowHeight: CGFloat, contentHeight: CGFloat) -> CGFloat {
        let radius = rowHeight / 2
        let halfContent = min(contentHeight, rowHeight) / 2
        let squared = radius * radius - halfContent * halfContent
        guard squared > 0 else { return radius }
        return radius - squared.squareRoot()
    }

    /// 收起态就是主按钮行本身；展开态再叠一条二级行。胶囊铺满窗口，不加额外留白
    /// ——留白区会变成看得见截图却点不动的死区。
    static var compactHeight: CGFloat {
        mainRowHeight
    }

    static var expandedHeight: CGFloat {
        mainRowHeight + pillSpacing + secondaryRowHeight
    }

    static let gap: CGFloat = 16
    static let screenHorizontalInset: CGFloat = 12
    static let availableWidthInset: CGFloat = screenHorizontalInset * 2
    static let overlayInset: CGFloat = 12
}

enum ScreenshotToolbarPlacement {
    /// 工具栏相对选区的落位。
    ///
    /// 它同时决定窗口**以哪条边为基准**：放在选区下方时基准是窗口上沿，放在上方
    /// 或压在图上时基准是下沿。主按钮行要待在基准那一侧，收起/展开二级行才不会
    /// 把它推走。
    enum Anchor {
        case below
        case above
        case overlay

        /// 基准是窗口下沿（二级行要排在主行上面）。
        var anchorsWindowBottom: Bool {
            self != .below
        }
    }

    /// 按**收起态**的高度选落位。
    ///
    /// 用请求的高度选会有个要命的效果：展开二级行时窗口变高，原本放得下的一侧变得
    /// 放不下，落位当场翻到对面——工具栏瞬移几百点，行序也跟着翻。收起态是它最小
    /// 的占位，按它选就永远稳定。
    static func anchor(
        for imageFrame: CGRect,
        in visibleFrame: CGRect,
        requestedWidth _: CGFloat = ScreenshotToolbarMetrics.baseWidth
    ) -> Anchor {
        let height = ScreenshotToolbarMetrics.compactHeight
        let minY = visibleFrame.minY
        let maxY = visibleFrame.maxY - height
        let belowY = imageFrame.minY - height - ScreenshotToolbarMetrics.gap
        let aboveY = imageFrame.maxY + ScreenshotToolbarMetrics.gap
        if belowY >= minY {
            return .below
        }
        if aboveY <= maxY {
            return .above
        }
        return .overlay
    }

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
        let y: CGFloat
        switch anchor(for: imageFrame, in: visibleFrame, requestedWidth: requestedWidth) {
        case .below:
            y = imageFrame.minY - height - ScreenshotToolbarMetrics.gap
        case .above:
            y = imageFrame.maxY + ScreenshotToolbarMetrics.gap
        case .overlay:
            let visibleImage = imageFrame.intersection(visibleFrame)
            let base = visibleImage.isNull || visibleImage.isEmpty ? visibleFrame : visibleImage
            y = base.minY + ScreenshotToolbarMetrics.overlayInset
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
    /// 每次收起编辑界面就 +1，用来让在途的导出结果作废。
    var resultGeneration = 0
    var selectionCompletionDelivered = false
    var pinNextSelectionResult = false
    var pinnedItems: [UUID: PinnedScreenshotItem] = [:]
    var selectedPinnedID: UUID?
    /// 上一次看到的屏幕排布，用来判断「屏幕真的变了」。
    var lastKnownScreenFrames: [CGRect] = []
    var activeCaptureScreenFrame: CGRect?
    var sessionPhase: ScreenshotSessionPhase = .idle
    var activeSessionID: UUID?
    var didPushCrosshairCursor = false
}
