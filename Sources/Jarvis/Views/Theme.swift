import AppKit
import SwiftUI

// MARK: - Jarvis visual language

enum JarvisTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func resolvedColorScheme(system: ColorScheme) -> ColorScheme {
        preferredColorScheme ?? system
    }
}

enum JarvisTypography {
    static let pageTitle = Font.system(size: 26, weight: .semibold, design: .rounded)
    static let cardTitle = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 14)
    static let bodyEmphasis = Font.system(size: 14, weight: .semibold)
    static let control = Font.system(size: 13, weight: .medium)
    static let controlEmphasis = Font.system(size: 13, weight: .semibold)
    static let secondary = Font.system(size: 13)
    static let caption = Font.system(size: 12)
    static let captionEmphasis = Font.system(size: 12, weight: .medium)
    static let monospaced = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let badge = Font.system(size: 11, weight: .bold, design: .rounded)
    /// 小节的标题字。比 caption 重一档，用来说明下面那一组控件是什么。
    static let sectionLabel = Font.system(size: 12, weight: .semibold)
    /// 更小一档的辅助文字，用于路径、计数这类次要信息。
    static let micro = Font.system(size: 10)
    static let microMonospaced = Font.system(size: 10, design: .monospaced)
    /// 数值读数：等宽，好让数字变化时不跳动。
    static let monospacedSmall = Font.system(size: 11, weight: .medium, design: .monospaced)
}

/// Uses SwiftUI's presentation-level appearance API with the current system
/// scheme resolved explicitly. Resolving .system to .light/.dark avoids a
/// macOS Settings scene retaining the previous preferred scheme until another
/// interaction causes it to redraw.
private struct JarvisThemeModifier: ViewModifier {
    let theme: JarvisTheme
    let systemColorScheme: ColorScheme

    func body(content: Content) -> some View {
        content.preferredColorScheme(theme.resolvedColorScheme(system: systemColorScheme))
    }
}

extension Color {
    // Keep these names stable for the rest of the app, but use semantic system
    // colors instead of a fixed dark palette so the window follows macOS.
    static let jarvisBackground = Color(nsColor: .textBackgroundColor)
    static let jarvisPanel = Color(nsColor: .controlBackgroundColor)
    static let jarvisCyan = Color.accentColor
    static let jarvisTextSecondary = Color.secondary
    /// 嵌在卡片里的区域（设置行、手风琴、权限行）的底色：比卡片表面更淡，
    /// 靠明度差而不是描边来分层。
    static let jarvisInsetSurface = Color.primary.opacity(0.045)
}

enum JarvisMetrics {
    static let pageInset: CGFloat = 30
    static let shellHorizontalPadding: CGFloat = 10
    static let shellVerticalPadding: CGFloat = 10
    static let shellContentSpacing: CGFloat = 10
    static let cardRadius: CGFloat = 14
    /// 模块外壳的圆角，比内部卡片略大一圈。
    static let panelRadius: CGFloat = 16
    static let controlRadius: CGFloat = 10
    static let iconTintOpacity: CGFloat = 0.22
    static let segmentedItemHeight: CGFloat = 28
    static let segmentedControlPadding: CGFloat = 2
    /// 选项之间的缝：转发 `JarvisSegmentedMetrics`，全 app 只有那一个数。
    static let segmentedItemSpacing: CGFloat = JarvisSegmentedMetrics.itemSpacing
    static let segmentedItemVerticalPadding: CGFloat = 4
    static let sidebarMinimumWidth: CGFloat = 152
    static let sidebarWidth: CGFloat = 168
    static let sidebarMaximumWidth: CGFloat = 220
    static let sidebarContentPadding: CGFloat = 8
}

/// 分段 / 组合容器的统一几何。
///
/// 一条规则：**容器四边留等宽的内边距，选中项填满这一圈以内，形状是胶囊**。
/// 等宽不是审美偏好——容器和选中胶囊的圆头圆心重合（容器半径 − 内边距 = 胶囊半径），
/// 胶囊才像嵌在容器里；两边给得不一样，选中块就会从圆头上歪出来。截图工具栏二级行
/// 原来横向留 20、纵向留 7（由行高 40 − 控件 26 反推），选中胶囊明显偏内。
///
/// 所以内边距只有一个来源：`padding(containerHeight:itemHeight:)`。调用点别再写第二个数。
enum JarvisSegmentedMetrics {
    /// 等宽内边距：选中胶囊到容器左 / 上 / 下（以及末项到右侧）都取它。
    static func padding(containerHeight: CGFloat, itemHeight: CGFloat) -> CGFloat {
        max(0, (containerHeight - itemHeight) / 2)
    }

