import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HermesConversationView: View {
    @EnvironmentObject private var app: AppModel
    @FocusState private var inputFocused: Bool
    @State private var showingURLPrompt = false
    @State private var urlDraft = ""
    @State private var isSpeaking = false
    @State private var speakingTask: Task<Void, Never>?
    @State private var orbPulse = 0
    @State private var historyState = HermesComposerHistoryState()
    @State private var keyMonitor: Any?

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                ToolbarItem(placement: .navigation) {
                    modelSwitcher
                }
            },
            trailingToolbar: {
                ToolbarItem(placement: .automatic) {
                    EmptyView()
                }
            },
            content: {
                VStack(spacing: 16) {
                    JarvisOrbView(diameter: 168, mood: orbMood, pulse: orbPulse)
                    chatPanel
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        )
        .onAppear {
            app.refreshHermesStatus()
            app.refreshAvailableAIModels()
            installKeyMonitor()
        }
        .onChange(of: app.currentHermesMessages.last?.id) { _, _ in
            startSpeakingIfNeeded()
        }
        .onChange(of: app.hermesChatProgress) { _, progress in
            if progress.hasPrefix("已完成") || progress.hasPrefix("已取消") {
                orbPulse += 1
            }
        }
        .onChange(of: app.hermesChatIsSending) { _, isSending in
            if isSending {
                historyState.reset()
            }
        }
        .onDisappear {
            speakingTask?.cancel()
            removeKeyMonitor()
        }
        .alert("附加 URL", isPresented: $showingURLPrompt) {
            TextField("https://", text: $urlDraft)
            Button("添加") {
                app.addHermesURLAttachment(urlDraft)
                urlDraft = ""
            }
            Button("取消", role: .cancel) {
                urlDraft = ""
            }
        } message: {
            Text("输入要交给 JARVIS 的网页链接")
        }
    }

    private var orbMood: JarvisOrbMood {
        let lastAssistant = app.currentHermesMessages.last(where: { $0.role == .assistant })?.text ?? ""
        let isListening = inputFocused
            || !app.hermesChatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !app.hermesChatAttachments.isEmpty
        return JarvisOrbMood.from(
            isSending: app.hermesChatIsSending,
            progress: app.hermesChatProgress,
            isListening: isListening,
            isSpeaking: isSpeaking,
            lastAssistantText: lastAssistant
        )
    }

    private func startSpeakingIfNeeded() {
        guard !app.hermesChatIsSending,
              app.currentHermesMessages.last?.role == .assistant
        else { return }
        speakingTask?.cancel()
        isSpeaking = true
        speakingTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            isSpeaking = false
        }
    }

    private var modelSwitcher: some View {
        Menu {
            ForEach(groupedModelOptions, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.options) { option in
                        Button {
                            app.selectAIModel(option)
                        } label: {
                            if isSelected(option) {
                                Label(option.menuTitle, systemImage: "checkmark")
                            } else {
                                Text(option.menuTitle)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 11, weight: .semibold))
                Text(currentModelTitle)
                    .font(JarvisTypography.control)
                    .lineLimit(1)
                if app.aiModelsLoading {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 10)
            .frame(height: JarvisToolbarMetrics.controlSize)
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .disabled(modelOptions.isEmpty && !app.aiModelsLoading)
        .help("切换模型")
    }

    private var chatPanel: some View {
        VStack(spacing: 0) {
            if !app.hermesProfileReady {
                emptyState
            } else {
                messageList
                composer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .jarvisGlass(cornerRadius: 22, interactive: false)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            JarvisEmptyState(
                icon: "bubble.left.and.bubble.right",
                title: "还不能和 JARVIS 对话",
                message: app.hermesIsInstalled
                    ? "先创建 Jarvis Profile，再开始对话。"
                    : "未检测到 Hermes。请先在本机安装 Hermes Agent。"
            )
            if app.hermesIsInstalled, !app.hermesProfileReady {
                Button("创建 Jarvis Profile") {
                    app.createJarvisHermesProfile()
                }
                .buttonStyle(JarvisPrimaryButtonStyle())
                .disabled(app.hermesIsBusy)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(app.currentHermesMessages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                    if app.hermesChatIsSending {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(app.hermesChatProgressSteps.enumerated()), id: \.offset) { _, step in
                                Text(step)
                                    .font(JarvisTypography.caption)
                                    .foregroundStyle(Color.secondary.opacity(0.7))
                            }
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(app.hermesChatProgress)
                                    .font(JarvisTypography.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        .padding(.horizontal, 4)
                        .id("sending")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: app.currentHermesMessages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: app.hermesChatIsSending) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: app.hermesChatProgress) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func messageBubble(_ message: HermesChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack {
            if isUser {
                Spacer(minLength: 72)
            }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if !message.attachmentNames.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.attachmentNames, id: \.self) { name in
                            Text(name)
                                .font(JarvisTypography.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(isUser ? Color.white.opacity(0.18) : Color.primary.opacity(0.08))
                                )
                        }
                    }
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(JarvisTypography.body)
                        .foregroundStyle(isUser ? Color.white : Color.primary)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isUser ? Color.accentColor : Color.primary.opacity(0.07))
            )
            if !isUser {
                Spacer(minLength: 72)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !app.hermesChatAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(app.hermesChatAttachments) { item in
                            attachmentChip(item)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }

            HStack(alignment: .center, spacing: 6) {
                attachmentMenu
                TextField("和 JARVIS 对话", text: $app.hermesChatDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(JarvisTypography.body)
                    .lineLimit(1 ... 5)
                    .frame(minHeight: 28, alignment: .center)
                    .focused($inputFocused)
                    .onSubmit(app.sendHermesChatMessage)

                Button {
                    app.sendHermesChatMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(app.hermesChatIsSending || !canSend)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: composerShape)
        .overlay {
            composerShape
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .padding(.top, 6)
    }

    private var canSend: Bool {
        !app.hermesChatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !app.hermesChatAttachments.isEmpty
    }

    private var composerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: app.hermesChatAttachments.isEmpty ? 22 : 18, style: .continuous)
    }

    private var attachmentMenu: some View {
        Menu {
            Section("附加") {
                Button("文件…") { pickAttachments() }
                Button("文件夹…") { pickAttachments(folders: true) }
                Button("图片…") { pickAttachments(images: true) }
                Button("URL…") {
                    urlDraft = ""
                    showingURLPrompt = true
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 28, height: 28, alignment: .center)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(width: 28, height: 28, alignment: .center)
        .disabled(app.hermesChatIsSending)
        .help("附加文件")
    }

    private func attachmentChip(_ item: HermesChatAttachment) -> some View {
        HStack(spacing: 4) {
            Image(systemName: item.systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(item.displayName)
                .font(JarvisTypography.caption)
                .lineLimit(1)
            Button {
                app.removeHermesAttachment(item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            handleComposerKey(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func handleComposerKey(_ event: NSEvent) -> NSEvent? {
        guard !showingURLPrompt, !app.hermesChatIsSending else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command),
           !flags.contains(.option),
           !flags.contains(.shift),
           event.charactersIgnoringModifiers?.lowercased() == "v"
        {
            if app.ingestHermesPasteboardObjects() {
                inputFocused = true
                return nil
            }
            return event
        }

        let blocking: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard flags.isDisjoint(with: blocking) else { return event }
        if event.keyCode == 126 {
            return handleHistoryUp(event)
        }
        if event.keyCode == 125 {
            return handleHistoryDown(event)
        }
        return event
    }

    private func handleHistoryUp(_ event: NSEvent) -> NSEvent? {
        let draft = app.hermesChatDraft
        if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !historyState.isBrowsing {
            return event
        }
        let history = HermesComposerHistory.userEntries(from: app.currentHermesMessages)
        guard let text = historyState.browseBackward(currentDraft: draft, history: history) else {
            return event
        }
        app.hermesChatDraft = text
        inputFocused = true
        return nil
    }

    private func handleHistoryDown(_ event: NSEvent) -> NSEvent? {
        guard historyState.isBrowsing else { return event }
        let history = HermesComposerHistory.userEntries(from: app.currentHermesMessages)
        guard let text = historyState.browseForward(history: history) else {
            return event
        }
        app.hermesChatDraft = text
        inputFocused = true
        return nil
    }

    private func pickAttachments(folders: Bool = false, images: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !folders
        panel.canChooseDirectories = folders
        panel.allowsMultipleSelection = !folders
        panel.canCreateDirectories = false
        if images {
            panel.allowedContentTypes = [.png, .jpeg, .heic, .webP, .gif, .tiff, .bmp]
            panel.title = "选择图片"
        } else if folders {
            panel.title = "选择文件夹"
        } else {
            panel.title = "选择文件"
        }
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            app.addHermesAttachment(url: url)
        }
    }

    private var modelOptions: [AIModelOption] {
        if app.availableAIModelOptions.isEmpty, !app.hermesCurrentModel.isEmpty {
            let isFree = HermesFreeModelCatalog.isAnonymousFreeModel(app.hermesCurrentModel)
            return [
                AIModelOption(
                    model: app.hermesCurrentModel,
                    isFree: isFree,
                    providerTitle: HermesProviderCatalog.groupTitle(
                        forSlug: app.hermesCurrentProvider,
                        isFree: isFree
                    ),
                    endpoint: HermesProviderCatalog.descriptor(for: app.hermesCurrentProvider)?
                        .chatCompletionsURL ?? "",
                    hermesProvider: app.hermesCurrentProvider
                )
            ]
        }
        return app.availableAIModelOptions
    }

    private var groupedModelOptions: [(title: String, options: [AIModelOption])] {
        var titles: [String] = []
        var grouped: [String: [AIModelOption]] = [:]
        for option in modelOptions {
            if grouped[option.providerTitle] == nil {
                titles.append(option.providerTitle)
            }
            grouped[option.providerTitle, default: []].append(option)
        }
        titles.sort { lhs, rhs in
            if lhs == "OpenCode" {
                return false
            }
            if rhs == "OpenCode" {
                return true
            }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        return titles.map { title in
            (title, grouped[title] ?? [])
        }
    }

    private var currentModelTitle: String {
        if app.hermesCurrentModel.isEmpty {
            return "选择模型"
        }
        return modelOptions.first(where: isSelected)?.menuTitle
            ?? (HermesFreeModelCatalog.isAnonymousFreeModel(app.hermesCurrentModel)
                ? "\(app.hermesCurrentModel)  free"
                : app.hermesCurrentModel)
    }

    private func isSelected(_ option: AIModelOption) -> Bool {
        option.model == app.hermesCurrentModel
            && option.hermesProvider == app.hermesCurrentProvider
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if app.hermesChatIsSending {
            proxy.scrollTo("sending", anchor: .bottom)
        } else if let last = app.currentHermesMessages.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}
