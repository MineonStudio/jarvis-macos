import AppKit
import SwiftUI

// MARK: - Jarvis visual language

enum JarvisTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var appKitAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

struct JarvisThemeModifier: ViewModifier {
    let theme: JarvisTheme

    @ViewBuilder
    func body(content: Content) -> some View {
        switch theme {
        case .system:
            content
        case .light:
            content.preferredColorScheme(.light)
        case .dark:
            content.preferredColorScheme(.dark)
        }
    }
}

extension Color {
    // Keep these names stable for the rest of the app, but use semantic system
    // colors instead of a fixed dark palette so the window follows macOS.
    static let jarvisBackground = Color(nsColor: .textBackgroundColor)
    static let jarvisPanel = Color(nsColor: .controlBackgroundColor)
    static let jarvisPanelLight = Color(nsColor: .windowBackgroundColor)
    static let jarvisCyan = Color.accentColor
    static let jarvisPurple = Color.accentColor
    static let jarvisTextSecondary = Color.secondary
}

enum JarvisMetrics {
    static let pageInset: CGFloat = 30
    static let windowRadius: CGFloat = 16
    static let cardRadius: CGFloat = 14
    static let controlRadius: CGFloat = 10
    static let iconTintOpacity: CGFloat = 0.22
}

struct JarvisCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .jarvisGlass(cornerRadius: JarvisMetrics.cardRadius, interactive: false)
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.jarvisTextSecondary)
        }
    }
}

/// A small compatibility wrapper for custom controls. On macOS 26 it uses the
/// native Liquid Glass effect; on older supported systems it keeps the same
/// geometry and falls back to the standard system material.
struct JarvisGlassModifier: ViewModifier {
    let tint: Color?
    let cornerRadius: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
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
        } else {
            content
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
                }
        }
    }
}

struct JarvisGlassShapeModifier<GlassShape: Shape>: ViewModifier {
    let tint: Color?
    let shape: GlassShape
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
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
        } else {
            content
                .background(.thinMaterial, in: shape)
                .overlay {
                    shape.stroke(Color.primary.opacity(0.12), lineWidth: 0.75)
                }
        }
    }
}

extension View {
    func jarvisTheme(_ theme: JarvisTheme) -> some View {
        modifier(JarvisThemeModifier(theme: theme))
    }

    func jarvisGlass(
        tint: Color? = nil,
        cornerRadius: CGFloat = JarvisMetrics.controlRadius,
        interactive: Bool = true
    ) -> some View {
        modifier(JarvisGlassModifier(tint: tint, cornerRadius: cornerRadius, interactive: interactive))
    }

    func jarvisGlass<GlassShape: Shape>(
        tint: Color? = nil,
        in shape: GlassShape,
        interactive: Bool = true
    ) -> some View {
        modifier(JarvisGlassShapeModifier(tint: tint, shape: shape, interactive: interactive))
    }

    /// A lighter Liquid Glass treatment for the small icon containers used
    /// throughout the pages. Full-strength accent tint makes these bubbles
    /// read as solid dark badges instead of translucent glass.
    func jarvisIconGlass<GlassShape: Shape>(
        tint: Color = .accentColor,
        in shape: GlassShape,
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
