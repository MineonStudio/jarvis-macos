import SwiftUI

struct JarvisOrbMark: View {
    @Environment(\.colorScheme) private var colorScheme

    let diameter: CGFloat

    init(diameter: CGFloat = 24) {
        self.diameter = diameter
    }

    private var orbColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var eyeColor: Color {
        colorScheme == .dark ? .black : .white
    }

    var body: some View {
        Circle()
            .fill(orbColor)
            .overlay {
                HStack(spacing: diameter * 0.174) {
                    Capsule()
                        .fill(eyeColor)
                        .frame(width: diameter * 0.152, height: diameter * 0.319)
                    Capsule()
                        .fill(eyeColor)
                        .frame(width: diameter * 0.152, height: diameter * 0.319)
                }
                .offset(y: -diameter * 0.138)
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.16),
                radius: diameter * 0.08,
                y: diameter * 0.043
            )
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}
