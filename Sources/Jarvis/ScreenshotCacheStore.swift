import Foundation

/// Persists the most recently finalized screenshot so the screenshot skill can
/// restore its working context after Jarvis is relaunched.
final class ScreenshotCacheStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    init(fileURL: URL) {
        self.fileURL = fileURL
        JarvisProtectedStorage.prepareDirectory(fileURL.deletingLastPathComponent())
    }

    init(fileManager: FileManager = .default) {
        let support = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        let directory = support.appendingPathComponent(
            "\(JarvisAppIdentity.dataDirectoryName)/Cache",
            isDirectory: true
        )
        JarvisProtectedStorage.prepareDirectory(directory, fileManager: fileManager)
        fileURL = directory.appendingPathComponent("latest-screenshot.png")
    }

    func load() -> Data? {
        lock.withLock {
            do {
                let data = try Data(contentsOf: fileURL)
                return data.isEmpty ? nil : data
            } catch CocoaError.fileReadNoSuchFile {
                return nil
            } catch {
                JarvisLog.error(
                    category: .storage,
                    event: "screenshot.cache.read.failed",
                    error: error
                )
                return nil
            }
        }
    }

    @discardableResult
    func save(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        return lock.withLock {
            do {
                try JarvisProtectedStorage.write(data, to: fileURL)
                return true
            } catch {
                JarvisLog.error(
                    category: .storage,
                    event: "screenshot.cache.write.failed",
                    error: error
                )
                return false
            }
        }
    }

    @discardableResult
    func clear() -> Bool {
        lock.withLock {
            do {
                try FileManager.default.removeItem(at: fileURL)
                return true
            } catch CocoaError.fileNoSuchFile {
                return true
            } catch {
                JarvisLog.error(
                    category: .storage,
                    event: "screenshot.cache.clear.failed",
                    error: error
                )
                return false
            }
        }
    }
}
