import AppKit
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    static let identityNameKey = "jarvis.identity.display-name"

    var selectedHermesBot: HermesBot? {
        hermesBots.first(where: { $0.id == selectedHermesBotID }) ?? hermesBots.first
    }

    var currentHermesMessages: [HermesChatMessage] {
        hermesChatTranscripts[selectedHermesBotID] ?? []
    }

    func refreshHermesStatus() {
        let adapter = HermesAdapter.live()
        applyHermesStatus(adapter.inspect())
        applyHermesCurrentModel(adapter.currentModel())
        hermesBots = adapter.listBots()
        if hermesBots.contains(where: { $0.id == selectedHermesBotID }) == false {
            selectedHermesBotID = hermesBots.first(where: \.isJarvisProfile)?.id
                ?? hermesBots.first?.id
                ?? HermesAdapter.profileName
        }
    }

    func createJarvisHermesProfile() {
        guard !hermesIsBusy else { return }
        hermesIsBusy = true
        Task.detached { [weak self] in
            do {
                let adapter = HermesAdapter.live()
                try adapter.createJarvisProfile()
                try adapter.injectAPIIfAbsent(AIAPIConfiguration.load())
                let status = adapter.inspect()
                await self?.finishHermesMutation(
                    status: status,
                    successMessage: "Jarvis Profile 已就绪"
                )
            } catch {
                await self?.failHermesMutation(
                    "创建 Jarvis Profile 失败：\(error.localizedDescription)"
                )
            }
        }
    }

    private func finishHermesMutation(status: HermesStatus, successMessage: String) {
        hermesIsBusy = false
        applyHermesStatus(status)
        applyHermesCurrentModel(HermesAdapter.live().currentModel())
        hermesBots = HermesAdapter.live().listBots()
        showToast(successMessage)
    }

    private func failHermesMutation(_ message: String) {
        hermesIsBusy = false
        refreshHermesStatus()
        showToast(message)
    }

    func selectHermesBot(_ botID: String) {
        selectedHermesBotID = botID
    }

    func sendHermesChatMessage() {
        let draft = hermesChatDraft
        let attachments = hermesChatAttachments
        let payload = HermesChatPayload.compose(draft: draft, attachments: attachments)
        guard !payload.query.isEmpty, !hermesChatIsSending else { return }
        hermesChatDraft = ""
        hermesChatAttachments = []
        appendHermesMessage(
            HermesChatMessage(
                role: .user,
                text: payload.displayText,
                attachmentNames: payload.attachmentNames
            )
        )
        hermesChatIsSending = true
        hermesChatProgress = "JARVIS 正在处理…"
        hermesChatProgressSteps = []
        let botID = selectedHermesBotID
        Task.detached { [weak self] in
            let chat = self
            do {
                let reply = try HermesAdapter.live().sendChat(
                    profileID: botID,
                    text: payload.query,
                    imagePaths: payload.imagePaths,
                    onProgress: { status in
                        Task { @MainActor in
                            chat?.updateHermesChatProgress(status)
                        }
                    }
                )
                await chat?.finishHermesChat(reply, botID: botID)
            } catch {
                await chat?.failHermesChat(error.localizedDescription, botID: botID)
            }
        }
    }

    func updateHermesChatProgress(_ status: String) {
        let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != hermesChatProgress else { return }
        if hermesChatProgress != "JARVIS 正在处理…" {
            hermesChatProgressSteps.append(hermesChatProgress)
            if hermesChatProgressSteps.count > 6 {
                hermesChatProgressSteps.removeFirst(hermesChatProgressSteps.count - 6)
            }
        }
        hermesChatProgress = trimmed
    }

    func addHermesAttachment(url: URL, kind: HermesChatAttachment.Kind? = nil) {
        let resolvedKind = kind ?? HermesChatAttachment.kind(forFileURL: url)
        let path = url.standardizedFileURL.path
        if hermesChatAttachments.contains(where: { $0.fileURL?.path == path }) {
            return
        }
        if hermesChatAttachments.count >= 8 {
            showToast("一次最多附加 8 项")
            return
        }
        hermesChatAttachments.append(
            HermesChatAttachment(
                kind: resolvedKind,
                fileURL: url.standardizedFileURL,
                displayName: url.lastPathComponent
            )
        )
    }

    func addHermesURLAttachment(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            showToast("请输入 http 或 https 链接")
            return
        }
        if hermesChatAttachments.contains(where: { $0.remoteURL == trimmed }) {
            return
        }
        if hermesChatAttachments.count >= 8 {
            showToast("一次最多附加 8 项")
            return
        }
        hermesChatAttachments.append(
            HermesChatAttachment(
                kind: .url,
                remoteURL: trimmed,
                displayName: url.host ?? trimmed
            )
        )
    }

    func removeHermesAttachment(_ id: UUID) {
        hermesChatAttachments.removeAll { $0.id == id }
    }

    @discardableResult
    func ingestHermesPasteboardObjects() -> Bool {
        guard !hermesChatIsSending else { return false }
        let pasteboard = NSPasteboard.general
        let classification = HermesPasteClassifier.classify(
            fileURLs: ClipboardService.fileURLs(from: pasteboard),
            hasImage: pasteboardHasImage(pasteboard),
            text: pasteboard.string(forType: .string)
        )
        guard classification.hasObjects else { return false }
        for object in classification.objects {
            switch object {
            case let .file(url):
                addHermesAttachment(url: url)
            case .image:
                pasteHermesImageFromClipboard()
            case let .url(value):
                addHermesURLAttachment(value)
            }
        }
        if let insertText = classification.insertText, !insertText.isEmpty {
            if hermesChatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hermesChatDraft = insertText
            } else {
                hermesChatDraft += "\n\(insertText)"
            }
        }
        return true
    }

    func pasteHermesImageFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let image = NSImage(pasteboard: pasteboard) else {
            showToast("剪贴板里没有图片")
            return
        }
        do {
            let url = try persistPastedHermesImage(image)
            addHermesAttachment(url: url, kind: .image)
        } catch {
            showToast("保存粘贴图片失败：\(error.localizedDescription)")
        }
    }

    private func pasteboardHasImage(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []
        return types.contains(.png)
            || types.contains(.tiff)
            || types.contains(NSPasteboard.PasteboardType("public.jpeg"))
            || types.contains(NSPasteboard.PasteboardType("public.heic"))
    }

    private func persistPastedHermesImage(_ image: NSImage) throws -> URL {
        let tiff = image.tiffRepresentation
        guard let tiff,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw HermesError.writeFailed("无法编码图片")
        }
        let supportDirectory = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        let folder = supportDirectory
            .appendingPathComponent(JarvisAppIdentity.dataDirectoryName, isDirectory: true)
            .appendingPathComponent("hermes-attachments", isDirectory: true)
        JarvisProtectedStorage.prepareDirectory(folder)
        let filename = "paste-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).png"
        let destination = folder.appendingPathComponent(filename)
        try png.write(to: destination)
        return destination
    }

    func loadJarvisIdentity() {
        jarvisIdentityName = UserDefaults.standard.string(forKey: Self.identityNameKey) ?? ""
        let localAvatar = Self.identityAvatarURL
        if FileManager.default.fileExists(atPath: localAvatar.path) {
            jarvisAvatarPath = localAvatar.path
        }
    }

    func saveJarvisIdentityName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = UserDefaults.standard.string(forKey: Self.identityNameKey) ?? ""
        jarvisIdentityName = trimmed
        guard trimmed != stored else { return }
        UserDefaults.standard.set(trimmed, forKey: Self.identityNameKey)
        do {
            try HermesAdapter.live().writeDisplayName(trimmed)
            showToast("姓名已保存")
        } catch HermesError.profileMissing {
            showToast("姓名已保存，创建 Jarvis Profile 后会同步到 Hermes")
        } catch {
            showToast("姓名已保存，同步到 Hermes 失败：\(error.localizedDescription)")
        }
    }

    func chooseJarvisAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "选择头像"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try saveJarvisAvatar(from: url)
            showToast("头像已更新")
        } catch {
            showToast("保存头像失败：\(error.localizedDescription)")
        }
    }

    private func saveJarvisAvatar(from sourceURL: URL) throws {
        let destination = Self.identityAvatarURL
        JarvisProtectedStorage.prepareDirectory(destination.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        jarvisAvatarPath = destination.path
        try? HermesAdapter.live().writeAvatar(from: destination)
    }

    private func appendHermesMessage(_ message: HermesChatMessage, botID: String? = nil) {
        let target = botID ?? selectedHermesBotID
        var messages = hermesChatTranscripts[target] ?? []
        messages.append(message)
        hermesChatTranscripts[target] = messages
    }

    private func finishHermesChat(_ reply: String, botID: String) {
        hermesChatIsSending = false
        hermesChatProgress = "JARVIS 正在处理…"
        hermesChatProgressSteps = []
        appendHermesMessage(HermesChatMessage(role: .assistant, text: reply), botID: botID)
    }

    private func failHermesChat(_ message: String, botID: String) {
        hermesChatIsSending = false
        hermesChatProgress = "JARVIS 正在处理…"
        hermesChatProgressSteps = []
        appendHermesMessage(HermesChatMessage(role: .assistant, text: message), botID: botID)
        showToast(message)
    }

    private func applyHermesStatus(_ status: HermesStatus) {
        hermesIsInstalled = status.isInstalled
        hermesProfileReady = status.isProfileReady
        hermesStatusMessage = status.message
        hermesCLIPath = status.cliPath ?? ""
        hermesSyncedModel = status.model ?? ""
    }

    private static var identityAvatarURL: URL {
        let supportDirectory = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return supportDirectory
            .appendingPathComponent(JarvisAppIdentity.dataDirectoryName, isDirectory: true)
            .appendingPathComponent("identity", isDirectory: true)
            .appendingPathComponent("avatar.png")
    }
}
