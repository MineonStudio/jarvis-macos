import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigationSelection: TopLevelSection = .overview
    @State private var selectedSkill: SkillID = .screenshot
    @State private var selectedSidebarSecondary: SidebarSecondaryItem = .skill(.screenshot)
    @State private var loadedSection: AppSection = .overview
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            JarvisSidebarNavigation(
                items: primaryNavigationItems,
                selection: selectedSectionBinding,
                title: { $0.title },
                icon: { $0.icon },
                secondaryMenus: secondaryMenus,
                secondarySelection: selectedSidebarSecondaryBinding,
                secondaryTitle: { $0.title },
                secondaryIcon: sidebarSecondaryIcon,
                footerTitle: "设置",
                footerIcon: "gearshape",
                footerIsSelected: navigationSelection == .settings,
                footerAction: { selectSection(.settings) }
            )
            .background(Color.jarvisBackground)
            .navigationSplitViewColumnWidth(
                min: JarvisMetrics.sidebarMinimumWidth,
                ideal: JarvisMetrics.sidebarWidth,
                max: JarvisMetrics.sidebarMaximumWidth
            )
        } detail: {
            loadedSectionView
                .id(loadedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            JarvisToastHost(message: app.toastMessage)
                .padding(.bottom, 26)
        }
        .tint(.accentColor)
        .animation(
            JarvisMotion.animation(JarvisMotion.feedback, reduceMotion: reduceMotion),
            value: app.toastMessage
        )
        .onChange(of: app.selectedSection) { _, newSection in
            // Other entry points (quick actions, menu bar, screenshot flow)
            // still drive the app model. Reflect them in the navbar immediately;
            // the section task below mounts the page after the tab settles.
            switch newSection {
            case let .skill(skill):
                selectedSkill = skill
                selectedSidebarSecondary = .skill(skill)
                navigationSelection = .skillLibrary
            case .overview:
                navigationSelection = .overview
            case .aiConversation:
                selectedSidebarSecondary = .aiProvider(app.selectedAIProvider)
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
                    try await Task.sleep(nanoseconds: 180_000_000)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled, nextSection == contentSection(for: navigationSelection) else { return }
            if reduceMotion {
                loadedSection = nextSection
            } else {
                // The sidebar indicator has settled. Replace the page in one
                // transaction so old and new module hierarchies never overlap.
                loadedSection = nextSection
            }
        }
        .onChange(of: app.selectedAIProvider) { _, provider in
            guard navigationSelection == .aiConversation else { return }
            selectedSidebarSecondary = .aiProvider(provider)
        }
    }

    private func selectSection(_ section: TopLevelSection) {
        guard navigationSelection != section || app.selectedSection != section.appSection else { return }
        navigationSelection = section
        switch section {
        case .skillLibrary:
            selectedSkill = .screenshot
            selectedSidebarSecondary = .skill(.screenshot)
            app.selectedSection = .skill(.screenshot)
        case .aiConversation:
            selectedSidebarSecondary = .aiProvider(app.selectedAIProvider)
            app.selectedSection = section.appSection
        case .overview, .settings:
            app.selectedSection = section.appSection
        }
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

    private var secondaryMenus: [JarvisSidebarSecondaryMenu<TopLevelSection, SidebarSecondaryItem>] {
        [
            JarvisSidebarSecondaryMenu(
                parent: .aiConversation,
                items: AIConversationProvider.allCases.map { .aiProvider($0) }
            ),
            JarvisSidebarSecondaryMenu(
                parent: .skillLibrary,
                items: SkillID.allCases.map { .skill($0) }
            )
        ]
    }

    private var selectedSidebarSecondaryBinding: Binding<SidebarSecondaryItem> {
        Binding(
            get: { selectedSidebarSecondary },
            set: { selectSidebarSecondary($0) }
        )
    }

    private func sidebarSecondaryIcon(
        _ item: SidebarSecondaryItem,
        isSelected: Bool
    ) -> AnyView {
        switch item {
        case let .skill(skill):
            AnyView(Image(systemName: skill.icon))
        case let .aiProvider(provider):
            AnyView(AIConversationProviderIcon(provider: provider, isSelected: isSelected))
        }
    }

    private func selectSidebarSecondary(_ item: SidebarSecondaryItem) {
        guard selectedSidebarSecondary != item else { return }
        selectedSidebarSecondary = item

        switch item {
        case let .skill(skill):
            selectedSkill = skill
            navigationSelection = .skillLibrary
            app.selectedSection = .skill(skill)
        case let .aiProvider(provider):
            navigationSelection = .aiConversation
            app.selectedAIProvider = provider
            app.selectedSection = .aiConversation
        }
    }

    private var navigationTargetID: String {
        "\(navigationSelection.id)|\(selectedSkill.id)"
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
        case .skill(.resume): ResumeContentView()
        case .settings: SettingsView()
        }
    }

    private var loadedSectionView: some View {
        selectedContentView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedContentView: some View {
        detailView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            JarvisMotion.animation(JarvisMotion.feedback, reduceMotion: reduceMotion),
            value: message
        )
    }
}

enum SidebarSecondaryItem: Hashable, Identifiable {
    case skill(SkillID)
    case aiProvider(AIConversationProvider)

    var id: String {
        switch self {
        case let .skill(skill): "skill.\(skill.id)"
        case let .aiProvider(provider): "ai.\(provider.id)"
        }
    }

    var title: String {
        switch self {
        case let .skill(skill): skill.navigationTitle
        case let .aiProvider(provider): provider.title
        }
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

struct DashboardView: View {
    @EnvironmentObject private var app: AppModel

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
                    VStack(alignment: .leading, spacing: 28) {
                        JarvisOrbView()

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
                    }
                    .frame(maxWidth: 980, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(JarvisMetrics.pageInset)
                }
            }
        )
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        .contentTransition(.numericText())
                        .animation(
                            JarvisMotion.animation(JarvisMotion.feedback, reduceMotion: reduceMotion),
                            value: value
                        )
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
