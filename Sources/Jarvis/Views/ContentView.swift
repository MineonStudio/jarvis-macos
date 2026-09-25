import AppKit
import SwiftUI

struct ContentView: View {
    static let homePointerCoordinateSpace = "jarvis.main-window"

    @Binding var isSettingsPresented: Bool
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigationSelection: TopLevelSection = .home
    @State private var loadedSection: AppSection = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var homePointerTracker = JarvisHomePointerTracker()

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
                footerIsSelected: false,
                footerAction: { isSettingsPresented = true }
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
        .jarvisToastOverlay(app.toastMessage)
        .tint(app.accentColorPreference.resolvedColor)
        .coordinateSpace(name: Self.homePointerCoordinateSpace)
        .onContinuousHover(coordinateSpace: .named(Self.homePointerCoordinateSpace)) { phase in
            guard loadedSection == .home else {
                homePointerTracker.location = nil
                return
            }
            if case let .active(location) = phase {
                homePointerTracker.location = location
            } else {
                homePointerTracker.location = nil
            }
        }
        .onChange(of: loadedSection) { _, section in
            if section != .home {
                homePointerTracker.location = nil
            }
        }
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
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch loadedSection {
        case .home: JarvisHomeView(pointerTracker: homePointerTracker)
        case .aiConversation: AIConversationView()
        case .entertainment: EntertainmentView()
        case .skill(.screenshot): ScreenshotView()
        case .skill(.clipboard): ClipboardView()
        case .skill(.windowLayout): WindowLayoutView()
        case .skill(.resume): ResumeContentView()
        case .skill(.wallpaper): WallpaperView()
        case .skill(.meetingNotes): MeetingView()
        }
    }

    private var loadedSectionView: some View {
        detailView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct JarvisToastHost: View {
    static let capsuleIdentity = "jarvis.toast"

    static func shouldAnimatePresence(from previous: String?, to next: String?) -> Bool {
        (previous == nil) != (next == nil)
    }

    let message: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let message {
                // Stable identity so a new action replaces the text in place
                // instead of playing the previous toast back out.
                JarvisToast(message: message)
                    .id(Self.capsuleIdentity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(
            JarvisMotion.animation(JarvisMotion.feedback, reduceMotion: reduceMotion),
            value: message != nil
        )
    }
}

extension View {
    func jarvisToastOverlay(_ message: String?) -> some View {
        overlay(alignment: .bottom) {
            JarvisToastHost(message: message)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
        }
    }
}

private enum TopLevelSection: Hashable, Identifiable {
    case home
    case skill(SkillID)
    case aiConversation
    case entertainment

    var id: String {
        switch self {
        case .home: "home"
        case let .skill(skill): "skill.\(skill.id)"
        case .aiConversation: "ai-conversation"
        case .entertainment: "entertainment"
        }
    }

    var title: String {
        switch self {
        case .home: "首页"
        case let .skill(skill): skill.navigationTitle
        case .aiConversation: "AI聚合"
        case .entertainment: "娱乐广场"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case let .skill(skill): skill.icon
        case .aiConversation: "sparkles"
        case .entertainment: "play.rectangle"
        }
    }

    var appSection: AppSection {
        switch self {
        case .home: .home
        case let .skill(skill): .skill(skill)
        case .aiConversation: .aiConversation
        case .entertainment: .entertainment
        }
    }
}
