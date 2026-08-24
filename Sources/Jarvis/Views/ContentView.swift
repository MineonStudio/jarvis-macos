import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigationSelection: AppSection = .overview
    @State private var loadedSection: AppSection = .overview

    var body: some View {
        ZStack(alignment: .top) {
            Color.jarvisBackground

            VStack(spacing: 0) {
                // Preserve the original content position while allowing the
                // navbar to be composited above the body instead of behind it.
                Color.clear
                    .frame(height: 102)
                ZStack {
                    detailView
                        .id(loadedSection)
                        .transition(.opacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .top) {
            ZStack {
                TopNavigationBar(selection: selectedSectionBinding)

                HStack {
                    Spacer()
                    Button {
                        selectSection(.settings)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 36, height: 36)
                            .foregroundStyle(
                                navigationSelection == .settings ? Color.white : Color.secondary
                            )
                            .background(
                                navigationSelection == .settings
                                    ? Color.accentColor.opacity(0.82)
                                    : .clear,
                                in: Circle()
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.76))
                    .contentShape(Rectangle())
                    .jarvisHoverFeedback(in: Circle(), scale: 1.04)
                    .help("设置")
                }
                .padding(.horizontal, 28)
            }
            .frame(height: 70)
            // The window uses a full-size transparent title bar. Keep the
            // capsule below the native traffic lights instead of letting it
            // occupy the same top strip.
            .padding(.top, 32)
            .zIndex(1)
        }
        .overlay(alignment: .bottom) {
            JarvisToastHost(message: app.toastMessage)
                .padding(.bottom, 26)
        }
        .tint(.accentColor)
        .ignoresSafeArea(.container, edges: .top)
        .animation(
            JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
            value: app.toastMessage
        )
        .onChange(of: app.selectedSection) { _, newSection in
            // Other entry points (quick actions, menu bar, screenshot flow)
            // still drive the app model. Reflect them in the navbar immediately;
            // the section task below mounts the page after the tab settles.
            guard navigationSelection != newSection else { return }
            navigationSelection = newSection
        }
        .task(id: navigationSelection) {
            let nextSection = navigationSelection
            guard nextSection != loadedSection else { return }

            // Let the navigation indicator finish its interaction animation
            // before mounting a potentially heavy page hierarchy such as the
            // AI WebView. The tab selection itself is already committed.
            if !reduceMotion {
                do {
                    try await Task.sleep(nanoseconds: 240_000_000)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled, navigationSelection == nextSection else { return }
            if reduceMotion {
                loadedSection = nextSection
            } else {
                withAnimation(JarvisMotion.pageTransition) {
                    loadedSection = nextSection
                }
            }
        }
    }

    private func selectSection(_ section: AppSection) {
        guard navigationSelection != section || app.selectedSection != section else { return }
        navigationSelection = section
        app.selectedSection = section
    }

    private var selectedSectionBinding: Binding<AppSection> {
        Binding(
            get: { navigationSelection },
            set: { newValue in
                // Commit the navigation state synchronously. The page
                // switch is deferred by the task above so heavy module
                // construction cannot delay the selected tab.
                selectSection(newValue)
            }
        )
    }

    @ViewBuilder
    private var detailView: some View {
        switch loadedSection {
        case .overview: DashboardView()
        case .aiConversation: AIConversationView()
        case .skill(.screenshot): ScreenshotView()
        case .skill(.clipboard): ClipboardView()
        case .settings: SettingsView()
        }
    }
}

struct JarvisToastHost: View {
    let message: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let message {
                JarvisToast(message: message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(
            JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
            value: message
        )
    }
}

private struct TopNavigationBar: View {
    @Binding var selection: AppSection

    private let sections: [AppSection] = [
        .overview,
        .aiConversation,
        .skill(.screenshot),
        .skill(.clipboard)
    ]

    var body: some View {
        JarvisSegmentedControl(items: sections, selection: $selection) { section, isSelected in
            Text(section.navigationTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(
                    minWidth: 70,
                    minHeight: JarvisMetrics.segmentedItemHeight,
                    maxHeight: JarvisMetrics.segmentedItemHeight
                )
                .padding(.horizontal, 10)
                .padding(.vertical, JarvisMetrics.topNavigationVerticalPadding)
                .help(section.navigationTitle)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 20, y: 9)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    SectionHeader(title: "你好，贾维斯")
                    Spacer()
                    StatusPill(
                        text: app.hasAPIKey ? "API 已连接" : "未配置 API",
                        color: app.hasAPIKey ? .accentColor : .secondary,
                        usesTint: app.hasAPIKey
                    )
                }

                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("快捷操作")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(app.statusMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }

                    HStack(spacing: 10) {
                        QuickActionButton(title: "框选截图", icon: "viewfinder", tint: .accentColor) {
                            // This is an in-window action, so it may move the
                            // main window to the screenshot tab explicitly.
                            app.selectedSection = .skill(.screenshot)
                            app.captureScreenshot()
                        }
                        QuickActionButton(title: "打开剪贴板", icon: "clipboard", tint: .accentColor) {
                            app.selectedSection = .skill(.clipboard)
                        }
                        QuickActionButton(title: "模型设置", icon: "brain.head.profile", tint: .accentColor) {
                            app.selectedSection = .settings
                        }
                    }
                }

                Divider()
                    .overlay(Color.primary.opacity(0.10))

                HStack(spacing: 0) {
                    DashboardMetric(title: "截图", value: "\(app.screenshotHistory.count)", detail: "历史记录", icon: "photo")
                    dashboardDivider
                    DashboardMetric(title: "剪贴板", value: "\(app.clipboardItems.count)", detail: "本地记录", icon: "clipboard")
                    dashboardDivider
                    DashboardMetric(title: "技能", value: "\(SkillID.allCases.count)", detail: "已启用", icon: "puzzlepiece.extension")
                }

                Divider()
                    .overlay(Color.primary.opacity(0.10))

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28, height: 28)
                        .jarvisIconGlass(in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("本机优先")
                            .font(.system(size: 13, weight: .semibold))
                        Text("剪贴板历史保存在本机；只有主动点击截图翻译时，截图才会发送给配置的 API 服务商，由大模型识别并翻译。")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.jarvisTextSecondary)
                            .lineSpacing(2)
                    }
                    Spacer(minLength: 12)
                    Text("隐私")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(JarvisMetrics.pageInset)
        }
    }

    private var dashboardDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(width: 1, height: 44)
            .padding(.horizontal, 22)
    }
}

struct DashboardMetric: View {
    let title: String
    let value: String
    let detail: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .jarvisIconGlass(in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(value)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.jarvisTextSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
