import AppKit
import AVKit
import SwiftUI

private struct ClipboardMediaSource {
    let image: NSImage?
    let displaySize: CGSize
    let player: AVPlayer?
}

@MainActor
final class ClipboardMediaPreviewController {
    private let previewController = FullscreenMediaPreviewController()
    private var player: AVPlayer?

    func show(item: ClipboardItem) {
        guard item.kind == .image || item.kind == .video,
              let path = item.kind == .image ? item.imagePath : item.filePath,
              FileManager.default.fileExists(atPath: path)
        else {
            return
        }

        dismiss()

        let frames = PreviewWindowSupport.screenFrames()
        let screenFrame = frames.screen
        let maximumSize = PreviewWindowSupport.maximumContentSize(
            for: screenFrame,
            topChromeHeight: 0
        )
        let source = mediaSource(for: item, path: path, maximumSize: maximumSize)
        let image = source.image
        let displaySize = source.displaySize
        let mediaPlayer = source.player
        let model = FullscreenMediaPreviewModel()
        let hostingView = NSHostingView(
            rootView: ClipboardMediaPreview(
                image: image,
                containerSize: screenFrame.size,
                displaySize: displaySize,
                model: model,
                player: mediaPlayer,
                onDismiss: { [weak self] in
                    self?.dismiss()
                }
            )
        )
        hostingView.sizingOptions = []
        player = mediaPlayer
        previewController.show(
            contentView: hostingView,
            model: model
        )
    }

    private func mediaSource(
        for item: ClipboardItem,
        path: String,
        maximumSize: CGSize
    ) -> ClipboardMediaSource {
        guard item.kind == .image,
              let image = NSImage(contentsOfFile: path)
        else {
            return ClipboardMediaSource(
                image: nil,
                displaySize: FullscreenMediaPreviewSizing.videoDisplaySize(maximumSize: maximumSize),
                player: AVPlayer(url: URL(fileURLWithPath: path))
            )
        }
        return ClipboardMediaSource(
            image: image,
            displaySize: FullscreenMediaPreviewSizing.displaySize(
                for: image.size,
                maximumSize: maximumSize
            ),
            player: nil
        )
    }

    func dismiss() {
        player?.pause()
        player = nil
        previewController.dismiss()
    }
}

struct ClipboardMediaPreview: View {
    let image: NSImage?
    let containerSize: CGSize
    let displaySize: CGSize
    @ObservedObject var model: FullscreenMediaPreviewModel
    let player: AVPlayer?
    let onDismiss: () -> Void

    var body: some View {
        FullscreenMediaPreview(
            containerSize: containerSize,
            mediaDisplaySize: displaySize,
            model: model,
            allowsMediaHitTesting: player != nil,
            onMaskClick: onDismiss
        ) {
            if let image {
                Image(nsImage: image)
                    .interpolation(.high)
                    .resizable()
                    .scaledToFit()
            } else if let player {
                ClipboardAVPlayerView(player: player)
            }
        }
    }
}

private struct ClipboardAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context _: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.videoGravity = AVLayerVideoGravity.resizeAspect
        view.showsFullScreenToggleButton = false
        view.allowsVideoFrameAnalysis = false
        view.allowsMagnification = false
        DispatchQueue.main.async {
            guard view.player === player else { return }
            player.play()
        }
        return view
    }

    func updateNSView(_ view: AVPlayerView, context _: Context) {
        if view.player !== player {
            view.player?.pause()
            view.player = player
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator _: ()) {
        view.player?.pause()
        view.player = nil
    }
}
