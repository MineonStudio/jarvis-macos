import Darwin
import Foundation

/// Observes concurrent launches without changing the app's launch behavior.
/// The lock is intentionally process-scoped so two copies of the same bundle
/// can be correlated in the structured log by PID and session ID.
final class JarvisInstanceCoordinator: @unchecked Sendable {
    let isPrimaryInstance: Bool

    private let fileDescriptor: Int32

    init() {
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "\(JarvisAppIdentity.bundleIdentifier).instance.lock",
                isDirectory: false
            )
        fileDescriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            isPrimaryInstance = false
            JarvisLog.error(
                category: .lifecycle,
                event: "instance.coordinator.failed",
                fields: [
                    "reason": "lockFileOpen",
                    "errno": String(errno)
                ]
            )
            return
        }

        if flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 {
            isPrimaryInstance = true
            let pid = String(ProcessInfo.processInfo.processIdentifier)
            _ = pid.withCString { pointer in
                ftruncate(fileDescriptor, 0)
                lseek(fileDescriptor, 0, SEEK_SET)
                return Darwin.write(fileDescriptor, pointer, strlen(pointer))
            }
            JarvisLog.info(
                category: .lifecycle,
                event: "instance.coordinator.acquired",
                result: "primary",
                fields: ["lockFile": JarvisLogRedactor.path(lockURL.path)]
            )
        } else {
            isPrimaryInstance = false
            JarvisLog.notice(
                category: .lifecycle,
                event: "instance.coordinator.contended",
                result: "secondary",
                fields: [
                    "lockFile": JarvisLogRedactor.path(lockURL.path),
                    "errno": String(errno)
                ]
            )
        }
    }

    deinit {
        guard fileDescriptor >= 0 else { return }
        if isPrimaryInstance {
            flock(fileDescriptor, LOCK_UN)
        }
        close(fileDescriptor)
    }
}
