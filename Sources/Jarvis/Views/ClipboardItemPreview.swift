import AppKit
import SwiftUI

struct ClipboardItemPreview: View {
    private static let videoThumbnailCache = NSCache<NSString, NSImage>()

    let item: ClipboardItem
    let displayMode: GridThumbnailDisplayMode
    @State private var videoThumbnail: NSImage?

    var body: some View {
        ZStack {
            if item.kind == .image,
               let path = item.imagePath,
               let image = NSImage(contentsOfFile: path)
            {
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
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) {
            guard item.kind == .video,
                  let videoPath = item.filePath else { return }

            let cacheKey = (item.thumbnailPath ?? videoPath) as NSString
            if let cached = Self.videoThumbnailCache.object(forKey: cacheKey) {
                videoThumbnail = cached
                return
            }

            if let thumbnailPath = item.thumbnailPath,
               let thumbnail = NSImage(contentsOfFile: thumbnailPath)
            {
                Self.videoThumbnailCache.setObject(thumbnail, forKey: cacheKey)
                videoThumbnail = thumbnail
                return
            }

            ClipboardVideoThumbnailGenerator.makeCGImageAsync(for: URL(fileURLWithPath: videoPath)) { image in
                guard let image else { return }
                let thumbnail = NSImage(
                    cgImage: image,
                    size: NSSize(width: image.width, height: image.height)
                )
                Self.videoThumbnailCache.setObject(thumbnail, forKey: cacheKey)
                videoThumbnail = thumbnail
            }
        }
    }

    @ViewBuilder
    private func mediaImage(_ image: NSImage) -> some View {
        switch displayMode {
        case .square:
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(
                    width: HistoryGridMetrics.previewHeight,
                    height: HistoryGridMetrics.previewHeight
                )
                .clipped()
        case .aspectRatio:
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
        }
    }
}
