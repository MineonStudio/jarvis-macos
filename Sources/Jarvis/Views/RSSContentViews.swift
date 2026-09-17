import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum RSSLayoutMetrics {
    static let feedColumnWidth: CGFloat = 208
    static let itemColumnWidth: CGFloat = 320
    static let rowCornerRadius: CGFloat = 8
}

struct RSSView: View {
    @Environment(AppModel.self) private var app
    @State private var showsManageSheet = false

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                ToolbarItem(id: "rss.add", placement: .navigation) {
                    Button {
                        showsManageSheet = true
                    } label: {
                        Label("订阅管理", systemImage: "plus")
                    }
                    .help("添加订阅源或导入 OPML")
                }
            },
            trailingToolbar: {
                ToolbarItem(id: "rss.refresh", placement: .automatic) {
                    refreshButton
                }
                ToolbarSpacer(.fixed, placement: .automatic)
                ToolbarItem(id: "rss.filter", placement: .automatic) {
                    filterPicker
                }
                ToolbarSpacer(.fixed, placement: .automatic)
                ToolbarItem(id: "rss.search", placement: .automatic) {
                    ClipboardSearchField(
                        text: Binding(
                            get: { app.rssSearchText },
                            set: { app.rssSearchText = $0 }
                        ),
                        placeholder: "搜索文章",
                        focusesOnAppear: false
                    )
                }
            },
            content: {
                VStack(spacing: 0) {
                    if let storageError = app.rssStorageError {
                        RSSStorageErrorBanner(message: storageError)
                    }

                    Group {
                        if app.rssFeeds.isEmpty {
                            RSSEmptyState { showsManageSheet = true }
                        } else {
                            HStack(spacing: 0) {
                                RSSFeedSidebar()
                                    .frame(width: RSSLayoutMetrics.feedColumnWidth)
                                Divider()
                                RSSItemList()
                                    .frame(width: RSSLayoutMetrics.itemColumnWidth)
                                Divider()
                                RSSArticlePane()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .jarvisModulePanel()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        )
        .sheet(isPresented: $showsManageSheet) {
            RSSManageSheet()
                .environment(app)
        }
    }

    private var refreshButton: some View {
        Button {
            app.rssRefreshTask?.cancel()
            app.rssRefreshTask = Task { await app.refreshAllRSSFeeds(manual: true) }
        } label: {
            if app.rssIsRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Label("刷新", systemImage: "arrow.clockwise")
            }
        }
        .help("立即刷新全部订阅")
        .disabled(app.rssIsRefreshing)
    }

    private var filterPicker: some View {
        Picker(
            "筛选",
            selection: Binding(
                get: { app.rssFilter },
                set: { app.rssFilter = $0 }
            )
        ) {
            ForEach(RSSItemFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 168)
    }
}

// MARK: - 空态与错误

private struct RSSStorageErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(JarvisTypography.caption)
                .foregroundStyle(Color.jarvisTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.top, 12)
        .padding(.bottom, 12)
    }
}

