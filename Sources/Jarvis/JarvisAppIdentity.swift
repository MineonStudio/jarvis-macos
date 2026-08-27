import Foundation

enum JarvisAppIdentity {
    static let mainWindowSceneID = "main"
    static let productionBundleIdentifier = "com.jarvis.mac"
    static let developmentBundleIdentifier = "com.jarvis.mac.dev"

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier == developmentBundleIdentifier
            ? developmentBundleIdentifier
            : productionBundleIdentifier
    }

    static var isDevelopment: Bool {
        bundleIdentifier == developmentBundleIdentifier
    }

    static var displayName: String {
        isDevelopment ? "贾维斯开发版" : "贾维斯"
    }

    static var dataDirectoryName: String {
        isDevelopment ? "Jarvis-Dev" : "Jarvis"
    }
}
