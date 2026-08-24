import Foundation

enum JarvisPrivacyPermissionReset {
    static func arguments(bundleIdentifier: String) -> [[String]] {
        [
            ["reset", "ScreenCapture", bundleIdentifier],
            ["reset", "Accessibility", bundleIdentifier]
        ]
    }

    static func isMissingBundleFailure(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("No such bundle identifier")
            || message.contains("OSStatus error -10814")
    }

    static func reset(bundleIdentifier: String) throws {
        for arguments in arguments(bundleIdentifier: bundleIdentifier) {
            let service = arguments.dropFirst().first ?? "未知服务"
            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = arguments
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                throw JarvisUpdateError.privacyPermissionResetFailed(
                    "\(service)：\(error.localizedDescription)"
                )
            }

            guard process.terminationStatus == 0 else {
                let message = String(
                    data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                )?.trimmingCharacters(in: .whitespacesAndNewlines)
                let failureMessage = message?.isEmpty == false
                    ? message ?? ""
                    : "tccutil 返回状态码 \(process.terminationStatus)"
                // A permission service may not have an entry for a fresh
                // installation. That already means there is no stale grant
                // to remove, so keep the update flow moving.
                if Self.isMissingBundleFailure(failureMessage) {
                    continue
                }
                throw JarvisUpdateError.privacyPermissionResetFailed(
                    "\(service)：\(failureMessage)"
                )
            }
        }
    }
}
