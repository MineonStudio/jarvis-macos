import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigationSelection: TopLevelSection = .home
    @State private var loadedSection: AppSection = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            JarvisSidebarNavigation(
                topItems: topNavigationItems,
                bottomItems: bottomNavigationItems,
                selection: selectedSectionBinding,
                title: { $0.title },
                icon: { $0.icon },
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
                navigationSelection = .skill(skill)
            case .home:
                navigationSelection = .home
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
            // The sidebar indicator has settled. Replace the page in one
            // transaction so old and new module hierarchies never overlap.
            loadedSection = nextSection
        }
    }

    private func selectSection(_ section: TopLevelSection) {
        guard navigationSelection != section || app.selectedSection != section.appSection else { return }
        navigationSelection = section
        app.selectedSection = section.appSection
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
        [.home] + SkillID.allCases.map(TopLevelSection.skill)
    }

    private var bottomNavigationItems: [TopLevelSection] {
        [.aiConversation, .entertainment]
    }

    private var navigationTargetID: String {
        switch navigationSelection {
        case .home:
            "home"
        case let .skill(skill):
            "skill|\(skill.id)"
        case .aiConversation:
            "ai-conversation|\(app.selectedAIProvider.id)"
        case .entertainment:
            "entertainment|\(app.selectedEntertainmentPlatform.id)"
        case .settings:
            "settings"
        }
    }

    private func contentSection(for section: TopLevelSection) -> AppSection {
        switch section {
        case .home:
            .home
        case let .skill(skill):
            .skill(skill)
        case .aiConversation:
            .aiConversation
        case .entertainment:
            .entertainment
        case .settings:
            .settings
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch loadedSection {
        case .home: JarvisHomeView()
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

private enum TopLevelSection: Hashable, Identifiable {
    case home
    case skill(SkillID)
    case aiConversation
    case entertainment
    case settings

    var id: String {
        switch self {
        case .home: "home"
        case let .skill(skill): "skill.\(skill.id)"
        case .aiConversation: "ai-conversation"
        case .entertainment: "entertainment"
        case .settings: "settings"
        }
    }

    var title: String {
        switch self {
        case .home: "首页"
        case let .skill(skill): skill.navigationTitle
        case .aiConversation: "AI聚合"
        case .entertainment: "娱乐广场"
        case .settings: "设置"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case let .skill(skill): skill.icon
        case .aiConversation: "sparkles"
        case .entertainment: "play.rectangle"
        case .settings: "gearshape"
        }
    }

    var appSection: AppSection {
        switch self {
        case .home: .home
        case let .skill(skill): .skill(skill)
        case .aiConversation: .aiConversation
        case .entertainment: .entertainment
        case .settings: .settings
        }
    }
}
