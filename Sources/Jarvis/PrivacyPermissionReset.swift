import Foundation

enum JarvisPrivacyPermissionReset {
    static func arguments(bundleIdentifier: String) -> [[String]] {
        [
            ["reset", "ScreenCapture", bundleIdentifier],
            ["reset", "Accessibility", bundleIdentifier]
        ]
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
                throw JarvisUpdateError.privacyPermissionResetFailed(
                    "\(service)：\(failureMessage)"
                )
            }
        }
    }
}