private struct RSSEmptyState: View {
    let onSubscribe: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            JarvisEmptyState(
                icon: "dot.radiowaves.up.forward",
                title: "还没有订阅",
                message: "添加一个订阅源，或者导入其它阅读器导出的 OPML 文件。新文章会在后台刷新并通过通知提醒你。"
            )
            Button("添加订阅") {
                onSubscribe()
            }
            .buttonStyle(JarvisPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 订阅列表

private struct RSSFeedSidebar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                allFeedsRow
                ForEach(orderedEntries, id: \.id) { entry in
                    switch entry {
                    case let .group(group, feeds):
                        RSSFeedGroupRow(group: group, feeds: feeds)
                    case let .feed(feed):
                        RSSFeedRow(feed: feed)
                    }
                }
            }
            .padding(8)
        }
    }

    private enum Entry: Identifiable {
        case group(RSSGroup, [RSSFeed])
        case feed(RSSFeed)

        var id: String {
            switch self {
            case let .group(group, _): "group-\(group.id.uuidString)"
            case let .feed(feed): "feed-\(feed.id.uuidString)"
            }
        }
    }

    private var orderedEntries: [Entry] {
        var entries: [Entry] = []
        for group in app.rssGroups.sorted(by: { $0.order < $1.order }) {
            let members = app.rssFeeds.filter { $0.groupID == group.id }
            guard !members.isEmpty else { continue }
            entries.append(.group(group, members))
        }
        let ungrouped = app.rssFeeds.filter { feed in
            feed.groupID == nil || !app.rssGroups.contains { $0.id == feed.groupID }
        }
        entries.append(contentsOf: ungrouped.map { .feed($0) })
        return entries
    }

    private var allFeedsRow: some View {
        Button {
            app.rssSelectedFeedID = nil
            app.rssSelectedItemID = app.rssFilteredRSSItems().first?.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "tray.full")
                    .font(.system(size: JarvisToolbarMetrics.iconSize))
                    .frame(width: 18)
                Text("全部订阅")
                    .font(JarvisTypography.control)
                Spacer(minLength: 0)
                if app.rssUnreadTotal > 0 {
                    RSSUnreadBadge(count: app.rssUnreadTotal)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                app.rssSelectedFeedID == nil ? Color.accentColor.opacity(0.14) : .clear,
                in: RoundedRectangle(cornerRadius: RSSLayoutMetrics.rowCornerRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct RSSFeedGroupRow: View {
    let group: RSSGroup
    let feeds: [RSSFeed]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.title)
                .font(JarvisTypography.sectionLabel)
                .foregroundStyle(Color.jarvisTextSecondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)
            ForEach(feeds) { feed in
                RSSFeedRow(feed: feed)
                    .padding(.leading, 10)
            }
        }
    }
}

private struct RSSFeedRow: View {
    @Environment(AppModel.self) private var app
    let feed: RSSFeed

    var body: some View {
        Button {
            app.rssSelectedFeedID = feed.id
            app.rssSelectedItemID = app.rssFilteredRSSItems().first?.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: feed.lastErrorMessage == nil ? "dot.radiowaves.up.forward" : "exclamationmark.triangle")
                    .font(.system(size: JarvisToolbarMetrics.iconSize))
                    .foregroundStyle(feed.lastErrorMessage == nil ? Color.accentColor : .orange)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(feed.title)
                        .font(JarvisTypography.control)
                        .lineLimit(1)
                        .foregroundStyle(feed.isEnabled ? Color.primary : Color.jarvisTextSecondary)
                    if let error = feed.lastErrorMessage {
                        Text(error)
                            .font(JarvisTypography.micro)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if feed.unreadCount > 0 {
                    RSSUnreadBadge(count: feed.unreadCount)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                app.rssSelectedFeedID == feed.id ? Color.accentColor.opacity(0.14) : .clear,
                in: RoundedRectangle(cornerRadius: RSSLayoutMetrics.rowCornerRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("刷新这个订阅") {
                Task { await app.refreshRSSFeed(feed) }
            }
            Button("全部标为已读") {
                app.markAllRSSTemsRead(feedID: feed.id)
            }
            Button(feed.isEnabled ? "暂停更新" : "恢复更新") {
                app.setRSSFeedEnabled(feed, isEnabled: !feed.isEnabled)
            }
            Divider()
            Button("删除订阅", role: .destructive) {
                app.removeRSSFeed(feed)
            }
        }
    }
}

private struct RSSUnreadBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : String(count))
            .font(JarvisTypography.badge)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor, in: Capsule())
    }
}

// MARK: - 条目列表

private struct RSSItemList: View {
    @Environment(AppModel.self) private var app
    @FocusState private var isFocused: Bool

    private var items: [RSSItem] {
        app.rssFilteredRSSItems()
    }