    /// 选项之间的缝。
    static let itemSpacing: CGFloat = 2
    /// 紧凑档选项：截图工具栏二级行、网页模块的分组选择器。
    static let compactItemHeight: CGFloat = 26

    /// 窗口工具栏里的成组控件：容器就是工具栏那一行（`JarvisToolbarMetrics.controlSize`），
    /// 装的是紧凑档选项。
    static var toolbarGroupPadding: CGFloat {
        padding(
            containerHeight: JarvisToolbarMetrics.controlSize,
            itemHeight: compactItemHeight
        )
    }
}

/// Metrics shared by every control rendered in the native window toolbar.
///
/// The chat toolbar is the reference implementation: controls occupy one
/// 32-point row, use an 8-point rhythm, and do not draw a parent surface.
enum JarvisToolbarMetrics {
    static let controlSize: CGFloat = 32
    static let iconSize: CGFloat = 13
    static let searchFieldWidth: CGFloat = 240
    /// 图标簇（网页模块那组前进/后退/刷新）自己的留白。里面装的是 32 高的图标按钮，
    /// 不是 26 高的紧凑选项——`JarvisSegmentedMetrics` 那条「容器高 − 选项高」的公式
    /// 在这里会算出 0，别混用。
    static let iconClusterPadding: CGFloat = 3
}

/// Marks a toolbar item whose view owns its own capsule, glass, or other
/// background. Native macOS toolbars otherwise add their shared item surface
/// around that view, producing the recurring double-layer control.
struct JarvisToolbarSurface<Content: View>: ToolbarContent {
    private let id: String
    private let placement: ToolbarItemPlacement
    private let content: Content

    init(
        id: String,
        placement: ToolbarItemPlacement = .automatic,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self.placement = placement
        self.content = content()
    }

    var body: some ToolbarContent {
        ToolbarItem(id: id, placement: placement) {
            content
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

/// Shared toolbar search field used by clipboard, wallpaper, and meetings.
///
/// Height comes from the native toolbar item surface, not a custom 32-point
/// glass capsule. Hiding that surface and drawing our own glass made the
/// field shorter than adjacent toolbar controls.
struct JarvisToolbarSearchField: View {
    @Binding var text: String
    var placeholder: String
    var help: String?
    var accessibilityTitle: String?
    var focusesOnAppear = false
    var onSubmit: (() -> Void)?
    var onClear: (() -> Void)?
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: JarvisToolbarMetrics.iconSize, weight: .medium))
                .foregroundStyle(Color.jarvisTextSecondary)
                .frame(
                    width: JarvisToolbarMetrics.iconSize,
                    height: JarvisToolbarMetrics.iconSize
                )

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(JarvisTypography.control)
                .controlSize(.regular)
                .focused($isFocused)
                .onSubmit {
                    onSubmit?()
                }

            if !text.isEmpty {
                Button {
                    if let onClear {
                        onClear()
                    } else {
                        text = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: JarvisToolbarMetrics.iconSize, weight: .semibold))
                        .frame(
                            width: JarvisToolbarMetrics.iconSize,
                            height: JarvisToolbarMetrics.iconSize
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.jarvisTextSecondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: JarvisToolbarMetrics.searchFieldWidth)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused = true
        }
        .onAppear {
            if focusesOnAppear {
                isFocused = true
            }
        }
        .accessibilityLabel(accessibilityTitle ?? placeholder)
    }
}

/// Shared capsule surface for compact text-entry controls.
/// Shared content-area shell for every module in the main window.
///
/// The shell owns the window toolbar and the body inset. Modules provide only
/// leading and trailing toolbar content plus their body, so the system can
/// place the operation bar alongside the native sidebar control and reflow it
/// when the split view changes width.
struct JarvisContentArea<LeadingToolbar: ToolbarContent, TrailingToolbar: ToolbarContent, Content: View>: View {
    private let leadingToolbar: LeadingToolbar
    private let trailingToolbar: TrailingToolbar
    private let content: Content

