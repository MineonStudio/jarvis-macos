import Foundation

struct JarvisStartupSnapshot: Sendable {
    let clipboardItems: [ClipboardItem]
    let screenshotHistory: [ScreenshotHistoryItem]
    let cachedScreenshot: Data?
    let clipboardCacheUsage: ClipboardCacheUsage
}

actor JarvisStartupRepository {
    func load() -> JarvisStartupSnapshot {
        let clipboardStore = ClipboardStore()
        let screenshotCacheStore = ScreenshotCacheStore()
        let screenshotHistoryStore = ScreenshotHistoryStore()
        let clipboardCacheStore = ClipboardCacheStore()

        let clipboardItems = clipboardStore.load()
        let screenshotHistory = screenshotHistoryStore.load()
        let cachedScreenshot = screenshotCacheStore.load()
        let clipboard = clipboardCacheStore.usage()
        let screenshots = screenshotHistoryStore.storedUsage()
        let latestBytes = screenshotCacheStore.storedBytes()
        return JarvisStartupSnapshot(
            clipboardItems: clipboardItems,
            screenshotHistory: screenshotHistory,
            cachedScreenshot: cachedScreenshot,
            clipboardCacheUsage: ClipboardCacheUsage(
                usedBytes: clipboard.usedBytes + screenshots.bytes + latestBytes,
                capacityBytes: clipboard.capacityBytes,
                fileCount: clipboard.fileCount + screenshots.fileCount + (latestBytes > 0 ? 1 : 0),
                clipboardBytes: clipboard.usedBytes,
                screenshotBytes: screenshots.bytes + latestBytes
            )
        )
    }
}

/// 剪贴板历史的后台写入者。与 AppModel 共用同一个 `ClipboardStore`，
/// 让版本号与文件锁只有一份，两个写入者才真正互斥。
actor ClipboardHistoryWriter {
    private let store: ClipboardStore

    init(store: ClipboardStore) {
        self.store = store
    }

    func save(_ items: [ClipboardItem], revision: UInt64) -> Bool {
        store.save(items, revision: revision)
    }
}