    var body: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.jarvisTextSecondary)
                    Text(emptyMessage)
                        .font(JarvisTypography.secondary)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(items) { item in
                                RSSItemRow(item: item)
                                    .id(item.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: app.rssSelectedItemID) { _, newValue in
                        guard let newValue else { return }
                        withAnimation(JarvisMotion.animation(JarvisMotion.content, reduceMotion: false)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }
        }
        .focusable()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.space) {
            toggleSelectedRead()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "sS")) { _ in
            guard let itemID = app.rssSelectedItemID else { return .ignored }
            app.toggleRSSStar(itemID: itemID)
            return .handled
        }
    }

    private var emptyMessage: String {
        switch app.rssFilter {
        case .all: "这里还没有文章"
        case .unread: "没有未读文章"
        case .starred: "还没有星标文章"
        }
    }

    private func moveSelection(by offset: Int) {
        let list = items
        guard !list.isEmpty else { return }
        guard let currentID = app.rssSelectedItemID,
              let index = list.firstIndex(where: { $0.id == currentID })
        else {
            app.rssSelectedItemID = list.first?.id
            return
        }
        let next = min(max(index + offset, 0), list.count - 1)
        app.rssSelectedItemID = list[next].id
        app.markRSSItemRead(itemID: list[next].id, isRead: true)
    }

    private func toggleSelectedRead() {
        guard let itemID = app.rssSelectedItemID,
              let item = items.first(where: { $0.id == itemID })
        else {
            return
        }
        app.markRSSItemRead(itemID: itemID, isRead: !item.isRead)
    }
}

private struct RSSItemRow: View {
    @Environment(AppModel.self) private var app
    let item: RSSItem

    private var isSelected: Bool {
        app.rssSelectedItemID == item.id
    }

    var body: some View {
        Button {
            app.selectRSSItem(item)
            app.markRSSItemRead(itemID: item.id, isRead: true)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(item.isRead ? Color.clear : Color.accentColor)
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(item.isRead ? JarvisTypography.control : JarvisTypography.controlEmphasis)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(RSSArticleRenderer.previewText(fromHTML: item.summaryHTML, limit: 90))
                        .font(JarvisTypography.micro)
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(app.rssFeedTitles[item.feedID] ?? "")
                        Text("·")
                        Text(RSSDateFormat.relative(item.sortDate))
                        if item.isStarred {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                        }
                    }
                    .font(JarvisTypography.micro)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : .clear,
                in: RoundedRectangle(cornerRadius: RSSLayoutMetrics.rowCornerRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(item.isStarred ? "取消星标" : "加星标") {
                app.toggleRSSStar(itemID: item.id)
            }
            Button(item.isRead ? "标为未读" : "标为已读") {
                app.markRSSItemRead(itemID: item.id, isRead: !item.isRead)
            }
            if let link = item.link {
                Divider()
                Button("在浏览器打开") {
                    NSWorkspace.shared.open(link)
                }
            }
        }
    }
}

// MARK: - 正文

