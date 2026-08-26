import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigationSelection: TopLevelSection = .overview
    @State private var selectedSkill: SkillID = .screenshot
    @State private var loadedSection: AppSection = .overview

    var body: some View {
        NavigationSplitView {
            JarvisSidebarNavigation(
                items: primaryNavigationItems,
                selection: selectedSectionBinding,
                title: { $0.title },
                icon: { $0.icon },
                footerTitle: "设置",
                footerIcon: "gearshape",
                footerIsSelected: navigationSelection == .settings,
                footerAction: { selectSection(.settings) }
            )
            .navigationSplitViewColumnWidth(
                min: JarvisMetrics.sidebarMinimumWidth,
                ideal: JarvisMetrics.sidebarWidth,
                max: JarvisMetrics.sidebarMaximumWidth
            )
        } detail: {
            loadedSectionView
                .id(loadedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.leading, JarvisMetrics.shellContentSpacing)
                .padding(.trailing, JarvisMetrics.shellHorizontalPadding)
                .padding(.vertical, JarvisMetrics.shellVerticalPadding)
                .background(Color.jarvisBackground)
                .ignoresSafeArea(
                    .container,
                    edges: detailExtendsIntoTitlebar ? .top : []
                )
        }
        .overlay(alignment: .bottom) {
            JarvisToastHost(message: app.toastMessage)
                .padding(.bottom, 26)
        }
        .tint(.accentColor)
        .animation(
            JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
            value: app.toastMessage
        )
        .onChange(of: app.selectedSection) { _, newSection in
            // Other entry points (quick actions, menu bar, screenshot flow)
            // still drive the app model. Reflect them in the navbar immediately;
            // the section task below mounts the page after the tab settles.
            switch newSection {
            case let .skill(skill):
                selectedSkill = skill
                navigationSelection = .skillLibrary
            case .overview:
                navigationSelection = .overview
            case .aiConversation:
                navigationSelection = .aiConversation
            case .settings:
                navigationSelection = .settings
            }
        }
        .task(id: navigationTargetID) {
            let nextSection = contentSection(for: navigationSelection)
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
            guard !Task.isCancelled, nextSection == contentSection(for: navigationSelection) else { return }
            if reduceMotion {
                loadedSection = nextSection
            } else {
                // Replace the top bar and its page atomically. A cross-fade
                // would keep the old and new mutually exclusive tab sets
                // composited together for part of the transition.
                loadedSection = nextSection
            }
        }
    }

    private func selectSection(_ section: TopLevelSection) {
        guard navigationSelection != section || app.selectedSection != section.appSection else { return }
        navigationSelection = section
        switch section {
        case .skillLibrary:
            app.selectedSection = .skill(selectedSkill)
        case .overview, .aiConversation, .settings:
            app.selectedSection = section.appSection
        }
    }

    private func selectSkill(_ skill: SkillID) {
        guard selectedSkill != skill else { return }
        selectedSkill = skill
        guard navigationSelection == .skillLibrary else { return }
        app.selectedSection = .skill(skill)
    }

    private var selectedSectionBinding: Binding<TopLevelSection> {
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

    private var primaryNavigationItems: [TopLevelSection] {
        [.overview, .aiConversation, .skillLibrary]
    }

    private var selectedSkillBinding: Binding<SkillID> {
        Binding(
            get: { selectedSkill },
            set: { selectSkill($0) }
        )
    }

    private var navigationTargetID: String {
        "\(navigationSelection.id)|\(selectedSkill.id)"
    }

    private var detailExtendsIntoTitlebar: Bool {
        switch loadedSection {
        case .aiConversation, .skill:
            true
        case .overview, .settings:
            false
        }
    }

    private func contentSection(for section: TopLevelSection) -> AppSection {
        switch section {
        case .overview:
            .overview
        case .aiConversation:
            .aiConversation
        case .skillLibrary:
            .skill(selectedSkill)
        case .settings:
            .settings
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch loadedSection {
        case .overview: DashboardView()
        case .aiConversation: AIConversationView()
        case .skill(.screenshot): ScreenshotView()
        case .skill(.clipboard): ClipboardView()
        case .skill(.windowLayout): WindowLayoutView()
        case .settings: SettingsView()
        }
    }

    private var loadedSectionView: some View {
        VStack(spacing: 0) {
            topNavigationBar

            selectedContentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var topNavigationBar: some View {
        switch loadedSection {
        case .aiConversation:
            AIConversationTopBar()
        case .skill:
            JarvisTopBarContainer {
                SkillNavigationBar(selection: selectedSkillBinding)
            }
        case .overview, .settings:
            EmptyView()
        }
    }

    @ViewBuilder
    private var selectedContentView: some View {
        switch loadedSection {
        case .skill:
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .jarvisFloatingPanel(cornerRadius: 16)
        case .overview, .aiConversation, .settings:
            detailView
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

private enum TopLevelSection: Hashable, Identifiable {
    case overview
    case aiConversation
    case skillLibrary
    case settings

    var id: String {
        switch self {
        case .overview: "overview"
        case .aiConversation: "ai-conversation"
        case .skillLibrary: "skill-library"
        case .settings: "settings"
        }
    }

    var title: String {
        switch self {
        case .overview: "总览"
        case .aiConversation: "聊天"
        case .skillLibrary: "技能库"
        case .settings: "设置"
        }
    }

    var icon: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .aiConversation: "bubble.left.and.bubble.right"
        case .skillLibrary: "square.stack.3d.up"
        case .settings: "gearshape"
        }
    }

    var appSection: AppSection {
        switch self {
        case .overview: .overview
        case .aiConversation: .aiConversation
        case .skillLibrary: .skill(.screenshot)
        case .settings: .settings
        }
    }
}

private struct SkillNavigationBar: View {
    @Binding var selection: SkillID

    var body: some View {
        JarvisSegmentedControl(items: Array(SkillID.allCases), selection: $selection) { skill, isSelected in
            HStack(spacing: 7) {
                Image(systemName: skill.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(skill.navigationTitle)
            }
            .font(isSelected ? JarvisTypography.controlEmphasis : JarvisTypography.control)
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .frame(
                minHeight: JarvisMetrics.segmentedItemHeight,
                maxHeight: JarvisMetrics.segmentedItemHeight
            )
            .padding(.horizontal, 12)
            .padding(.vertical, JarvisMetrics.topNavigationVerticalPadding)
            .help(skill.navigationTitle)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 20, y: 9)
        .fixedSize(horizontal: true, vertical: false)
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
                }

                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("快捷操作")
                            .font(JarvisTypography.cardTitle)
                        Spacer()
                        Text(app.statusMessage)
                            .font(JarvisTypography.secondary)
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
                        QuickActionButton(title: "窗口布局", icon: "macwindow.on.rectangle", tint: .accentColor) {
                            app.selectedSection = .skill(.windowLayout)
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

                permissionCard

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28, height: 28)
                        .jarvisIconGlass(in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("本机优先")
                            .font(JarvisTypography.bodyEmphasis)
                        Text("剪贴板历史和截图历史均保存在本机。")
                            .font(JarvisTypography.secondary)
                            .foregroundStyle(Color.jarvisTextSecondary)
                            .lineSpacing(2)
                    }
                    Spacer(minLength: 12)
                    Text("隐私")
                        .font(JarvisTypography.captionEmphasis)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(JarvisMetrics.pageInset)
        }
        .onAppear {
            app.refreshPermissionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshPermissionStatus()
        }
    }

    private var permissionCard: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label("权限状态", systemImage: "lock.shield")
                        .font(JarvisTypography.bodyEmphasis)
                    Spacer()
                    Text(app.screenCapturePermissionGranted && app.accessibilityPermissionGranted ? "已就绪" : "需要授权")
                        .font(JarvisTypography.captionEmphasis)
                        .foregroundStyle(
                            app.screenCapturePermissionGranted && app.accessibilityPermissionGranted
                                ? Color.green
                                : Color.orange
                        )
                }

                DashboardPermissionRow(
                    title: "屏幕录制",
                    message: "用于冻结屏幕画面并完成框选截图。",
                    isGranted: app.screenCapturePermissionGranted,
                    action: { _ = app.requestScreenCapturePermission() }
                )
                DashboardPermissionRow(
                    title: "辅助功能",
                    message: "用于读取并调整其他应用的窗口位置和大小。",
                    isGranted: app.accessibilityPermissionGranted,
                    action: app.requestAccessibilityPermission
                )
            }
        }
    }

    private var dashboardDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(width: 1, height: 44)
            .padding(.horizontal, 22)
    }
}

private struct DashboardPermissionRow: View {
    let title: String
    let message: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isGranted ? Color.green : Color.orange)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(JarvisTypography.bodyEmphasis)
                Text(message)
                    .font(JarvisTypography.secondary)
                    .foregroundStyle(Color.jarvisTextSecondary)
            }

            Spacer(minLength: 8)

            if !isGranted {
                Button(action: action) {
                    Label("获取权限", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(JarvisSecondaryButtonStyle())
            }
        }
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
                        .font(JarvisTypography.metricValue)
                    Text(title)
                        .font(JarvisTypography.control)
                }
                Text(detail)
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.jarvisTextSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
