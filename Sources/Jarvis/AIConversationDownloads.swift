import AppKit
import Foundation
import WebKit

enum AIConversationDownloadState: Equatable {
    case queued
    case downloading
    case completed
    case failed
    case cancelled

    var title: String {
        switch self {
        case .queued: "等待下载"
        case .downloading: "下载中"
        case .completed: "已完成"
        case .failed: "下载失败"
        case .cancelled: "已取消"
        }
    }

    var icon: String {
        switch self {
        case .queued: "clock"
        case .downloading: "arrow.down.circle"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .cancelled: "xmark.circle"
        }
    }

    var isActive: Bool {
        switch self {
        case .queued, .downloading: true
        case .completed, .failed, .cancelled: false
        }
    }
}

struct AIConversationDownloadItem: Identifiable, Equatable {
    let id: UUID
    let platformTitle: String
    let sourceURL: URL?
    var filename: String
    var state: AIConversationDownloadState
    var progress: Double?
    var destinationURL: URL?
    var errorMessage: String?

    var canOpenFile: Bool {
        guard state == .completed, let destinationURL else { return false }
        return FileManager.default.fileExists(atPath: destinationURL.path)
    }
}

enum AIConversationDownloadFileName {
    static func destination(
        in directory: URL,
        suggestedFilename: String,
        fileManager: FileManager = .default
    ) -> URL {
        let filename = sanitizedFilename(suggestedFilename)
        var candidate = directory.appendingPathComponent(filename, isDirectory: false)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let nsFilename = filename as NSString
        let basename = nsFilename.deletingPathExtension
        let pathExtension = nsFilename.pathExtension
        var suffix = 2
        repeat {
            let numberedName = pathExtension.isEmpty
                ? "\(basename) (\(suffix))"
                : "\(basename) (\(suffix)).\(pathExtension)"
            candidate = directory.appendingPathComponent(numberedName, isDirectory: false)
            suffix += 1
        } while fileManager.fileExists(atPath: candidate.path)

        return candidate
    }

    private static func sanitizedFilename(_ suggestedFilename: String) -> String {
        let lastPathComponent = URL(fileURLWithPath: suggestedFilename).lastPathComponent
        let trimmed = lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "." || trimmed == ".." ? "下载文件" : trimmed
    }
}

@MainActor
final class AIConversationDownloadManager: NSObject, ObservableObject {
    @Published private(set) var items: [AIConversationDownloadItem] = []

    private var downloads: [UUID: WKDownload] = [:]
    private var downloadIDs: [ObjectIdentifier: UUID] = [:]
    private var pendingIDs: [UUID] = []
    private var progressObservations: [UUID: NSKeyValueObservation] = [:]

    var activeDownloadCount: Int {
        items.count(where: { $0.state.isActive })
    }

    var hasDownloads: Bool {
        !items.isEmpty
    }

    var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    @discardableResult
    func enqueue(platformTitle: String, sourceURL: URL?) -> UUID {
        let item = AIConversationDownloadItem(
            id: UUID(),
            platformTitle: platformTitle,
            sourceURL: sourceURL,
            filename: sourceURL?.lastPathComponent.isEmpty == false
                ? sourceURL?.lastPathComponent ?? "下载文件"
                : "下载文件",
            state: .queued,
            progress: nil,
            destinationURL: nil,
            errorMessage: nil
        )
        items.insert(item, at: 0)
        pendingIDs.append(item.id)
        return item.id
    }

    func attach(
        _ download: WKDownload,
        platformTitle: String,
        sourceURL: URL?
    ) {
        let id = matchingPendingID(for: platformTitle, sourceURL: sourceURL) ?? enqueue(
            platformTitle: platformTitle,
            sourceURL: sourceURL
        )

        downloads[id] = download
        downloadIDs[ObjectIdentifier(download)] = id
        download.delegate = self
        updateItem(id) {
            $0.state = .downloading
            $0.progress = download.progress.fractionCompleted
            if let originalURL = download.originalRequest?.url {
                $0.filename = originalURL.lastPathComponent.isEmpty
                    ? $0.filename
                    : originalURL.lastPathComponent
            }
        }

        progressObservations[id] = download.progress.observe(
            \.fractionCompleted,
            options: [.initial, .new]
        ) { [weak self, weak download] progress, _ in
            Task { @MainActor [weak self, weak download] in
                guard let self, let download else { return }
                self.updateItem(ObjectIdentifier(download), progress: progress.fractionCompleted)
            }
        }
    }

