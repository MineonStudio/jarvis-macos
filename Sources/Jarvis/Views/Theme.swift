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
    static let cardRadius: CGFloat = 14
    static let controlRadius: CGFloat = 10
    static let iconTintOpacity: CGFloat = 0.22
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

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 26, weight: .semibold, design: .rounded))
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .jarvisGlass(tint: .accentColor, cornerRadius: JarvisMetrics.controlRadius)
            .contentShape(RoundedRectangle(cornerRadius: JarvisMetrics.controlRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct JarvisSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .opacity(configuration.isPressed ? 0.68 : 1)
            .jarvisGlass(cornerRadius: JarvisMetrics.controlRadius)
            .contentShape(RoundedRectangle(cornerRadius: JarvisMetrics.controlRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
