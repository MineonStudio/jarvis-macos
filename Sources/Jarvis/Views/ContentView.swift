import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigationSelection: TopLevelSection = .conversation
    @State private var selectedSkill: SkillID = .screenshot
    @State private var selectedSidebarSecondary: SidebarSecondaryItem = .skill(.screenshot)
    @State private var loadedSection: AppSection = .conversation
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            JarvisSidebarNavigation(
                topItems: topNavigationItems,
                bottomItems: bottomNavigationItems,
                selection: selectedSectionBinding,
                title: { $0.title },
                icon: { $0.icon },
                secondaryMenus: secondaryMenus,
                secondarySelection: selectedSidebarSecondaryBinding,
                secondaryTitle: sidebarSecondaryTitle,
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
            case .overview, .conversation:
                navigationSelection = .conversation
            case .aiConversation:
                navigationSelection = .aiConversation
            case .entertainment:
                navigationSelection = .entertainment
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
    }

    private func selectSection(_ section: TopLevelSection) {
        guard navigationSelection != section || app.selectedSection != section.appSection else { return }
        navigationSelection = section
        switch section {
        case .skillLibrary:
            selectedSkill = .screenshot
            selectedSidebarSecondary = .skill(.screenshot)
            app.selectedSection = .skill(.screenshot)
        case .conversation, .overview:
            app.selectedSection = .conversation
        case .aiConversation, .entertainment, .settings:
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

    private var topNavigationItems: [TopLevelSection] {
        [.conversation, .skillLibrary]
    }

    private var bottomNavigationItems: [TopLevelSection] {
        [.aiConversation, .entertainment]
    }

    private var secondaryMenus: [JarvisSidebarSecondaryMenu<TopLevelSection, SidebarSecondaryItem>] {
        [
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

    private func sidebarSecondaryTitle(_ item: SidebarSecondaryItem) -> String {
        switch item {
        case let .skill(skill):
            skill.navigationTitle
        }
    }

    private func sidebarSecondaryIcon(
        _ item: SidebarSecondaryItem,
        isSelected _: Bool
    ) -> AnyView {
        switch item {
        case let .skill(skill):
            AnyView(Image(systemName: skill.icon))
        }
    }

    private func selectSidebarSecondary(_ item: SidebarSecondaryItem) {
        let isAlreadyShowing: Bool = switch item {
        case let .skill(skill):
            navigationSelection == .skillLibrary && app.selectedSection == .skill(skill)
        }
        guard !isAlreadyShowing else { return }

        selectedSidebarSecondary = item

        switch item {
        case let .skill(skill):
            selectedSkill = skill
            navigationSelection = .skillLibrary
            app.selectedSection = .skill(skill)
        }
    }

    private var navigationTargetID: String {
        switch navigationSelection {
        case .skillLibrary:
            "skill-library|\(selectedSkill.id)"
        case .conversation, .overview:
            "conversation"
        case .aiConversation:
            "ai-conversation|\(app.selectedAIProvider.id)"
        case .entertainment:
            "entertainment|\(app.selectedEntertainmentPlatform.id)"
        case .settings:
            navigationSelection.id
        }
    }

    private func contentSection(for section: TopLevelSection) -> AppSection {
        switch section {
        case .overview, .conversation:
            .conversation
        case .aiConversation:
            .aiConversation
        case .entertainment:
            .entertainment
        case .skillLibrary:
            .skill(selectedSkill)
        case .settings:
            .settings
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch loadedSection {
        case .overview, .conversation: HermesConversationView()
        case .aiConversation: AIConversationView()
        case .entertainment: EntertainmentView()
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

    var id: String {
        switch self {
        case let .skill(skill): "skill.\(skill.id)"
        }
    }

    var title: String {
        switch self {
        case let .skill(skill): skill.navigationTitle
        }
    }
}

private enum TopLevelSection: Hashable, Identifiable {
    case overview
    case conversation
    case aiConversation
    case entertainment
    case skillLibrary
    case settings

    var id: String {
        switch self {
        case .overview: "overview"
        case .conversation: "conversation"
        case .aiConversation: "ai-conversation"
        case .entertainment: "entertainment"
        case .skillLibrary: "skill-library"
        case .settings: "settings"
        }
    }

    var title: String {
        switch self {
        case .overview: "首页"
        case .conversation: "对话"
        case .aiConversation: "AI聚合"
        case .entertainment: "娱乐广场"
        case .skillLibrary: "技能库"
        case .settings: "设置"
        }
    }

    var icon: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .conversation: "bubble.left.and.bubble.right"
        case .aiConversation: "sparkles"
        case .entertainment: "play.rectangle"
        case .skillLibrary: "square.stack.3d.up"
        case .settings: "gearshape"
        }
    }

    var appSection: AppSection {
        switch self {
        case .overview: .overview
        case .conversation: .conversation
        case .aiConversation: .aiConversation
        case .entertainment: .entertainment
        case .skillLibrary: .skill(.screenshot)
        case .settings: .settings
        }
    }
}