    func cancel(_ item: AIConversationDownloadItem) {
        guard item.state.isActive else { return }
        pendingIDs.removeAll(where: { $0 == item.id })

        guard let download = downloads[item.id] else {
            updateItem(item.id) {
                $0.state = .cancelled
                $0.errorMessage = nil
            }
            return
        }

        updateItem(item.id) {
            $0.state = .cancelled
            $0.errorMessage = nil
        }
        download.cancel { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.removeDownloadReferences(for: download)
            }
        }
    }

    func open(_ item: AIConversationDownloadItem) {
        guard item.canOpenFile, let destinationURL = item.destinationURL else { return }
        NSWorkspace.shared.open(destinationURL)
    }

    func revealInFinder(_ item: AIConversationDownloadItem) {
        guard let destinationURL = item.destinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    }

    func openDownloadsFolder() {
        NSWorkspace.shared.open(downloadsDirectory)
    }

    func clearFinished() {
        let activeIDs = Set(items.filter(\.state.isActive).map(\.id))
        items.removeAll { !activeIDs.contains($0.id) }
    }

    private func matchingPendingID(
        for platformTitle: String,
        sourceURL: URL?
    ) -> UUID? {
        let matchingID = pendingIDs.first { pendingID in
            guard let item = items.first(where: { $0.id == pendingID }) else { return false }
            return item.platformTitle == platformTitle && (sourceURL == nil || item.sourceURL == sourceURL)
        }
        guard let matchingID else { return nil }
        pendingIDs.removeAll(where: { $0 == matchingID })
        return matchingID
    }

    private func updateItem(_ id: UUID, _ update: (inout AIConversationDownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        update(&items[index])
    }

    private func updateItem(_ downloadID: ObjectIdentifier, progress: Double) {
        guard let id = downloadIDs[downloadID] else { return }
        updateItem(id) { item in
            item.progress = min(max(progress, 0), 1)
        }
    }

    private func removeDownloadReferences(for download: WKDownload) {
        let objectID = ObjectIdentifier(download)
        guard let id = downloadIDs.removeValue(forKey: objectID) else { return }
        downloads.removeValue(forKey: id)
        progressObservations.removeValue(forKey: id)?.invalidate()
    }

    private func updateCompletion(for download: WKDownload, state: AIConversationDownloadState, error: String?) {
        guard let id = downloadIDs[ObjectIdentifier(download)] else { return }
        updateItem(id) {
            $0.state = state
            $0.progress = state == .completed ? 1 : $0.progress
            $0.errorMessage = error
        }
        removeDownloadReferences(for: download)
    }
}

extension AIConversationDownloadManager: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing _: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        guard let id = downloadIDs[ObjectIdentifier(download)] else {
            completionHandler(nil)
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.directoryURL = downloadsDirectory
        panel.nameFieldStringValue = AIConversationDownloadFileName.destination(
            in: downloadsDirectory,
            suggestedFilename: suggestedFilename
        ).lastPathComponent
        panel.begin { [weak self] response in
            guard let self else {
                completionHandler(nil)
                return
            }
            guard response == .OK, let destination = panel.url else {
                self.updateCompletion(for: download, state: .cancelled, error: nil)
                completionHandler(nil)
                return
            }
            self.updateItem(id) {
                $0.filename = destination.lastPathComponent
                $0.destinationURL = destination
            }
            completionHandler(destination)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        updateCompletion(for: download, state: .completed, error: nil)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData _: Data?) {
        let isCancellation = (error as NSError).code == NSURLErrorCancelled
        updateCompletion(
            for: download,
            state: isCancellation ? .cancelled : .failed,
            error: isCancellation ? nil : error.localizedDescription
        )
    }
}
