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
        let isAlreadyShowing: Bool = switch item {
        case let .skill(skill):
            navigationSelection == .skillLibrary && app.selectedSection == .skill(skill)
        case let .aiProvider(provider):
            navigationSelection == .aiConversation
                && app.selectedSection == .aiConversation
                && app.selectedAIProvider == provider
        }
        guard !isAlreadyShowing else { return }

        selectedSidebarSecondary = item

        switch item {
        case let .skill(skill):
            selectedSkill = skill
            navigationSelection = .skillLibrary
            app.selectedSection = .skill(skill)
        case let .aiProvider(provider):
            navigationSelection = .aiConversation
            app.selectAIProvider(provider)
            app.selectedSection = .aiConversation
        }
    }

    private var navigationTargetID: String {
        switch navigationSelection {
        case .skillLibrary:
            "skill-library|\(selectedSkill.id)"
        case .aiConversation:
            "ai-conversation|\(app.selectedAIProvider.id)"
        case .overview, .settings:
            navigationSelection.id
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
        case .skill(.resume): ResumeContentView()
        case .skill(.wallpaper): WallpaperView()
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
        case .overview: "首页"
        case .aiConversation: "第三方AI平台"
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
                GeometryReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            JarvisOrbView()

                            dailyQuoteCard

                            Spacer(minLength: 0)

                            permissionStatusRow
                        }
                        .frame(
                            maxWidth: 980,
                            minHeight: max(0, proxy.size.height - JarvisMetrics.pageInset * 2),
                            alignment: .top
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(JarvisMetrics.pageInset)
                    }
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

    private var dailyQuoteCard: some View {
        Text("“\(app.dailyQuote.text)”")
            .font(.system(size: 50, weight: .bold))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.primary)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("每日语录，\(app.dailyQuote.text)")
            .onAppear {
                app.refreshDailyQuote()
            }
    }

    private var permissionStatusRow: some View {
        HStack(spacing: 10) {
            DashboardPermissionCapsule(
                title: "屏幕录制",
                isGranted: app.screenCapturePermissionGranted,
                action: { _ = app.requestScreenCapturePermission() }
            )
            DashboardPermissionCapsule(
                title: "辅助功能",
                isGranted: app.accessibilityPermissionGranted,
                action: app.requestAccessibilityPermission
            )
            DashboardPermissionCapsule(
                title: "麦克风",
                isGranted: app.microphonePermissionGranted,
                action: app.requestMicrophonePermission
            )
            DashboardPermissionCapsule(
                title: "摄像头",
                isGranted: app.cameraPermissionGranted,
                action: app.requestCameraPermission
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct DashboardPermissionCapsule: View {
    let title: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(JarvisTypography.captionEmphasis)
                    .foregroundStyle(Color.primary)
                Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isGranted ? Color.green : Color.orange)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill((isGranted ? Color.green : Color.orange).opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke((isGranted ? Color.green : Color.orange).opacity(0.20), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isGranted)
        .accessibilityLabel("\(title)，\(isGranted ? "已授权" : "需要授权")")
        .help(isGranted ? "\(title)已授权" : "点击获取\(title)权限")
    }
}
