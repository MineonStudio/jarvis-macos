import AppKit

extension AppModel {
    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Jarvis-diagnostics-\(Date().formatted(.iso8601)).zip"
        panel.message = "导出的诊断包只包含脱敏日志和缓存统计，不包含剪贴板正文。"
        guard panel.runModal() == .OK, let url = panel.url else {
            JarvisLog.debug(
                category: .storage,
                event: "diagnostics.export.cancelled"
            )
            return
        }

        do {
            _ = try JarvisDiagnosticsExporter.exportArchive(
                clipboardItems: clipboardItems,
                cacheStore: clipboardCacheStore,
                autoCleanupEnabled: clipboardCacheAutoCleanupEnabled,
                outputURL: url
            )
            showToast("诊断日志已导出")
        } catch {
            JarvisLog.error(
                category: .storage,
                event: "diagnostics.export.failed",
                error: error
            )
            showToast("诊断日志导出失败")
        }
    }
}
