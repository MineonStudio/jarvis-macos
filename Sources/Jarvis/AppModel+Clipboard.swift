import AppKit

extension AppModel {
    // MARK: - Clipboard workflow

    func migrateClipboardTextCache() {
        var didChange = false
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
        }

        if didChange, !clipboardStore.save(clipboardItems) {
            JarvisPersistenceLog.logger.error("迁移文本剪贴板缓存失败：无法保存历史记录")
        }
    }

    func receiveClipboardItem(_ item: ClipboardItem) {
        let matchingItems = clipboardItems.filter { $0.fingerprint == item.fingerprint }
        let wasPinned = matchingItems.contains(where: \.isPinned)
        var item = item
        item.isPinned = wasPinned

        if item.kind != .text,
           !item.hasLocalContent,
           matchingItems.contains(where: \.hasLocalContent)
        {
            return
        }

        let previousItems = clipboardItems
        clipboardItems.removeAll { $0.fingerprint == item.fingerprint }
        clipboardItems.append(item)
        clipboardItems = ClipboardOrdering.newestFirst(clipboardItems)
        let overflowItems = Array(clipboardItems.dropFirst(ClipboardLimits.maximumItemCount))
        clipboardItems = Array(clipboardItems.prefix(ClipboardLimits.maximumItemCount))
        trimClipboardCacheIfNeeded()
        guard clipboardStore.save(clipboardItems) else {
            clipboardItems = previousItems
            showToast("剪贴板历史保存失败")
            return
        }

        let preservedPaths = Set(item.cachePaths)
        let stalePaths = matchingItems.flatMap(\.cachePaths).filter { !preservedPaths.contains($0) }
            + overflowItems.flatMap(\.cachePaths)
        clipboardCacheStore.removeLegacyFiles(atPaths: stalePaths)
        refreshClipboardCacheUsage()
    }

    func copyClipboard(_ item: ClipboardItem) {
        guard writeClipboardItem(item) else {
            showToast("内容已不可用，可能已被移动或删除")
            return
        }
        clipboardService.markCurrentPasteboardAsHandled()
        showToast("已复制 \(item.preview)")
    }

    func showClipboardMediaPreview(_ item: ClipboardItem) {
        guard item.kind == .image || item.kind == .video else {
            copyClipboard(item)
            return
        }
        guard item.hasLocalContent else {
            showToast("媒体文件已不可用")
            return
        }
        clipboardMediaPreviewController.show(item: item)
    }

    func showClipboardPanel() {
        clipboardPanelController.show(app: self)
    }

    func closeClipboardPanel() {
        clipboardPanelController.close()
    }

    func toggleClipboardPin(_ item: ClipboardItem) {
        guard let index = clipboardItems.firstIndex(where: { $0.id == item.id }) else { return }
        clipboardItems[index].isPinned.toggle()
        guard clipboardStore.save(clipboardItems) else {
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
        _ = clipboardCacheStore.removeManagedFiles(for: [item])
        clipboardItems.removeAll { $0.id == item.id }
        if !clipboardStore.save(clipboardItems) {
            showToast("剪贴板历史保存失败")
            return
        }
        refreshClipboardCacheUsage()
        showToast("已删除剪贴板记录")
    }

    func clearClipboardHistory() {
        _ = clipboardCacheStore.removeManagedFiles(for: clipboardItems)
        clipboardItems.removeAll()
        if clipboardStore.save(clipboardItems) {
            refreshClipboardCacheUsage()
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
        configureClipboardCacheAutoCleanup()
    }

    func updateClipboardCacheAutoCleanupPeriod(_ period: ClipboardCacheCleanupPeriod) {
        clipboardCacheAutoCleanupPeriod = period
        UserDefaults.standard.set(period.rawValue, forKey: clipboardCacheAutoCleanupPeriodKey)
        configureClipboardCacheAutoCleanup()
    }

    @discardableResult
    func clearClipboardCache(
        category: ClipboardCacheCategory = .all,
        olderThan: Date? = nil,
        automatically: Bool = false
    ) -> Int {
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
                && clipboardCacheStore.hasManagedFiles(for: item)
        }

        var removedIDs = Set<UUID>()
        var failedCount = 0
        for item in candidates {
            if clipboardCacheStore.removeManagedFiles(for: [item]) {
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
                olderThan: olderThan
            ) || didChange
        }

        guard didChange else {
            if !automatically, failedCount > 0 {
                showToast("有 \(failedCount) 条缓存无法清理，请检查文件权限或占用情况")
            } else if !automatically {
                showToast("没有符合条件的缓存")
            }
            return 0
        }

        if !clipboardStore.save(clipboardItems) {
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
            if !clipboardStore.save(clipboardItems) {
                if let rollback = try? clipboardCacheStore.migrateManagedFiles(
                    for: clipboardItems,
                    to: oldDirectoryURL
                ) {
                    clipboardItems = rollback.items
                    clipboardCacheStore.removeLegacyFiles(atPaths: rollback.legacyPaths)
                    clipboardCacheDirectoryURL = clipboardCacheStore.currentDirectoryURL
                }
                showToast("缓存目录已切换，但历史记录保存失败")
            } else {
                clipboardCacheStore.removeLegacyFiles(atPaths: migration.legacyPaths)
                showToast("剪贴板缓存目录已更新")
            }
            trimClipboardCacheIfNeeded()
            refreshClipboardCacheUsage()
        } catch {
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
            .filter { !$0.isPinned && clipboardCacheStore.hasManagedFiles(for: $0) }
            .sorted { $0.createdAt < $1.createdAt }
        var changed = false
        for item in candidates where needsRoom(usage) {
            guard clipboardCacheStore.removeManagedFiles(for: [item]) else { continue }
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
            if clipboardCacheStore.removeOrphanedManagedFiles(referencedPaths: referencedPaths) {
                usage = clipboardCacheStore.usage()
                changed = true
            }
        }
        if changed, !clipboardStore.save(clipboardItems) {
            JarvisPersistenceLog.logger.error("清理剪贴板缓存后保存历史失败")
            showToast("剪贴板历史保存失败")
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
        guard clipboardCacheAutoCleanupEnabled else { return }

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
