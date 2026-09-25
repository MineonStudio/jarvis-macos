import Foundation

enum JarvisFreshInstallPermissionCleanup {
    private static let markerKey = "jarvis.installation.permission-reset.fingerprint"
    private static let codeIdentityKey = "jarvis.installation.code-identity.fingerprint"
    static let pendingResetKey = "jarvis.installation.permission-reset.pending"

    static func runIfNeeded() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        guard bundleIdentifier == "com.jarvis.mac" else { return }
        let defaults = UserDefaults.standard
        let hasPendingReset = defaults.bool(forKey: pendingResetKey)
        let currentInstallation = installationFingerprint(for: Bundle.main.bundleURL)
        let previousInstallation = defaults.string(forKey: markerKey)
        let currentCodeIdentity = JarvisLocalSigning.codeIdentityFingerprint(appAt: Bundle.main.bundleURL)
        let previousCodeIdentity = defaults.string(forKey: codeIdentityKey)
        let replacedBundle = previousInstallation != nil && previousInstallation != currentInstallation
        let signingIdentityChanged = previousCodeIdentity != nil
            && currentCodeIdentity != nil
            && currentCodeIdentity != previousCodeIdentity
        let resetForIdentityChange = replacedBundle && signingIdentityChanged
        let resetRequested = hasPendingReset || resetForIdentityChange

        do {
            let didReset = try runIfNeeded(
                bundleURL: Bundle.main.bundleURL,
                bundleIdentifier: bundleIdentifier,
                defaults: defaults,
                force: resetRequested
            ) {
                if resetRequested {
                    try JarvisUpdateService.resetPrivacyPermissions(bundleIdentifier: bundleIdentifier)
                }
            }
            if resetRequested, didReset {
                if hasPendingReset {
                    if let pendingSource = defaults.string(forKey: JarvisInstallSource.pendingSourceKey) {
                        defaults.set(pendingSource, forKey: JarvisInstallSource.defaultsKey)
                        defaults.removeObject(forKey: JarvisInstallSource.pendingSourceKey)
                    }
                }
                defaults.removeObject(forKey: pendingResetKey)
            }
            if let currentCodeIdentity {
                defaults.set(currentCodeIdentity, forKey: codeIdentityKey)
            }
            if didReset, resetRequested {
                JarvisLog.notice(
                    category: .security,
                    event: "privacyPermissions.reset.complete",
                    result: "success",
                    fields: [
                        "reason": hasPendingReset ? "pendingReset" : "codeIdentityChanged",
                        "channel": JarvisInstallSource.current(defaults: defaults)
                    ]
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
        force: Bool = false,
        reset: () throws -> Void
    ) throws -> Bool {
        let fingerprint = installationFingerprint(for: bundleURL)
        guard force || defaults.string(forKey: markerKey) != fingerprint else { return false }

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
