import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppModel
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
                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .top) {
            ZStack {
                TopNavigationBar(selection: selectedSectionBinding)

                HStack {
                    Spacer()
                    Button {
                        navigationSelection = .settings
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
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
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
            if let toastMessage = app.toastMessage {
                JarvisToast(message: toastMessage)
                    .padding(.bottom, 26)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .tint(.accentColor)
        .ignoresSafeArea(.container, edges: .top)
        .animation(.easeInOut(duration: 0.2), value: app.toastMessage)
        .onChange(of: app.selectedSection) { _, newSection in
            // Other entry points (quick actions, menu bar, screenshot flow)
            // still drive the app model. Reflect them in the navbar first;
            // the section task below will mount the page on the next turn.
            guard navigationSelection != newSection else { return }
            navigationSelection = newSection
        }
        .task(id: navigationSelection) {
            let nextSection = navigationSelection
            guard nextSection != loadedSection else {
                if app.selectedSection != nextSection {
                    app.selectedSection = nextSection
                }
                return
            }

            // Give SwiftUI one turn to commit the optimistic navbar state
            // before constructing the potentially heavier page hierarchy.
            await Task.yield()
            guard !Task.isCancelled, navigationSelection == nextSection else { return }
            loadedSection = nextSection
            app.selectedSection = nextSection
        }
    }

    private var selectedSectionBinding: Binding<AppSection?> {
        Binding(
            get: { navigationSelection },
            set: { newValue in
                guard let newValue else { return }
                // This is intentionally local and synchronous. The page
                // switch is deferred by the task above so the selected tab
                // responds before its destination is loaded.
                navigationSelection = newValue
            }
        )
    }

    @ViewBuilder
    private var detailView: some View {
        switch loadedSection {
        case .overview: DashboardView()
        case .skill(.screenshot): ScreenshotView()
        case .skill(.clipboard): ClipboardView()
        case .settings: SettingsView()
        }
    }
}

private struct TopNavigationBar: View {
    @Binding var selection: AppSection?

    private let sections: [AppSection] = [
        .overview,
        .skill(.screenshot),
        .skill(.clipboard)
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(sections) { section in
                Button {
                    selection = section
                } label: {
                    Text(section.navigationTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selection == section ? Color.white : Color.secondary)
                        .frame(minWidth: 64, minHeight: 34)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Capsule())
                        .background(
                            selection == section ? Color.accentColor.opacity(0.82) : .clear,
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
                .help(section.navigationTitle)
            }
        }
        .padding(3)
        .jarvisGlass(in: Capsule(), interactive: false)
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
                        Text("剪贴板历史保存在本机；截图文字先由 macOS 在本地识别，只有识别出的文字会在你主动翻译时发送给配置的 API 服务商。")
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
