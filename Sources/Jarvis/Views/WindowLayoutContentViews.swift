import AppKit
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
                permissionCard
            }
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(JarvisMetrics.pageInset)
        }
        .onAppear {
            app.refreshWindowLayoutAccessibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshWindowLayoutAccessibility()
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
                    Text("使用与 Tiles 一致的 ⌥⌘ 快捷键：方向键切换左右半屏，U/I/J/K 切换四个角落。")
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

    private var permissionCard: some View {
        JarvisCard {
            HStack(spacing: 12) {
                Image(systemName: app.windowLayoutAccessibilityTrusted ? "checkmark.shield.fill" : "lock.shield")
                    .foregroundStyle(app.windowLayoutAccessibilityTrusted ? Color.green : Color.orange)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.windowLayoutAccessibilityTrusted ? "辅助功能权限已开启" : "需要辅助功能权限")
                        .font(.system(size: 13, weight: .semibold))
                    Text("只有获得权限后，贾维斯才能调整其他应用的窗口位置和大小。")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
                Spacer(minLength: 8)
                if !app.windowLayoutAccessibilityTrusted {
                    Button("打开系统设置") {
                        app.openWindowLayoutAccessibilitySettings()
                    }
                    .buttonStyle(JarvisSecondaryButtonStyle())
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
                Image(systemName: layout.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .jarvisIconGlass(in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(layout.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(layout.shortcutDisplay)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.jarvisTextSecondary)
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
