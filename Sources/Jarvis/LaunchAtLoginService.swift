import Foundation
import ServiceManagement

enum JarvisLaunchAtLoginPreference {
    static let key = "jarvis.launch-at-login.enabled"
    static let defaultValue = true

    static func load(from defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            defaults.set(defaultValue, forKey: key)
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }
}

@MainActor
final class JarvisLaunchAtLoginService {
    static let shared = JarvisLaunchAtLoginService()

    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    var statusDescription: String {
        switch status {
        case .enabled:
            "已在系统登录项中启用"
        case .requiresApproval:
            "等待在系统设置中确认"
        case .notRegistered:
            "未添加到系统登录项"
        case .notFound:
            "当前应用包不支持登录项"
        @unknown default:
            "登录项状态未知"
        }
    }
}