private struct RSSArticlePane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let item = app.rssSelectedItem() {
            article(for: item)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.jarvisTextSecondary)
                Text("选择一篇文章开始阅读")
                    .font(JarvisTypography.secondary)
                    .foregroundStyle(Color.jarvisTextSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func article(for item: RSSItem) -> some View {
        let html = app.rssArticleHTML(for: item)
        let heroImage = RSSArticleRenderer.imageURLs(inHTML: html, baseURL: item.link).first

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(item.title)
                    .font(.system(size: 22, weight: .semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(app.rssFeedTitles[item.feedID] ?? "")
                    if let author = item.author, !author.isEmpty {
                        Text("·")
                        Text(author)
                    }
                    Text("·")
                    Text(RSSDateFormat.absolute(item.sortDate))
                }
                .font(JarvisTypography.caption)
                .foregroundStyle(Color.jarvisTextSecondary)

                HStack(spacing: 8) {
                    Button {
                        app.toggleRSSStar(itemID: item.id)
                    } label: {
                        Label(item.isStarred ? "已星标" : "星标", systemImage: item.isStarred ? "star.fill" : "star")
                    }
                    .buttonStyle(JarvisToolbarButtonStyle())
                    if let link = item.link {
                        Button {
                            NSWorkspace.shared.open(link)
                        } label: {
                            Label("在浏览器打开", systemImage: "safari")
                        }
                        .buttonStyle(JarvisToolbarButtonStyle())
                    }
                    Spacer(minLength: 0)
                }

                if let heroImage {
                    AsyncImage(url: heroImage) { phase in
                        if case let .success(image) = phase {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: JarvisMetrics.cardRadius, style: .continuous))
                        }
                    }
                }

                Text(RSSArticleRenderer.attributedString(fromHTML: html, baseURL: item.link))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(JarvisMetrics.pageInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 订阅管理

private struct RSSManageSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("订阅管理")
                .font(JarvisTypography.cardTitle)

            VStack(alignment: .leading, spacing: 8) {
                Text("添加订阅")
                    .font(JarvisTypography.sectionLabel)
                    .foregroundStyle(Color.jarvisTextSecondary)
                HStack(spacing: 8) {
                    TextField("订阅源地址或网站地址", text: $input)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                        .onSubmit { subscribe() }
                    Button("添加") { subscribe() }
                        .buttonStyle(JarvisPrimaryButtonStyle())
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                }
                if isWorking {
                    JarvisInlineLoadingState()
                }
                if let message {
                    Text(message)
                        .font(JarvisTypography.caption)
                        .foregroundStyle(messageIsError ? .orange : Color.jarvisTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("导入导出")
                    .font(JarvisTypography.sectionLabel)
                    .foregroundStyle(Color.jarvisTextSecondary)
                HStack(spacing: 8) {
                    Button("导入 OPML") { importOPML() }
                        .buttonStyle(JarvisSecondaryButtonStyle())
                    Button("导出 OPML") { exportOPML() }
                        .buttonStyle(JarvisSecondaryButtonStyle())
                        .disabled(app.rssFeeds.isEmpty)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("刷新与提醒")
                    .font(JarvisTypography.sectionLabel)
                    .foregroundStyle(Color.jarvisTextSecondary)
                HStack(spacing: 10) {
                    Text("后台刷新")
                        .font(JarvisTypography.secondary)
                    Picker(
                        "后台刷新",
                        selection: Binding(
                            get: { app.rssRefreshInterval },
                            set: { app.updateRSSRefreshInterval($0) }
                        )
                    ) {
                        ForEach(RSSRefreshScheduler.Interval.allCases) { interval in
                            Text(interval.title).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                Toggle(
                    "新文章通知",
                    isOn: Binding(
                        get: { app.rssNotificationsEnabled },
                        set: { app.updateRSSNotificationsEnabled($0) }
                    )
                )
                .font(JarvisTypography.secondary)
                .toggleStyle(.switch)
            }

            if !app.rssFeeds.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("已订阅（\(app.rssFeeds.count)）")
                        .font(JarvisTypography.sectionLabel)
                        .foregroundStyle(Color.jarvisTextSecondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(app.rssFeeds) { feed in
                                HStack(spacing: 8) {
                                    Text(feed.title)
                                        .font(JarvisTypography.secondary)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Text("\(feed.unreadCount) 未读")
                                        .font(JarvisTypography.micro)
                                        .foregroundStyle(Color.jarvisTextSecondary)
                                    Button("删除", role: .destructive) {
                                        app.removeRSSFeed(feed)
                                    }
                                    .buttonStyle(.link)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
            }

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(JarvisPrimaryButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func subscribe() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isWorking = true
        message = nil
        Task {
            let result = await app.subscribeRSSFeed(fromInput: value)
            isWorking = false
            switch result {
            case let .success(feed):
                messageIsError = false
                message = "已订阅「\(feed.title)」"
                input = ""
            case let .failure(error):
                messageIsError = true
                message = error.errorDescription ?? "订阅失败"
            }
        }
    }

    private func importOPML() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let type = UTType(filenameExtension: "opml") {
            panel.allowedContentTypes = [type, .xml]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isWorking = true
        message = nil
        Task {
            await app.importRSSOPML(from: url)
            isWorking = false
            messageIsError = false
            message = "导入完成，共 \(app.rssFeeds.count) 个订阅源"
        }
    }

    private func exportOPML() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Jarvis订阅.opml"
        if let type = UTType(filenameExtension: "opml") {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        app.exportRSSOPML(to: url)
        messageIsError = false
        message = "已导出到 \(url.lastPathComponent)"
    }
}

// MARK: - 日期显示

enum RSSDateFormat {
    private nonisolated(unsafe) static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter
    }()

    private nonisolated(unsafe) static let absolute: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func relative(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 {
            return "刚刚"
        }
        return relative.localizedString(for: date, relativeTo: Date())
    }

    static func absolute(_ date: Date) -> String {
        absolute.string(from: date)
    }
}
