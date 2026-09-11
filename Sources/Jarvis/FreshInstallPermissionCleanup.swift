import Foundation

enum JarvisFreshInstallPermissionCleanup {
    private static let markerKey = "jarvis.installation.permission-reset.fingerprint"

    static func runIfNeeded() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        do {
            let didReset = try runIfNeeded(
                bundleURL: Bundle.main.bundleURL,
                bundleIdentifier: bundleIdentifier,
                defaults: .standard
            ) {
                try JarvisUpdateService.resetPrivacyPermissions(bundleIdentifier: bundleIdentifier)
            }
            if didReset {
                JarvisLog.notice(
                    category: .security,
                    event: "privacyPermissions.reset.complete",
                    result: "success",
                    fields: ["reason": "installationChanged"]
                )
            }
        } catch {
            // Do not prevent a newly installed app from launching. The marker
            // is only written after both resets succeed, so the next launch
            // will retry if tccutil was temporarily unavailable.
            JarvisLog.error(
                category: .security,
                event: "privacyPermissions.reset.failed",
                error: error
            )
        }
    }

    static func runIfNeeded(
        bundleURL: URL,
        bundleIdentifier _: String,
        defaults: UserDefaults,
        reset: () throws -> Void
    ) throws -> Bool {
        let fingerprint = installationFingerprint(for: bundleURL)
        guard defaults.string(forKey: markerKey) != fingerprint else { return false }

        try reset()
        defaults.set(fingerprint, forKey: markerKey)
        return true
    }

    static func installationFingerprint(for bundleURL: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: bundleURL.path)
        let fileNumber = (attributes?[.systemFileNumber] as? NSNumber)?.stringValue ?? "unknown"
        let modificationDate = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(bundleURL.standardizedFileURL.path)|\(fileNumber)|\(modificationDate)"
    }
}
