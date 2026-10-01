import AppKit

extension AppModel {
    // MARK: - Clipboard workflow

    func configureClipboardRecording() {
        guard automaticClipboardRecordingEnabled else {
            clipboardService.stop()
            return
        }
        clipboardService.start(
            onChange: { [weak self] item in
                Task { @MainActor [weak self] in
                    self?.receiveClipboardItem(item)
                }
            },
            prepareCacheSpace: { [weak self, cacheStore = clipboardCacheStore, historyStore = screenshotHistoryStore, latestStore = screenshotCacheStore] bytes in
                let clipboard = cacheStore.usage()
                let screenshots = historyStore.storedUsage()
                let allowed = SharedCacheAdmission.allows(
                    usedBytes: clipboard.usedBytes + screenshots.bytes + latestStore.storedBytes(),
                    capacityBytes: clipboard.capacityBytes,
                    incomingBytes: bytes
                )
                if !allowed {
                    Task { @MainActor [weak self] in
                        self?.notifySharedCacheFull()
                    }
                }
                return allowed
            }
        )
    }

    func updateAutomaticClipboardRecordingEnabled(_ enabled: Bool) {
        automaticClipboardRecordingEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: clipboardRecordingEnabledKey)
        configureClipboardRecording()
        JarvisLog.info(
            category: .clipboard,
            event: "recording.preferenceChanged",
            fields: ["enabled": String(enabled)]
        )
        showToast(enabled ? "已开启自动记录剪贴板" : "已暂停自动记录剪贴板")
    }

    func updateHideSensitiveClipboardContent(_ hidden: Bool) {
        hideSensitiveClipboardContent = hidden
        UserDefaults.standard.set(hidden, forKey: hideSensitiveClipboardContentKey)
        showToast(hidden ? "敏感内容将默认隐藏" : "敏感内容将直接显示")
    }

    func migrateClipboardTextCache() {
        var didChange = false
        var migratedCount = 0
        for index in clipboardItems.indices {
            let item = clipboardItems[index]
            guard item.kind == .text,
                  item.textPath == nil,
                  let text = item.text,
                  !text.isEmpty
            else {
                continue
            }

            let data = Data(text.utf8)
            guard admitSharedCacheBytes(Int64(data.count), notify: false) else { continue }
            guard let path = clipboardCacheStore.storeData(data, fileExtension: "txt") else {
                continue
            }
            clipboardItems[index].textPath = path
            clipboardItems[index].isStoredCopy = true
            didChange = true
            migratedCount += 1
        }

        if migratedCount > 0 {
            JarvisLog.info(
                category: .clipboard,
                event: "cache.textMigration.complete",
                fields: ["itemCount": String(migratedCount)]
            )
        }
        if didChange, !persistClipboardHistory() {
            JarvisLog.error(
                category: .clipboard,
                event: "history.textMigrationSave.failed",
                fields: ["recordCount": String(clipboardItems.count)]
            )
        }
    }

    func receiveClipboardItem(_ item: ClipboardItem) {
        let matchingItems = clipboardItems.filter { $0.fingerprint == item.fingerprint }
        let wasPinned = matchingItems.contains(where: \.isPinned)
        var item = item
        item.isPinned = wasPinned
        JarvisLog.notice(
            category: .clipboard,
            event: "history.itemReceived",
            fields: [
                "kind": item.kind.rawValue,
                "bytes": String(item.fileSize ?? 0),
                "storedCopy": String(item.isStoredCopy),
                "duplicateCount": String(matchingItems.count),
                "pinned": String(wasPinned)
            ]
        )

        if item.kind != .text,
           !item.hasLocalContent
        {
            JarvisLog.notice(
                category: .clipboard,
                event: "history.itemRejected",
                result: "unusableDuplicate",
                fields: ["kind": item.kind.rawValue]
            )
            return
        }

        clipboardItems.removeAll { $0.fingerprint == item.fingerprint }
        clipboardItems.append(item)
        clipboardItems = ClipboardOrdering.newestFirst(clipboardItems)
        scheduleClipboardHistorySave()

        let preservedPaths = Set(item.cachePaths)
        let stalePaths = matchingItems.flatMap(\.cachePaths).filter { !preservedPaths.contains($0) }
        clipboardCacheStore.removeLegacyFiles(
            atPaths: stalePaths,
            reason: "historyDuplicateReplacement"
        )
        JarvisLog.info(
            category: .clipboard,
            event: "history.itemApplied",
            result: "success",
            fields: [
                "recordCount": String(clipboardItems.count),
                "stalePathCount": String(stalePaths.count)
            ]
        )
        refreshClipboardCacheUsage()
    }

    /// 剪贴板历史的唯一落盘入口：写入调用当下的状态，并作废在途的去抖写入。
    /// 版本号就在读取状态之后取，两者同在 MainActor 上同步完成，顺序一致。
    @discardableResult
    private func persistClipboardHistory() -> Bool {
        clipboardSaveTask?.cancel()
        clipboardSaveTask = nil
        clipboardHistoryRevision += 1
        return clipboardStore.save(clipboardItems, revision: clipboardHistoryRevision)
    }

    private func scheduleClipboardHistorySave() {
        clipboardSaveTask?.cancel()
        clipboardSaveTask = Task { @MainActor [weak self, clipboardHistoryWriter] in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled, let self else { return }
            self.clipboardSaveTask = nil

            // 取当前状态而不是调度时的快照：用户可能已经收藏或删除过条目。
            self.clipboardHistoryRevision += 1
            let revision = self.clipboardHistoryRevision
            guard await clipboardHistoryWriter.save(self.clipboardItems, revision: revision) else {
                self.showToast(JarvisFeedbackCopy.saveFailed)
                return
            }
        }
    }

    func copyClipboard(_ item: ClipboardItem) {
        guard writeClipboardItem(item) else {
            JarvisLog.notice(
                category: .clipboard,
                event: "history.copy.failed",
                result: "contentUnavailable",
                fields: ["kind": item.kind.rawValue]
            )
            showToast(JarvisFeedbackCopy.contentUnavailable)
            return
        }
        JarvisLog.info(
            category: .clipboard,
            event: "history.copy.complete",
            result: "success",
            fields: ["kind": item.kind.rawValue]
        )
        clipboardService.markCurrentPasteboardAsHandled()
        showToast(JarvisFeedbackCopy.copied)
    }

    func showClipboardMediaPreview(_ item: ClipboardItem) {
        guard item.canFullscreenPreview else {
            JarvisLog.notice(
                category: .clipboard,
                event: "preview.open.failed",
                result: "contentUnavailable",
                fields: ["kind": item.kind.rawValue]
            )
            if item.kind == .file {
                copyClipboard(item)
                return
            }
            showToast(item.kind == .text ? JarvisFeedbackCopy.textUnavailable : JarvisFeedbackCopy.mediaUnavailable)
            return
        }
        clipboardMediaPreviewController.show(item: item)
    }

    func showClipboardPanel() {
        clipboardPanelController.show(app: self)
    }

    func toggleClipboardPin(_ item: ClipboardItem) {
        guard let index = clipboardItems.firstIndex(where: { $0.id == item.id }) else { return }
        clipboardItems[index].isPinned.toggle()
        JarvisLog.info(
            category: .clipboard,
            event: "history.pinChanged",
            fields: [
                "kind": item.kind.rawValue,
                "pinned": String(clipboardItems[index].isPinned)
            ]
        )
        guard persistClipboardHistory() else {
            showToast(JarvisFeedbackCopy.saveFailed)
            return
        }
        showToast(clipboardItems.first(where: { $0.id == item.id })?.isPinned == true
            ? JarvisFeedbackCopy.favorited
            : JarvisFeedbackCopy.unfavorited)
    }

    @discardableResult
    func writeClipboardItem(_ item: ClipboardItem) -> Bool {
        let pasteboard = NSPasteboard.general

        switch item.kind {
        case .text:
            guard let text = item.text else { return false }
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        case .image:
            guard let path = item.imagePath,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let image = NSImage(data: data) else { return false }
            pasteboard.clearContents()
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setData(data, forType: .png)
            if let tiffData = image.tiffRepresentation {
                pasteboardItem.setData(tiffData, forType: .tiff)
            }
            return pasteboard.writeObjects([pasteboardItem])
        case .file, .video:
            guard let path = item.filePath,
                  FileManager.default.fileExists(atPath: path) else { return false }
            pasteboard.clearContents()
            return pasteboard.writeObjects([URL(fileURLWithPath: path) as NSURL])
        }
    }

    func deleteClipboardItem(_ item: ClipboardItem) {
        JarvisLog.notice(
            category: .clipboard,
            event: "history.delete.begin",
            fields: ["kind": item.kind.rawValue]
        )
        _ = clipboardCacheStore.removeManagedFiles(for: [item], reason: "userDelete")
        clipboardItems.removeAll { $0.id == item.id }
        if !persistClipboardHistory() {
            showToast(JarvisFeedbackCopy.saveFailed)
            return
        }
        refreshClipboardCacheUsage()
        JarvisLog.info(
            category: .clipboard,
            event: "history.delete.complete",
            result: "success",
            fields: ["recordCount": String(clipboardItems.count)]
        )
        showToast(JarvisFeedbackCopy.deleted)
    }

    func refreshClipboardCacheUsage() {
        let cacheStore = clipboardCacheStore
        let historyStore = screenshotHistoryStore
        let latestScreenshotStore = screenshotCacheStore
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let clipboard = cacheStore.usage()
            let screenshots = historyStore.storedUsage()
            let latestBytes = latestScreenshotStore.storedBytes()
            let usage = ClipboardCacheUsage(
                usedBytes: clipboard.usedBytes + screenshots.bytes + latestBytes,
                capacityBytes: clipboard.capacityBytes,
                fileCount: clipboard.fileCount + screenshots.fileCount + (latestBytes > 0 ? 1 : 0),
                clipboardBytes: clipboard.usedBytes,
                screenshotBytes: screenshots.bytes + latestBytes
            )
            DispatchQueue.main.async {
                self?.clipboardCacheUsage = usage
            }
        }
    }

    @discardableResult
    func admitSharedCacheBytes(_ incomingBytes: Int64, notify: Bool = true) -> Bool {
        let clipboard = clipboardCacheStore.usage()
        let screenshots = screenshotHistoryStore.storedUsage()
        let latestBytes = screenshotCacheStore.storedBytes()
        let allowed = SharedCacheAdmission.allows(
            usedBytes: clipboard.usedBytes + screenshots.bytes + latestBytes,
            capacityBytes: clipboard.capacityBytes,
            incomingBytes: incomingBytes
        )
        if !allowed, notify {
            notifySharedCacheFull()
        }
        return allowed
    }

    func notifySharedCacheFull() {
        let now = Date()
        if let lastCacheFullNotice, now.timeIntervalSince(lastCacheFullNotice) < 3 {
            return
        }
        lastCacheFullNotice = now
        showToast(JarvisFeedbackCopy.cacheFull)
    }

    func updateClipboardCacheMaximumBytes(_ value: Int64) {
        let requestedMaximum = ClipboardCacheStore.normalizedMaximumBytes(value)
        let clipboard = clipboardCacheStore.usage()
        let screenshots = screenshotHistoryStore.storedUsage()
        let latestBytes = screenshotCacheStore.storedBytes()
        let usedBytes = clipboard.usedBytes + screenshots.bytes + latestBytes
        let usage = ClipboardCacheUsage(
            usedBytes: usedBytes,
            capacityBytes: clipboard.capacityBytes,
            fileCount: clipboard.fileCount + screenshots.fileCount + (latestBytes > 0 ? 1 : 0),
            clipboardBytes: clipboard.usedBytes,
            screenshotBytes: screenshots.bytes + latestBytes
        )
        guard requestedMaximum >= usedBytes else {
            JarvisLog.notice(
                category: .clipboard,
                event: "cache.capacityChange.rejected",
                result: "belowCurrentUsage",
                fields: [
                    "requestedBytes": String(requestedMaximum),
                    "usedBytes": String(usage.usedBytes)
                ]
            )
            showToast(JarvisFeedbackCopy.cacheMinimumTooLow(cacheSizeDescription(usage.usedBytes)))
            clipboardCacheUsage = usage
            return
        }

        clipboardCacheStore.updateMaximumBytes(requestedMaximum)
        clipboardCacheMaximumBytes = clipboardCacheStore.currentMaximumBytes
        refreshClipboardCacheUsage()
    }

    func updateClipboardCacheAutoCleanupEnabled(_ enabled: Bool) {
        updateClipboardCacheAutoCleanupPeriod(enabled ? .sevenDays : .never)
    }

    func updateClipboardCacheAutoCleanupPeriod(_ period: ClipboardCacheCleanupPeriod) {
        clipboardCacheAutoCleanupPeriod = period
        clipboardCacheAutoCleanupEnabled = period != .never
        UserDefaults.standard.set(period.rawValue, forKey: clipboardCacheAutoCleanupPeriodKey)
        UserDefaults.standard.set(clipboardCacheAutoCleanupEnabled, forKey: clipboardCacheAutoCleanupEnabledKey)
        JarvisLog.info(
            category: .clipboard,
            event: "cache.autoCleanupPeriod.changed",
            fields: ["period": period.rawValue]
        )
        configureClipboardCacheAutoCleanup()
    }

    @discardableResult
    func clearClipboardCache(
        category: ClipboardCacheCategory = .all,
        olderThan: Date? = nil,
        automatically: Bool = false
    ) -> Int {
        let reason = automatically ? "automatic.age" : "manual.category"
        JarvisLog.notice(
            category: .clipboard,
            event: "cache.cleanup.begin",
            fields: [
                "reason": reason,
                "category": category.rawValue,
                "hasCutoff": String(olderThan != nil)
            ]
        )
        guard category != .favorites else {
            if !automatically {
                showToast(JarvisFeedbackCopy.pinnedCacheManual)
            }
            return 0
        }

        let candidates = clipboardItems.filter { item in
            let matchesAge = olderThan.map { item.createdAt < $0 } ?? true
            return !item.isPinned
                && category.matches(item)
                && matchesAge
                && clipboardCacheStore.hasManagedReferences(for: item)
        }

        var removedIDs = Set<UUID>()
        var failedCount = 0
        for item in candidates {
            if clipboardCacheStore.removeManagedFiles(for: [item], reason: reason) {
                removedIDs.insert(item.id)
            } else {
                failedCount += 1
            }
        }
        clipboardItems.removeAll { removedIDs.contains($0.id) }

        var removedScreenshotCount = 0
        if category == .all, let olderThan {
            removedScreenshotCount = screenshotHistoryStore.delete(olderThan: olderThan)
            if removedScreenshotCount > 0 {
                screenshotHistory = screenshotHistoryStore.load()
            }
            if screenshotCacheStore.removeIfModified(before: olderThan) {
                latestScreenshotData = nil
                removedScreenshotCount += 1
            }
        }

        var didChange = !removedIDs.isEmpty || removedScreenshotCount > 0
        if category == .all {
            let referencedPaths = Set(
                clipboardItems.flatMap { item in
                    item.cachePaths
                }
            )
            didChange = clipboardCacheStore.removeOrphanedManagedFiles(
                referencedPaths: referencedPaths,
                olderThan: olderThan,
                reason: reason
            ) || didChange
        }

        guard didChange else {
            if !automatically, failedCount > 0 {
                showToast(JarvisFeedbackCopy.cacheCleanupFailed(failedCount))
            } else if !automatically {
                showToast(JarvisFeedbackCopy.noMatchingCache)
            }
            JarvisLog.info(
                category: .clipboard,
                event: "cache.cleanup.complete",
                result: "noOp",
                fields: [
                    "reason": reason,
                    "candidateCount": String(candidates.count),
                    "failedCount": String(failedCount)
                ]
            )
            return 0
        }

        if !persistClipboardHistory() {
            showToast(JarvisFeedbackCopy.saveFailed)
        }
        refreshClipboardCacheUsage()
        if !automatically {
            let removedCount = removedIDs.count + removedScreenshotCount
            if failedCount > 0 {
                showToast(JarvisFeedbackCopy.cleanedCachePartial(
                    removed: removedCount,
                    failed: failedCount
                ))
            } else {
                showToast(JarvisFeedbackCopy.cleanedCache(removedCount))
            }
        }
        JarvisLog.info(
            category: .clipboard,
            event: "cache.cleanup.complete",
            result: failedCount == 0 ? "success" : "partialFailure",
            fields: [
                "reason": reason,
                "removedCount": String(removedIDs.count),
                "removedScreenshotCount": String(removedScreenshotCount),
                "failedCount": String(failedCount)
            ]
        )
        return removedIDs.count + removedScreenshotCount
    }

    func chooseClipboardCacheDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择用于保存剪贴板文件的文件夹。截图仍在应用目录，占用计入同一上限。"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let oldDirectoryURL = clipboardCacheStore.currentDirectoryURL
            let migration = try clipboardCacheStore.migrateManagedFiles(
                for: clipboardItems,
                to: url
            )
            clipboardItems = migration.items
            clipboardCacheDirectoryURL = clipboardCacheStore.currentDirectoryURL
            if !persistClipboardHistory() {
                if let rollback = try? clipboardCacheStore.migrateManagedFiles(
                    for: clipboardItems,
                    to: oldDirectoryURL
                ) {
                    clipboardItems = rollback.items
                    clipboardCacheStore.removeLegacyFiles(
                        atPaths: rollback.legacyPaths,
                        reason: "cacheDirectoryMigrationRollback"
                    )
                    clipboardCacheDirectoryURL = clipboardCacheStore.currentDirectoryURL
                }
                showToast(JarvisFeedbackCopy.saveFailed)
            } else {
                clipboardCacheStore.removeLegacyFiles(
                    atPaths: migration.legacyPaths,
                    reason: "cacheDirectoryMigrationComplete"
                )
                showToast(JarvisFeedbackCopy.cacheDirectoryUpdated)
            }
            refreshClipboardCacheUsage()
        } catch {
            JarvisLog.error(
                category: .clipboard,
                event: "cache.directoryChange.failed",
                error: error
            )
            showToast(JarvisFeedbackCopy.cacheDirectorySwitchFailed)
        }
    }

    private func cacheSizeDescription(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter.string(fromByteCount: bytes)
    }

    func loadClipboardCacheCleanupSettings() {
        let defaults = UserDefaults.standard
        automaticClipboardRecordingEnabled = defaults.object(forKey: clipboardRecordingEnabledKey) as? Bool ?? true
        hideSensitiveClipboardContent = defaults.object(forKey: hideSensitiveClipboardContentKey) as? Bool ?? true
        let wasCleanupEnabled = defaults.bool(forKey: clipboardCacheAutoCleanupEnabledKey)
        if wasCleanupEnabled {
            let savedPeriod = defaults.string(forKey: clipboardCacheAutoCleanupPeriodKey)
                .flatMap(ClipboardCacheCleanupPeriod.init(rawValue:))
            clipboardCacheAutoCleanupPeriod = savedPeriod.flatMap { $0 == .never ? nil : $0 } ?? .sevenDays
        } else {
            clipboardCacheAutoCleanupPeriod = .never
        }
        clipboardCacheAutoCleanupEnabled = clipboardCacheAutoCleanupPeriod != .never
    }

    func configureClipboardCacheAutoCleanup() {
        clipboardCacheCleanupTimer?.invalidate()
        clipboardCacheCleanupTimer = nil
        guard clipboardCacheAutoCleanupEnabled,
              let cutoffDate = clipboardCacheAutoCleanupPeriod.cutoffDate
        else {
            JarvisLog.debug(
                category: .clipboard,
                event: "cache.autoCleanup.disabled"
            )
            return
        }

        JarvisLog.info(
            category: .clipboard,
            event: "cache.autoCleanup.started",
            fields: ["period": clipboardCacheAutoCleanupPeriod.rawValue]
        )
        clearClipboardCache(olderThan: cutoffDate, automatically: true)
        clipboardCacheCleanupTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let cutoffDate = self.clipboardCacheAutoCleanupPeriod.cutoffDate
                else { return }
                self.clearClipboardCache(
                    olderThan: cutoffDate,
                    automatically: true
                )
            }
        }
    }
}
