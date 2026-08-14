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
        clipboardItems.insert(item, at: 0)
        let removedItems = Array(clipboardItems.dropFirst(ClipboardLimits.maximumItemCount))
        clipboardItems = Array(clipboardItems.prefix(ClipboardLimits.maximumItemCount))
        clipboardStore.removeStoredFiles(for: removedItems)
        if !clipboardStore.save(clipboardItems) {
            statusMessage = "剪贴板历史保存失败"
        }
    }

    func copyClipboard(_ item: ClipboardItem) {
        guard writeClipboardItem(item) else {
            statusMessage = "内容已不可用，可能已被移动或删除"
            return
        }
        clipboardService.markCurrentPasteboardAsHandled()
        statusMessage = "已复制 \(item.preview)"
    }

    func showClipboardMediaPreview(_ item: ClipboardItem) {
        guard item.kind == .image || item.kind == .video else {
            copyClipboard(item)
            return
        }
        guard item.hasLocalContent else {
            statusMessage = "媒体文件已不可用"
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
        clipboardItems.sort {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned
            }
            return $0.createdAt > $1.createdAt
        }
        guard clipboardStore.save(clipboardItems) else {
            statusMessage = "剪贴板收藏状态保存失败"
            return
        }
        statusMessage = clipboardItems.first(where: { $0.id == item.id })?.isPinned == true
            ? "已收藏剪贴板内容"
            : "已取消收藏"
    }

    func revealClipboardItem(_ item: ClipboardItem) {
        let path = item.kind == .image ? item.imagePath : item.filePath
        guard let path, FileManager.default.fileExists(atPath: path) else {
            statusMessage = "本地文件已不可用"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
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
            statusMessage = "剪贴板历史保存失败"
        }
    }

    func clearClipboardHistory() {
        clipboardStore.removeStoredFiles(for: clipboardItems)
        clipboardItems.removeAll()
        statusMessage = clipboardStore.save(clipboardItems)
            ? "剪贴板历史已清空"
            : "剪贴板历史清空后保存失败"
    }
}
