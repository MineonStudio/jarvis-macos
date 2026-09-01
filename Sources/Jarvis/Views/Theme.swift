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
    static let metricValue = Font.system(size: 22, weight: .semibold, design: .rounded)
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
}

enum JarvisMetrics {
    static let pageInset: CGFloat = 30
    static let shellHorizontalPadding: CGFloat = 10
    static let shellVerticalPadding: CGFloat = 10
    static let shellContentSpacing: CGFloat = 10
    static let cardRadius: CGFloat = 14
    static let controlRadius: CGFloat = 10
    static let iconTintOpacity: CGFloat = 0.22
    static let segmentedItemHeight: CGFloat = 28
    static let segmentedControlPadding: CGFloat = 2
    static let segmentedItemVerticalPadding: CGFloat = 4
    static let sidebarMinimumWidth: CGFloat = 152
    static let sidebarWidth: CGFloat = 168
    static let sidebarMaximumWidth: CGFloat = 220
    static let sidebarContentPadding: CGFloat = 8
}

/// Metrics shared by every control rendered in the native window toolbar.
///
/// The chat toolbar is the reference implementation: controls occupy one
/// 32-point row, use an 8-point rhythm, and do not draw a parent surface.
enum JarvisToolbarMetrics {
    static let controlSize: CGFloat = 32
    static let controlSpacing: CGFloat = 8
    static let iconSize: CGFloat = 13
}

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

struct JarvisPageTopBar: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(JarvisTypography.cardTitle)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct JarvisCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .jarvisGlass(cornerRadius: JarvisMetrics.cardRadius, interactive: false)
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
        .jarvisGlass(cornerRadius: JarvisMetrics.cardRadius, interactive: false)
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(JarvisTypography.pageTitle)
            .foregroundStyle(.primary)
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

/// Text-first action style for module operation bars. The operation bar owns
/// placement and spacing; individual actions provide only their label and
/// hover/press feedback, so no control can grow into a toolbar background.
struct JarvisToolbarButtonStyle: ButtonStyle {
    let tint: Color?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(tint: Color? = nil) {
        self.tint = tint
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(tint == nil ? JarvisTypography.control : JarvisTypography.controlEmphasis)
            .foregroundStyle(tint ?? Color.primary)
            .padding(.horizontal, 10)
            .frame(height: JarvisToolbarMetrics.controlSize)
            .opacity(configuration.isPressed ? 0.68 : 1)
            .contentShape(Capsule())
            .jarvisHoverFeedback(in: Capsule(), scale: 1.03)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.98)
            .animation(
                JarvisMotion.animation(JarvisMotion.buttonPress, reduceMotion: reduceMotion),
                value: configuration.isPressed
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

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(isSelected ? JarvisTypography.controlEmphasis : JarvisTypography.control)
                .foregroundStyle(isSelected ? Color.white : Color.jarvisTextSecondary)
                .padding(.horizontal, 10)
                .frame(height: JarvisToolbarMetrics.controlSize)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(JarvisMotion.selectionPillTint)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.82))
        .jarvisHoverFeedback(in: Capsule(), scale: 1.02)
    }
}

struct JarvisSecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(JarvisTypography.control)
            .foregroundStyle(.primary)
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
