import SwiftUI

struct HistoryFilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text("\(title)（\(count)）")
                .font(JarvisTypography.control)
                .foregroundStyle(isSelected ? Color.accentColor : Color.jarvisTextSecondary)
                .padding(.horizontal, HistoryGridMetrics.filterChipHorizontalPadding)
                .padding(.vertical, HistoryGridMetrics.filterChipVerticalPadding)
                .frame(height: HistoryGridMetrics.filterChipHeight)
                .background(
                    isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.045),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .strokeBorder(
                            Color.primary.opacity(isSelected ? 0.16 : 0.08),
                            lineWidth: 0.75
                        )
                }
                .contentShape(Capsule())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.82))
        .contentShape(Capsule())
        .jarvisHoverFeedback(in: Capsule(), scale: 1.02)
        .animation(
            JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
            value: isSelected
        )
    }
}
