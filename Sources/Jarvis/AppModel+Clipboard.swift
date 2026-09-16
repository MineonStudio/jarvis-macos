import AppKit

extension AppModel {
    // MARK: - Clipboard workflow

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
            trimClipboardCacheIfNeeded(forAdditionalBytes: Int64(data.count))
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
        let overflowItems = Array(clipboardItems.dropFirst(ClipboardLimits.maximumItemCount))
        clipboardItems = Array(clipboardItems.prefix(ClipboardLimits.maximumItemCount))
        trimClipboardCacheIfNeeded()
        scheduleClipboardHistorySave()

        let preservedPaths = Set(item.cachePaths)
        let stalePaths = matchingItems.flatMap(\.cachePaths).filter { !preservedPaths.contains($0) }
            + overflowItems.flatMap(\.cachePaths)
        clipboardCacheStore.removeLegacyFiles(
            atPaths: stalePaths,
            reason: "historyReplacementOrOverflow"
        )
        JarvisLog.info(
            category: .clipboard,
            event: "history.itemApplied",
            result: "success",
            fields: [
                "recordCount": String(clipboardItems.count),
                "overflowCount": String(overflowItems.count),
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
                self.showToast("剪贴板历史保存失败")
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
            showToast("内容已不可用，可能已被移动或删除")
            return
        }
        JarvisLog.info(
            category: .clipboard,
            event: "history.copy.complete",
            result: "success",
            fields: ["kind": item.kind.rawValue]
        )
        clipboardService.markCurrentPasteboardAsHandled()
        showToast(item.isSensitive ? "已复制敏感内容" : "已复制 \(item.preview)")
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
            showToast(item.kind == .text ? "文本已不可用" : "媒体文件已不可用")
            return
        }
        clipboardMediaPreviewController.show(item: item)
    }

    func showClipboardPanel() {
        guard requireAllPermissions() else { return }
        clipboardPanelController.show(app: self)
    }

    func closeClipboardPanel() {
        clipboardPanelController.close()
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
            showToast("剪贴板收藏状态保存失败")
            return
        }
        showToast(clipboardItems.first(where: { $0.id == item.id })?.isPinned == true
            ? "已收藏剪贴板内容"
            : "已取消收藏")
    }

    func revealClipboardItem(_ item: ClipboardItem) {
        let path = item.kind == .image ? item.imagePath : item.filePath
        guard let path, FileManager.default.fileExists(atPath: path) else {
            JarvisLog.notice(
                category: .clipboard,
                event: "history.reveal.failed",
                result: "contentUnavailable",
                fields: ["kind": item.kind.rawValue]
            )
            showToast("本地文件已不可用")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        showToast("已在 Finder 中显示")
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
            showToast("剪贴板历史保存失败")
            return
        }
        refreshClipboardCacheUsage()
        JarvisLog.info(
            category: .clipboard,
            event: "history.delete.complete",
            result: "success",
            fields: ["recordCount": String(clipboardItems.count)]
        )
        showToast("已删除剪贴板记录")
    }

    func clearClipboardHistory() {
        JarvisLog.notice(
            category: .clipboard,
            event: "history.clear.begin",
            fields: ["recordCount": String(clipboardItems.count)]
        )
        _ = clipboardCacheStore.removeManagedFiles(
            for: clipboardItems,
            reason: "userClearHistory"
        )
        clipboardItems.removeAll()
        if persistClipboardHistory() {
            refreshClipboardCacheUsage()
            JarvisLog.info(
                category: .clipboard,
                event: "history.clear.complete",
                result: "success"
            )
            showToast("剪贴板历史已清空")
        } else {
            showToast("剪贴板历史清空后保存失败")
        }
    }

    func refreshClipboardCacheUsage() {
        let cacheStore = clipboardCacheStore
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let usage = cacheStore.usage()
            DispatchQueue.main.async {
                self?.clipboardCacheUsage = usage
            }
        }
    }

    func updateClipboardCacheMaximumBytes(_ value: Int64) {
        let requestedMaximum = ClipboardCacheStore.normalizedMaximumBytes(value)
        let usage = clipboardCacheStore.usage()
        guard requestedMaximum >= usage.usedBytes else {
            JarvisLog.notice(
                category: .clipboard,
                event: "cache.capacityChange.rejected",
                result: "belowCurrentUsage",
                fields: [
                    "requestedBytes": String(requestedMaximum),
                    "usedBytes": String(usage.usedBytes)
                ]
            )
            showToast("缓存空间上限不能低于当前占用 \(cacheSizeDescription(usage.usedBytes))")
            clipboardCacheUsage = usage
            return
        }

        clipboardCacheStore.updateMaximumBytes(requestedMaximum)
        clipboardCacheMaximumBytes = clipboardCacheStore.currentMaximumBytes
        trimClipboardCacheIfNeeded()
        refreshClipboardCacheUsage()
    }

    func updateClipboardCacheAutoCleanupEnabled(_ enabled: Bool) {
        clipboardCacheAutoCleanupEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: clipboardCacheAutoCleanupEnabledKey)
        JarvisLog.info(
            category: .clipboard,
            event: "cache.autoCleanup.changed",
            fields: ["enabled": String(enabled)]
        )
        configureClipboardCacheAutoCleanup()
    }

    func updateClipboardCacheAutoCleanupPeriod(_ period: ClipboardCacheCleanupPeriod) {
        clipboardCacheAutoCleanupPeriod = period
        UserDefaults.standard.set(period.rawValue, forKey: clipboardCacheAutoCleanupPeriodKey)
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
                showToast("已收藏内容只能在剪贴板模块中手动清理")
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

        var didChange = !removedIDs.isEmpty
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
                showToast("有 \(failedCount) 条缓存无法清理，请检查文件权限或占用情况")
            } else if !automatically {
                showToast("没有符合条件的缓存")
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
            showToast("缓存清理后历史记录保存失败")
        }
        refreshClipboardCacheUsage()
        if !automatically {
            if failedCount > 0 {
                showToast("已清理 \(removedIDs.count) 条缓存，\(failedCount) 条无法清理")
            } else {
                showToast("已清理 \(removedIDs.count) 条缓存")
            }
        }
        JarvisLog.info(
            category: .clipboard,
            event: "cache.cleanup.complete",
            result: failedCount == 0 ? "success" : "partialFailure",
            fields: [
                "reason": reason,
                "removedCount": String(removedIDs.count),
                "failedCount": String(failedCount)
            ]
        )
        return removedIDs.count
    }

    func chooseClipboardCacheDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择用于保存剪贴板文件和图片的缓存文件夹"
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
                showToast("缓存目录已切换，但历史记录保存失败")
            } else {
                clipboardCacheStore.removeLegacyFiles(
                    atPaths: migration.legacyPaths,
                    reason: "cacheDirectoryMigrationComplete"
                )
                showToast("剪贴板缓存目录已更新")
            }
            trimClipboardCacheIfNeeded()
            refreshClipboardCacheUsage()
        } catch {
            JarvisLog.error(
                category: .clipboard,
                event: "cache.directoryChange.failed",
                error: error
            )
            showToast("缓存目录切换失败：\(error.localizedDescription)")
        }
    }

    func trimClipboardCacheIfNeeded(forAdditionalBytes additionalBytes: Int64 = 0) {
        var usage = clipboardCacheStore.usage()
        let needsRoom: (ClipboardCacheUsage) -> Bool = { usage in
            usage.isOverCapacity
                || additionalBytes > max(0, usage.capacityBytes - usage.usedBytes)
        }
        guard needsRoom(usage) else { return }
        guard additionalBytes <= usage.capacityBytes || usage.isOverCapacity else { return }

        let candidates = clipboardItems
            .filter { !$0.isPinned && clipboardCacheStore.hasManagedReferences(for: $0) }
            .sorted { $0.createdAt < $1.createdAt }
        var changed = false
        for item in candidates where needsRoom(usage) {
            guard clipboardCacheStore.removeManagedFiles(
                for: [item],
                reason: "automatic.capacity"
            ) else { continue }
            if item.kind == .text, item.text != nil,
               let index = clipboardItems.firstIndex(where: { $0.id == item.id })
            {
                clipboardItems[index].textPath = nil
                clipboardItems[index].isStoredCopy = false
            } else {
                clipboardItems.removeAll { $0.id == item.id }
            }
            usage = clipboardCacheStore.usage()
            changed = true
        }

        if needsRoom(usage) {
            let referencedPaths = Set(
                clipboardItems.flatMap { item in
                    item.cachePaths
                }
            )
            if clipboardCacheStore.removeOrphanedManagedFiles(
                referencedPaths: referencedPaths,
                reason: "automatic.capacity"
            ) {
                usage = clipboardCacheStore.usage()
                changed = true
            }
        }
        if changed, !persistClipboardHistory() {
            JarvisLog.error(
                category: .clipboard,
                event: "history.saveAfterTrim.failed",
                fields: ["recordCount": String(clipboardItems.count)]
            )
            showToast("剪贴板历史保存失败")
        }
        if changed {
            JarvisLog.info(
                category: .clipboard,
                event: "cache.capacityTrim.complete",
                fields: [
                    "remainingRecordCount": String(clipboardItems.count),
                    "usedBytes": String(usage.usedBytes),
                    "capacityBytes": String(usage.capacityBytes)
                ]
            )
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
        clipboardCacheAutoCleanupEnabled = defaults.bool(forKey: clipboardCacheAutoCleanupEnabledKey)
        if let rawValue = defaults.string(forKey: clipboardCacheAutoCleanupPeriodKey),
           let period = ClipboardCacheCleanupPeriod(rawValue: rawValue)
        {
            clipboardCacheAutoCleanupPeriod = period
        }
    }

    func configureClipboardCacheAutoCleanup() {
        clipboardCacheCleanupTimer?.invalidate()
        clipboardCacheCleanupTimer = nil
        guard clipboardCacheAutoCleanupEnabled else {
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
        clearClipboardCache(olderThan: clipboardCacheAutoCleanupPeriod.cutoffDate, automatically: true)
        clipboardCacheCleanupTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.clearClipboardCache(
                    olderThan: self.clipboardCacheAutoCleanupPeriod.cutoffDate,
                    automatically: true
                )
            }
        }
    }
}