    init(
        @ToolbarContentBuilder leadingToolbar: () -> LeadingToolbar,
        @ToolbarContentBuilder trailingToolbar: () -> TrailingToolbar,
        @ViewBuilder content: () -> Content
    ) {
        self.leadingToolbar = leadingToolbar()
        self.trailingToolbar = trailingToolbar()
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, JarvisMetrics.shellContentSpacing)
            .padding(.horizontal, JarvisMetrics.shellHorizontalPadding)
            .padding(.bottom, JarvisMetrics.shellVerticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.jarvisBackground)
            .toolbar {
                leadingToolbar
                ToolbarSpacer(.flexible, placement: .automatic)
                trailingToolbar
            }
    }
}

struct JarvisCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .jarvisContentSurface(cornerRadius: JarvisMetrics.cardRadius)
    }
}

struct JarvisEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 56, height: 56)
                .background(
                    Color.accentColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.75)
                }
            Text(title)
                .font(JarvisTypography.cardTitle)
                .multilineTextAlignment(.center)
            Text(message)
                .font(JarvisTypography.secondary)
                .foregroundStyle(Color.jarvisTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .jarvisContentSurface(cornerRadius: JarvisMetrics.cardRadius)
    }
}

/// Standard content-layer surface for cards and collections.
///
/// Liquid Glass belongs primarily to the functional layer (toolbars,
/// navigation, and transient controls). Content cards use a semantic macOS
/// control background instead so dense content remains legible and calm.
struct JarvisContentSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                Color.jarvisPanel,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
    }
}

struct JarvisInlineLoadingState: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("正在加载")
        }
        .foregroundStyle(Color.jarvisTextSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在加载")
    }
}

/// Native macOS 26 Liquid Glass wrapper shared by cards and controls.
struct JarvisGlassModifier: ViewModifier {
    let tint: Color?
    let cornerRadius: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        if let tint {
            content.glassEffect(
                .regular.tint(tint).interactive(interactive),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content.glassEffect(
                .regular.interactive(interactive),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}

/// 选中 / 悬停的胶囊底。全应用共用一套：形状恒为 `Capsule`，选中恒为 accent 实心，
/// 悬停恒为淡色。
///
/// 这套判断（选中 > 悬停 > 透明）原来在五六个控件里各写一遍，颜色和形状各有出入，
/// 改一处漏一处不会有信号。分段容器里的可选项、工具栏筛选按钮都用它。
struct JarvisSelectionPillModifier: ViewModifier {
    let isSelected: Bool
    let isHovered: Bool

    func body(content: Content) -> some View {
        content.background {
            Capsule().fill(
                isSelected
                    ? JarvisMotion.selectionPillTint
                    : (isHovered ? JarvisMotion.hoverPillTint : .clear)
            )
        }
    }
}

extension View {
    /// 选中 / 悬停的胶囊底，见 `JarvisSelectionPillModifier`。
    func jarvisSelectionPill(isSelected: Bool, isHovered: Bool = false) -> some View {
        modifier(JarvisSelectionPillModifier(isSelected: isSelected, isHovered: isHovered))
    }
}

struct JarvisGlassShapeModifier<GlassShape: Shape>: ViewModifier {
    let tint: Color?
    let shape: GlassShape
    let interactive: Bool

    func body(content: Content) -> some View {
        if let tint {
            content.glassEffect(
                .regular.tint(tint).interactive(interactive),
                in: shape
            )
        } else {
            content.glassEffect(
                .regular.interactive(interactive),
                in: shape
            )
        }
    }
}

extension View {
    /// 模块外壳：先裁圆角再铺面板底色。
    ///
    /// 这段组合原本在六处逐字重复，圆角值 16 也散在各处。网页模块是**例外**，
    /// 它不能裁剪（见 `JarvisWebPlatformViews` 的说明），所以只取
    /// `JarvisMetrics.panelRadius` 而不用这个 modifier。
    func jarvisModulePanel() -> some View {
        clipShape(RoundedRectangle(cornerRadius: JarvisMetrics.panelRadius, style: .continuous))
            .jarvisFloatingPanel(cornerRadius: JarvisMetrics.panelRadius)
    }
}

struct JarvisFloatingPanelModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                Color.jarvisPanel,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(0.11), radius: 16, y: 6)
    }
}

extension View {
    func jarvisTheme(_ theme: JarvisTheme, systemColorScheme: ColorScheme) -> some View {
        modifier(JarvisThemeModifier(theme: theme, systemColorScheme: systemColorScheme))
    }

