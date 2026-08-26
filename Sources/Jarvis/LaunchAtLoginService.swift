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

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
