import SwiftUI

enum JarvisGlassRenderer {
    @ViewBuilder
    static func render<Content: View>(
        _ content: Content,
        tint: Color?,
        cornerRadius: CGFloat,
        interactive: Bool
    ) -> some View {
#if swift(>=6.2)
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
            fallback(content, tint: tint, shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
#else
        fallback(content, tint: tint, shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
#endif
    }

    @ViewBuilder
    static func render<Content: View, Shape: SwiftUI.Shape>(
        _ content: Content,
        tint: Color?,
        shape: Shape,
        interactive: Bool
    ) -> some View {
#if swift(>=6.2)
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
            fallback(content, tint: tint, shape: shape)
        }
#else
        fallback(content, tint: tint, shape: shape)
#endif
    }

    private static func fallback<Content: View, Shape: SwiftUI.Shape>(
        _ content: Content,
        tint _: Color?,
        shape: Shape
    ) -> some View {
        content
            .background(.thinMaterial, in: shape)
            .overlay {
                shape.stroke(Color.primary.opacity(0.12), lineWidth: 0.75)
            }
    }
}