    func jarvisGlass(
        tint: Color? = nil,
        cornerRadius: CGFloat = JarvisMetrics.controlRadius,
        interactive: Bool = true
    ) -> some View {
        modifier(JarvisGlassModifier(tint: tint, cornerRadius: cornerRadius, interactive: interactive))
    }

    func jarvisGlass(
        tint: Color? = nil,
        in shape: some Shape,
        interactive: Bool = true
    ) -> some View {
        modifier(JarvisGlassShapeModifier(tint: tint, shape: shape, interactive: interactive))
    }

    func jarvisFloatingPanel(cornerRadius: CGFloat = 16) -> some View {
        modifier(JarvisFloatingPanelModifier(cornerRadius: cornerRadius))
    }

    func jarvisContentSurface(cornerRadius: CGFloat = JarvisMetrics.cardRadius) -> some View {
        modifier(JarvisContentSurfaceModifier(cornerRadius: cornerRadius))
    }

    /// A lighter Liquid Glass treatment for the small icon containers used
    /// throughout the pages. Full-strength accent tint makes these bubbles
    /// read as solid dark badges instead of translucent glass.
    func jarvisIconGlass(
        tint: Color = .accentColor,
        in shape: some Shape,
        interactive: Bool = false
    ) -> some View {
        jarvisGlass(
            tint: tint.opacity(JarvisMetrics.iconTintOpacity),
            in: shape,
            interactive: interactive
        )
    }
}

/// 历史网格卡片的骨架：悬停缩放、圆角裁剪、选中描边和「已选中」徽标。
///
/// 剪贴板和截图两张卡片原本各写一份完全一样的外壳，唯一的差别是内容的对齐方式。
struct HistoryCardChrome<Preview: View>: View {
    let preview: Preview
    let width: CGFloat
    let height: CGFloat
    let isSelected: Bool
    var alignment: Alignment = .center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        ZStack {
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .scaleEffect(
                    isHovered && !reduceMotion
                        ? HistoryGridMetrics.clipboardPreviewHoverScale
                        : 1
                )
                .animation(
                    JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion),
                    value: isHovered
                )
        }
        .frame(width: width, height: height, alignment: alignment)
        .clipShape(
            RoundedRectangle(
                cornerRadius: HistoryGridMetrics.clipboardCornerRadius,
                style: .continuous
            )
        )
        .jarvisContentSurface(cornerRadius: HistoryGridMetrics.clipboardCornerRadius)
        .overlay {
            RoundedRectangle(
                cornerRadius: HistoryGridMetrics.clipboardCornerRadius,
                style: .continuous
            )
            .stroke(
                isSelected ? Color.accentColor : .clear,
                lineWidth: isSelected ? 2 : 0
            )
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            if isSelected {
                Label("已选中", systemImage: "checkmark.circle.fill")
                    .font(JarvisTypography.captionEmphasis)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    // 选中色和全app的选中胶囊同一枚（`selectionPillTint`）：
                    // 徽标原来自己用了 0.92，比别处深一档，放在一起能看出色差。
                    .background(JarvisMotion.selectionPillTint, in: Capsule())
                    .padding(8)
                    .accessibilityHidden(true)
            }
        }
        .onHover { isHovered = $0 }
    }
}

