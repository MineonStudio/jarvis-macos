import AppKit
import SwiftUI

struct ClipboardItemPreview: View {
    private static let videoThumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 128
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    static func purgeVideoThumbnailCache() {
        videoThumbnailCache.removeAllObjects()
    }

    let item: ClipboardItem
    var maxPixelSize: Int = HistoryGridZoomLevel.regular.thumbnailPixelSize
    @State private var image: NSImage?
    @State private var videoThumbnail: NSImage?

    var body: some View {
        ZStack {
            if item.kind == .image, let image {
                mediaImage(image)
            } else if item.kind == .video,
                      let image = videoThumbnail
            {
                mediaImage(image)
                    .overlay(alignment: .bottomLeading) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.55), in: Circle())
                            .padding(7)
                    }
            } else {
                Image(systemName: item.kind.icon)
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(Color.jarvisAccent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: thumbnailTaskID) {
            let operationID = JarvisLog.operationID()

            switch item.kind {
            case .image:
                guard let path = item.imagePath else {
                    JarvisLog.error(
                        category: .clipboard,
                        event: "preview.read.failed",
                        operationID: operationID,
                        result: "missingReference",
                        fields: ["kind": item.kind.rawValue]
                    )
                    return
                }
                let fileURL = URL(fileURLWithPath: path)
                if image == nil {
                    image = JarvisThumbnailCache.cached(
                        fileURL: fileURL,
                        maxPixelSize: maxPixelSize
                    )
                }
                guard let loadedImage = await JarvisThumbnailCache.loadAsync(
                    fileURL: fileURL,
                    maxPixelSize: maxPixelSize
                ) else {
                    guard !Task.isCancelled else { return }
                    JarvisLog.error(
                        category: .clipboard,
                        event: "preview.read.failed",
                        operationID: operationID,
                        result: "unreadable",
                        fields: [
                            "kind": item.kind.rawValue,
                            "pathExists": String(FileManager.default.fileExists(atPath: path))
                        ]
                    )
                    return
                }
                guard !Task.isCancelled else { return }
                image = loadedImage
            case .video:
                guard let videoPath = item.filePath else {
                    JarvisLog.error(
                        category: .clipboard,
                        event: "preview.read.failed",
                        operationID: operationID,
                        result: "missingReference",
                        fields: ["kind": item.kind.rawValue]
                    )
                    return
                }

                let cacheKey = "\(item.thumbnailPath ?? videoPath)|\(maxPixelSize)" as NSString
                if let cached = Self.videoThumbnailCache.object(forKey: cacheKey) {
                    videoThumbnail = cached
                    JarvisLog.debug(
                        category: .clipboard,
                        event: "preview.read.complete",
                        operationID: operationID,
                        result: "memoryCache",
                        fields: ["kind": item.kind.rawValue]
                    )
                    return
                }

                if let thumbnailPath = item.thumbnailPath,
                   let thumbnail = await JarvisThumbnailCache.loadAsync(
                       fileURL: URL(fileURLWithPath: thumbnailPath),
                       maxPixelSize: maxPixelSize
                   )
                {
                    guard !Task.isCancelled else { return }
                    Self.videoThumbnailCache.setObject(
                        thumbnail,
                        forKey: cacheKey,
                        cost: max(1, Int(thumbnail.size.width * thumbnail.size.height))
                    )
                    videoThumbnail = thumbnail
                    return
                }

                let generated = await ClipboardVideoThumbnailGenerator.makeCGImage(
                    for: URL(fileURLWithPath: videoPath),
                    maxPixelSize: maxPixelSize
                )
                guard !Task.isCancelled else { return }
                guard let generated else {
                    JarvisLog.error(
                        category: .clipboard,
                        event: "preview.read.failed",
                        operationID: operationID,
                        result: "unreadable",
                        fields: [
                            "kind": item.kind.rawValue,
                            "pathExists": String(FileManager.default.fileExists(atPath: videoPath))
                        ]
                    )
                    return
                }
                let thumbnail = NSImage(
                    cgImage: generated,
                    size: NSSize(width: generated.width, height: generated.height)
                )
                Self.videoThumbnailCache.setObject(
                    thumbnail,
                    forKey: cacheKey,
                    cost: max(1, generated.width * generated.height)
                )
                videoThumbnail = thumbnail
            case .file, .text:
                break
            }
        }
    }

    private var thumbnailTaskID: String {
        [
            item.id.uuidString,
            item.imagePath ?? "",
            item.thumbnailPath ?? "",
            item.filePath ?? "",
            String(maxPixelSize)
        ].joined(separator: "|")
    }

    private func mediaImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .interpolation(.medium)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}
