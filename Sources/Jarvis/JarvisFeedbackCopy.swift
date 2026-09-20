import Foundation

/// Short toast phrases. Success states the result; failures state the reason.
/// Do not repeat the control label ("到剪贴板", "历史截图") or append
/// `localizedDescription`.
enum JarvisFeedbackCopy {
    static let displayDurationNanoseconds: UInt64 = 1_800_000_000

    static let copied = "复制成功"
    static let saved = "已保存"
    static let deleted = "已删除"
    static let favorited = "已收藏"
    static let unfavorited = "已取消收藏"
    static let applied = "已设置"
    static let exported = "已导出"
    static let opened = "已打开"
    static let created = "已新建"
    static let saveFailed = "保存失败"
    static let deleteFailed = "删除失败"
    static let exportFailed = "导出失败"
    static let applyFailed = "设置失败"
    static let favoriteFailed = "收藏失败"
    static let fileMissing = "文件不存在"
    static let contentUnavailable = "内容已不可用"
    static let textUnavailable = "文本已不可用"
    static let mediaUnavailable = "媒体文件已不可用"
    static let cannotPreview = "无法预览"
    static let invalidJSON = "文件格式无效"
    static let originalImageLoadFailed = "原图加载失败"
    static let wallpaperBusy = "正在设置…"
    static let wallpaperFileUnavailable = "文件不可用"
    static let historySaveFailed = "历史保存失败"
    static let cacheSaveFailed = "缓存保存失败"
    static let cacheClearFailed = "清除失败"
    static let noMatchingCache = "没有符合条件的缓存"
    static let pinnedCacheManual = "已收藏内容需手动清理"
    static let cacheDirectoryUpdated = "缓存目录已更新"
    static let cacheDirectorySwitchFailed = "切换失败"
    static let finishScreenshotFirst = "请先完成当前截图操作"
    static let recapture = "请重新框选"
    static let noDisplays = "没有可用显示器"
    static let captureFailed = "截图失败"
    static let connectionSucceeded = "连接成功"
    static let connectionFailed = "连接失败"
    static let apiKeyReadFailed = "读取 API Key 失败"
    static let selectModelFirst = "请先刷新并选择模型"
    static let apiKeyRequired = "请输入 API Key"
    static let httpsRequired = "接口地址需要是 HTTPS 地址"
    static let fillAPIFields = "请先填写接口地址、模型和 API Key"
    static let launchAtLoginOn = "已开启开机自启"
    static let launchAtLoginOff = "已关闭开机自启"
    static let launchAtLoginFailed = "开机自启失败"
    static let latestVersion = "当前已是最新版本"
    static let updateCheckFailed = "检查更新失败"
    static let updateFailed = "更新失败"
    static let recordingStarted = "已开始录音"
    static let recordingStartedWithoutSystemAudio = "已开始录音，未采集系统音频"
    static let recordingInterrupted = "录音已中断，正在处理"
    static let recordingStartFailed = "开始录音失败"
    static let downloadModelsFirst = "请先下载识别模型"
    static let finishRecordingFirst = "请先结束录音"
    static let nothingToCopy = "没有可复制的内容"
    static let nothingToExport = "没有可导出的内容"
    static let configureAIFirst = "请先配置 AI 服务"
    static let summaryReady = "总结已生成"
    static let summaryFailed = "纪要生成失败"
    static let processingFailed = "处理失败"
    static let microphoneRequired = "请允许麦克风权限"
    static let shortcutUpdated = "快捷键已更新"
    static let shortcutServiceUnavailable = "快捷键服务未就绪"
    static let accessibilityRequired = "请先开启辅助功能"
    static let noAdjustableWindow = "没有可调整的窗口"
    static let cannotReadWindow = "无法读取窗口位置"
    static let windowNotResizable = "窗口无法调整"

    static func refreshedModels(_ count: Int) -> String {
        "已刷新 \(count) 个模型"
    }

    static func resumeSaved(as format: String) -> String {
        "已保存为 \(format)"
    }

    static func generatedResumeItems(_ count: Int, section: String) -> String {
        "已生成 \(count) 条\(section)"
    }

    static func cleanedCache(_ count: Int) -> String {
        "已清理 \(count) 条缓存"
    }

    static func cleanedCachePartial(removed: Int, failed: Int) -> String {
        "已清理 \(removed) 条，\(failed) 条失败"
    }

    static func cacheCleanupFailed(_ count: Int) -> String {
        "有 \(count) 条无法清理"
    }

    static func cacheMinimumTooLow(_ size: String) -> String {
        "上限不能低于当前占用 \(size)"
    }

    static func recordingsUsageWarning(_ gigabytes: Double) -> String {
        String(format: "录音已占用 %.1f GB", gigabytes)
    }

    static func windowAdjusted(_ layoutTitle: String) -> String {
        "已调整为\(layoutTitle)"
    }
}