struct JarvisPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(JarvisTypography.controlEmphasis)
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .opacity(configuration.isPressed ? 0.78 : (isEnabled ? 1 : 0.78))
            .jarvisGlass(
                tint: isEnabled ? .accentColor : Color.primary.opacity(0.12),
                cornerRadius: JarvisMetrics.controlRadius
            )
            .contentShape(RoundedRectangle(cornerRadius: JarvisMetrics.controlRadius, style: .continuous))
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1))
            .animation(
                JarvisMotion.animation(JarvisMotion.buttonPress, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

/// Bottom-overlay action used by media cards. Keep this aligned with the
/// wallpaper card's "设为壁纸" action so card-level operations share one
/// visual language across modules.
struct JarvisCardActionPillButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(JarvisTypography.control)
            .foregroundStyle(.primary)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .opacity(configuration.isPressed ? 0.68 : 1)
            .jarvisGlass(in: Capsule())
            .contentShape(Capsule())
            .shadow(
                color: Color.black.opacity(0.24),
                radius: 6,
                y: 2
            )
            .fixedSize(horizontal: true, vertical: false)
            .scaleEffect(
                reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1)
            )
            .animation(
                JarvisMotion.animation(JarvisMotion.buttonPress, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

/// Text-first action style for module operation bars. The operation bar owns
/// placement and spacing; individual actions provide only their label and
/// hover/press feedback, so no control can grow into a toolbar background.
/// Controls that intentionally draw their own surface must be wrapped in
/// `JarvisToolbarSurface` at the ToolbarItem boundary.
struct JarvisToolbarButtonStyle: ButtonStyle {
    let tint: Color?
    let hoverScale: CGFloat
    let animatesPress: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(tint: Color? = nil, hoverScale: CGFloat = 1.03, animatesPress: Bool = true) {
        self.tint = tint
        self.hoverScale = hoverScale
        self.animatesPress = animatesPress
    }

    /// Menu labels must keep a stable frame. Hovering popup items toggles
    /// press/hover on macOS and would otherwise flicker the attached list.
    static func menu(tint: Color? = nil) -> Self {
        Self(tint: tint, hoverScale: 1, animatesPress: false)
    }

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = animatesPress && configuration.isPressed
        configuration.label
            .font(tint == nil ? JarvisTypography.control : JarvisTypography.controlEmphasis)
            .foregroundStyle(tint ?? Color.primary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .frame(height: JarvisToolbarMetrics.controlSize)
            .opacity(isPressed ? 0.68 : 1)
            .contentShape(Capsule())
            .jarvisHoverFeedback(in: Capsule(), scale: hoverScale)
            .scaleEffect(reduceMotion || !isPressed ? 1 : 0.98)
            .animation(
                JarvisMotion.animation(JarvisMotion.buttonPress, reduceMotion: reduceMotion),
                value: isPressed
            )
    }
}

/// A single selection control for the native toolbar. Selection is rendered
/// by the button itself; there is intentionally no parent capsule or group
/// surface around a row of options.
struct JarvisToolbarSelectionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(isSelected ? JarvisTypography.controlEmphasis : JarvisTypography.control)
                .foregroundStyle(isSelected ? Color.white : Color.jarvisTextSecondary)
                .padding(.horizontal, 10)
                .frame(height: JarvisToolbarMetrics.controlSize)
                .jarvisSelectionPill(isSelected: isSelected, isHovered: isHovered)
                .contentShape(Capsule())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.82))
        .scaleEffect(
            reduceMotion || isSelected || !isHovered ? 1 : 1.02,
            anchor: .center
        )
        .animation(
            JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion),
            value: isHovered
        )
        .animation(
            JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
            value: isSelected
        )
        .onHover { isHovering in
            withAnimation(
                JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion)
            ) {
                isHovered = isHovering
            }
        }
    }
}

/// Shared zoom pair used by the clipboard, screenshot, and resume toolbars.
///
/// The native toolbar item surface sets the height, so the row fills its host
/// instead of forcing a custom frame; a custom 32-point capsule was shorter
/// than adjacent toolbar controls.
struct JarvisToolbarZoomControl: View {
    let canZoomOut: Bool
    let canZoomIn: Bool
    let zoomOutLabel: String
    let zoomInLabel: String
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            zoomButton(
                systemName: "minus",
                help: zoomOutLabel,
                isEnabled: canZoomOut,
                action: onZoomOut
            )

            Divider()
                .frame(height: 16)
                .opacity(0.35)

            zoomButton(
                systemName: "plus",
                help: zoomInLabel,
                isEnabled: canZoomIn,
                action: onZoomIn
            )
        }
        .padding(.horizontal, 2)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func zoomButton(
        systemName: String,
        help: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(
                JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion)
            ) {
                action()
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.92, pressedOpacity: 0.75))
        .opacity(isEnabled ? 1 : 0.35)
        .disabled(!isEnabled)
        .accessibilityLabel(help)
    }
}

struct JarvisSecondaryButtonStyle: ButtonStyle {
    let tint: Color?

    init(tint: Color? = nil) {
        self.tint = tint
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(JarvisTypography.control)
            .foregroundStyle(tint ?? .primary)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .opacity(configuration.isPressed ? 0.68 : 1)
            .jarvisGlass(cornerRadius: JarvisMetrics.controlRadius)
            .contentShape(RoundedRectangle(cornerRadius: JarvisMetrics.controlRadius, style: .continuous))
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1))
            .animation(
                JarvisMotion.animation(JarvisMotion.buttonPress, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}
