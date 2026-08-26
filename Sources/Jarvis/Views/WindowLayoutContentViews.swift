import SwiftUI

struct WindowLayoutView: View {
    @EnvironmentObject private var app: AppModel

    private let layouts: [WindowLayout] = [
        .halfLeft,
        .halfRight,
        .upperLeft,
        .upperRight,
        .lowerLeft,
        .lowerRight
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(title: "窗口布局")

                introductionCard
                layoutGrid
            }
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(JarvisMetrics.pageInset)
        }
    }

    private var introductionCard: some View {
        JarvisCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .jarvisIconGlass(in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text("把当前窗口快速放到屏幕的指定区域")
                        .font(.system(size: 14, weight: .semibold))
                    Text("快捷键提示仅用于展示；请点击下方布局卡片，或从菜单栏执行窗口调整。")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .lineSpacing(2)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var layoutGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(layouts) { layout in
                WindowLayoutActionCard(layout: layout) {
                    app.applyWindowLayout(layout)
                }
            }
        }
    }
}

private struct WindowLayoutActionCard: View {
    let layout: WindowLayout
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                WindowLayoutDiagram(layout: layout)
                Text(layout.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                WindowLayoutShortcutLabel(layout: layout)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .jarvisGlass(cornerRadius: 13)
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.86))
        .jarvisHoverFeedback(
            in: RoundedRectangle(cornerRadius: 13, style: .continuous),
            scale: 1.008
        )
    }
}

private struct WindowLayoutShortcutLabel: View {
    let layout: WindowLayout

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(layout.shortcutDisplayParts.enumerated()), id: \.offset) { _, part in
                Text(part)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .frame(minWidth: 13)
            }
        }
        .foregroundStyle(Color.jarvisTextSecondary)
        .fixedSize()
    }
}

private struct WindowLayoutDiagram: View {
    let layout: WindowLayout

    private var fillAlignment: Alignment {
        switch layout {
        case .halfLeft: .leading
        case .halfRight: .trailing
        case .upperLeft: .topLeading
        case .upperRight: .topTrailing
        case .lowerLeft: .bottomLeading
        case .lowerRight: .bottomTrailing
        }
    }

    private var fillHeightRatio: CGFloat {
        switch layout {
        case .halfLeft, .halfRight: 1
        case .upperLeft, .upperRight, .lowerLeft, .lowerRight: 0.5
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 2
            let width = max(0, geometry.size.width - inset * 2)
            let height = max(0, geometry.size.height - inset * 2)

            ZStack(alignment: fillAlignment) {
                Color.clear
                Rectangle()
                    .fill(Color.accentColor.opacity(0.9))
                    .frame(width: width / 2, height: height * fillHeightRatio)
            }
            .padding(inset)
            .overlay {
                Rectangle()
                    .strokeBorder(Color.primary.opacity(0.72), lineWidth: 1)
            }
        }
        .frame(width: 44, height: 24.75)
    }
}
