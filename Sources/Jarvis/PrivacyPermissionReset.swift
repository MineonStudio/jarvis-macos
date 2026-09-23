import Foundation

enum JarvisPrivacyPermissionResetError: LocalizedError {
    case commandFailed(service: String, message: String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(service, message):
            "重置\(service)权限失败：\(message)"
        }
    }
}

/// Releases are ad-hoc signed (no paid Apple Developer ID / notarization).
/// Each replacement binary gets a new code identity, so Screen Recording and
/// Accessibility grants on the old identity will not apply to the new one.
/// Reset those TCC entries while the current process is still running, then
/// let the replacement app prompt again. Do not reset on ordinary launches.
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
            do {
                // During an app update, a missing TCC entry is expected for
                // fresh installs and simply means there is nothing to clean up.
                try run(arguments: arguments)
            } catch {
                throw JarvisUpdateError.privacyPermissionResetFailed(error.localizedDescription)
            }
        }
    }

    private static func run(arguments: [String]) throws {
        let service = arguments.dropFirst().first ?? "未知服务"
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw JarvisPrivacyPermissionResetError.commandFailed(
                service: service,
                message: error.localizedDescription
            )
        }

        guard process.terminationStatus != 0 else {
            return
        }

        let message = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let failureMessage = message?.isEmpty == false
            ? message ?? ""
            : "tccutil 返回状态码 \(process.terminationStatus)"
        // A permission service may not have an entry for a fresh installation.
        // That already means there is no stale grant to remove.
        if Self.isMissingBundleFailure(failureMessage) {
            return
        }
        throw JarvisPrivacyPermissionResetError.commandFailed(
            service: service,
            message: failureMessage
        )
    }
}
