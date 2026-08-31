import SwiftUI

enum WindowLayoutDisplayMetrics {
    static let diagramWidth: CGFloat = 44
    static let cardContentSpacing: CGFloat = 12
    static let cardHorizontalPadding: CGFloat = 28
    static let minimumTitleWidth: CGFloat = 52
    static let shortcutPartWidth: CGFloat = 13
    static let shortcutPartSpacing: CGFloat = 4
    static let maximumShortcutPartCount = 3
    static let gridSpacing: CGFloat = 12

    static var shortcutWidth: CGFloat {
        (shortcutPartWidth * CGFloat(maximumShortcutPartCount))
            + (shortcutPartSpacing * CGFloat(maximumShortcutPartCount - 1))
    }

    static var minimumCardWidth: CGFloat {
        cardHorizontalPadding
            + diagramWidth
            + cardContentSpacing
            + minimumTitleWidth
            + shortcutWidth
    }

    static var minimumGridWidth: CGFloat {
        (minimumCardWidth * 2) + gridSpacing
    }
}

struct WindowLayoutView: View {
    private let layouts: [WindowLayout] = [
        .halfLeft,
        .halfRight,
        .upperLeft,
        .upperRight,
        .lowerLeft,
        .lowerRight
    ]

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                ToolbarItem(placement: .navigation) {
                    EmptyView()
                }
            },
            trailingToolbar: {
                ToolbarItem(placement: .automatic) {
                    EmptyView()
                }
            },
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        introductionCard
                        layoutGrid
                    }
                    .frame(maxWidth: 980, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(JarvisMetrics.pageInset)
                }
            }
        )
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
                        .font(JarvisTypography.bodyEmphasis)
                    Text("快捷键提示仅用于展示；请从菜单栏执行窗口调整。")
                        .font(JarvisTypography.secondary)
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .lineSpacing(2)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var layoutGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .flexible(minimum: WindowLayoutDisplayMetrics.minimumCardWidth),
                    spacing: WindowLayoutDisplayMetrics.gridSpacing
                ),
                GridItem(
                    .flexible(minimum: WindowLayoutDisplayMetrics.minimumCardWidth),
                    spacing: WindowLayoutDisplayMetrics.gridSpacing
                )
            ],
            spacing: WindowLayoutDisplayMetrics.gridSpacing
        ) {
            ForEach(layouts) { layout in
                WindowLayoutDisplayCard(layout: layout)
            }
        }
    }
}

private struct WindowLayoutDisplayCard: View {
    let layout: WindowLayout

    var body: some View {
        HStack(spacing: 12) {
            WindowLayoutDiagram(layout: layout)
            Text(layout.title)
                .font(JarvisTypography.bodyEmphasis)
            Spacer(minLength: 0)
            WindowLayoutShortcutLabel(layout: layout)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisGlass(cornerRadius: 13)
        .jarvisHoverPanelFeedback(scale: 1.012)
        .accessibilityElement(children: .combine)
    }
}

private struct WindowLayoutShortcutLabel: View {
    let layout: WindowLayout

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(layout.shortcutDisplayParts.enumerated()), id: \.offset) { _, part in
                Text(part)
                    .font(JarvisTypography.monospaced)
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
