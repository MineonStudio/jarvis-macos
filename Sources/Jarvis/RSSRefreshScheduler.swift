import AppKit
import Foundation
import UserNotifications

/// 后台刷新的调度。
///
/// 用 `NSBackgroundActivityScheduler` 而不是 `Timer`：系统会合并唤醒、跟着 App Nap
/// 和热状态让路，这正是「每 30 分钟拉一次网络」该有的样子。每个 feed 各起一个
/// 定时器是这类模块最常见的耗电写法，这里刻意只留一个调度器。
@MainActor
final class RSSRefreshScheduler {
    enum Interval: String, CaseIterable, Identifiable, Sendable {
        case fifteenMinutes
        case thirtyMinutes
        case hourly
        case manual

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .fifteenMinutes: "每 15 分钟"
            case .thirtyMinutes: "每 30 分钟"
            case .hourly: "每小时"
            case .manual: "仅手动刷新"
            }
        }

        /// `nil` 表示不排后台任务。
        var seconds: TimeInterval? {
            switch self {
            case .fifteenMinutes: 15 * 60
            case .thirtyMinutes: 30 * 60
            case .hourly: 60 * 60
            case .manual: nil
            }
        }

        static let `default`: Interval = .thirtyMinutes
    }

    private var scheduler: NSBackgroundActivityScheduler?
    private var handler: (@MainActor () async -> Void)?

    var isRunning: Bool {
        scheduler != nil
    }

    func start(interval: Interval, handler: @escaping @MainActor () async -> Void) {
        self.handler = handler
        stop()
        guard let seconds = interval.seconds else {
            JarvisLog.info(category: .network, event: "rss.scheduler.disabled")
            return
        }

        let scheduler = NSBackgroundActivityScheduler(
            identifier: "\(JarvisAppIdentity.bundleIdentifier).rss.refresh"
        )
        scheduler.interval = seconds
        // 容忍一半的窗口：让系统挑它方便的时间点，别和别的唤醒撞在一起。
        scheduler.tolerance = seconds / 2
        scheduler.repeats = true
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            guard let self else {
                completion(.finished)
                return
            }
            Task { @MainActor in
                await self.runScheduledRefresh()
                completion(.finished)
            }
        }
        self.scheduler = scheduler
        JarvisLog.info(
            category: .network,
            event: "rss.scheduler.started",
            fields: ["intervalSeconds": String(Int(seconds))]
        )
    }

    func stop() {
        scheduler?.invalidate()
        scheduler = nil
    }

    private func runScheduledRefresh() async {
        // 低电量模式下不主动联网，用户手动刷新不受影响。
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            JarvisLog.notice(
                category: .network,
                event: "rss.refresh.skipped",
                result: "skipped",
                fields: ["reason": "lowPowerMode"]
            )
            return
        }
        await handler?()
    }
}

/// 新文章的系统通知。
@MainActor
final class RSSNotificationService: NSObject {
    private(set) var isAuthorized = false
    private var hasRequestedAuthorization = false

    /// 首次订阅成功后再申请，用户那时才明白为什么要这个权限。
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        guard !hasRequestedAuthorization else { return isAuthorized }
        hasRequestedAuthorization = true
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            isAuthorized = granted
            JarvisLog.info(
                category: .network,
                event: "rss.notifications.authorization",
                result: granted ? "granted" : "denied"
            )
            return granted
        } catch {
            JarvisLog.error(
                category: .network,
                event: "rss.notifications.authorizationFailed",
                error: error
            )
            return false
        }
    }

    func refreshAuthorizationState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    /// 把这一轮的新文章汇总成通知：一条足够，多了就是打扰。
    func post(newItems: [RSSItem], feedTitles: [UUID: String], limit: Int = 3) {
        guard isAuthorized, !newItems.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.sound = .default
        if newItems.count == 1, let item = newItems.first {
            content.title = item.title
            content.subtitle = feedTitles[item.feedID] ?? ""
            content.body = RSSArticleRenderer.previewText(fromHTML: item.summaryHTML, limit: 120)
        } else {
            content.title = "\(newItems.count) 篇新文章"
            content.body = newItems.prefix(limit).map(\.title).joined(separator: "\n")
        }
        content.userInfo = ["itemID": newItems.first?.id ?? ""]

        let request = UNNotificationRequest(
            identifier: "jarvis.rss.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            guard let error else { return }
            Task { @MainActor in
                JarvisLog.error(
                    category: .network,
                    event: "rss.notifications.postFailed",
                    error: error
                )
            }
        }
    }
}

/// 点通知直接跳到那篇文章，否则通知只是噪音。
@MainActor
final class RSSNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onOpenItem: (@MainActor (String) -> Void)?

    /// 这两个回调由系统在它自己的线程上调用，协议要求也不是 main actor 的，
    /// 所以先取出可发送的值，再跳回主 actor 处理。
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let itemID = response.notification.request.content.userInfo["itemID"] as? String,
              !itemID.isEmpty
        else {
            return
        }
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            self.onOpenItem?(itemID)
        }
    }
}
