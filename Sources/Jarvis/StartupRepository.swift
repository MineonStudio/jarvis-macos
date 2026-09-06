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

        return JarvisStartupSnapshot(
            clipboardItems: clipboardStore.load(),
            screenshotHistory: screenshotHistoryStore.load(),
            cachedScreenshot: screenshotCacheStore.load(),
            clipboardCacheUsage: clipboardCacheStore.usage()
        )
    }
}

actor ClipboardHistoryWriter {
    private let store = ClipboardStore()

    func save(_ items: [ClipboardItem]) -> Bool {
        store.save(items)
    }
}
