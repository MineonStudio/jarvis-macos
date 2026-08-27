import AppKit

extension AppModel {
    // MARK: - Clipboard workflow

    func receiveClipboardItem(_ item: ClipboardItem) {
        let matchingItems = clipboardItems.filter { $0.fingerprint == item.fingerprint }
        let wasPinned = matchingItems.contains(where: \.isPinned)
        clipboardStore.removeStoredFiles(for: matchingItems)

        var item = item
        item.isPinned = wasPinned
        clipboardItems.removeAll { $0.fingerprint == item.fingerprint }
        clipboardItems.append(item)
        clipboardItems = ClipboardOrdering.newestFirst(clipboardItems)
        let removedItems = Array(clipboardItems.dropFirst(ClipboardLimits.maximumItemCount))
        clipboardItems = Array(clipboardItems.prefix(ClipboardLimits.maximumItemCount))
        clipboardStore.removeStoredFiles(for: removedItems)
        trimClipboardCacheIfNeeded()
        if !clipboardStore.save(clipboardItems) {
            showToast("剪贴板历史保存失败")
        }
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
        clipboardMediaPreviewController.show(item: item, app: self)
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
        clipboardStore.removeStoredFiles(for: [item])
        clipboardItems.removeAll { $0.id == item.id }
        if !clipboardStore.save(clipboardItems) {
            showToast("剪贴板历史保存失败")
            return
        }
        refreshClipboardCacheUsage()
        showToast("已删除剪贴板记录")
    }

    func clearClipboardHistory() {
        clipboardStore.removeStoredFiles(for: clipboardItems)
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
        clipboardCacheStore.updateMaximumBytes(value)
        clipboardCacheMaximumBytes = clipboardCacheStore.currentMaximumBytes
        trimClipboardCacheIfNeeded()
        refreshClipboardCacheUsage()
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
            refreshClipboardCacheUsage()
        } catch {
            showToast("缓存目录切换失败：\(error.localizedDescription)")
        }
    }

    private func trimClipboardCacheIfNeeded() {
        var usage = clipboardCacheStore.usage()
        guard usage.isOverCapacity else { return }

        let candidates = clipboardItems
            .filter { !$0.isPinned && $0.isStoredCopy }
            .sorted { $0.createdAt < $1.createdAt }
        var changed = false
        for item in candidates where usage.isOverCapacity {
            clipboardStore.removeStoredFiles(for: [item])
            clipboardItems.removeAll { $0.id == item.id }
            usage = clipboardCacheStore.usage()
            changed = true
        }
        if changed {
            _ = clipboardStore.save(clipboardItems)
        }
    }
}
