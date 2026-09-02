import AppKit
import AVKit
import SwiftUI

@MainActor
final class ClipboardMediaPreviewController {
    private let previewController = FullscreenMediaPreviewController()
    private var player: AVPlayer?

    func show(item: ClipboardItem) {
        dismiss()

        let frames = PreviewWindowSupport.screenFrames()
        let maximumSize = PreviewWindowSupport.maximumContentSize(
            for: frames.screen,
            topChromeHeight: 0
        )

        switch item.kind {
        case .text:
            guard let text = item.resolvedText else { return }
            previewController.show(
                displaySize: FullscreenMediaPreviewSizing.textDisplaySize(
                    for: text,
                    maximumSize: maximumSize
                ),
                allowsHitTesting: true,
                onDismiss: { [weak self] in
                    self?.dismiss()
                }
            ) {
                FullscreenTextPreviewContent(text: text)
            }
        case .image, .video:
            showMedia(item: item, maximumSize: maximumSize)
        case .file:
            return
        }
    }

    private func showMedia(item: ClipboardItem, maximumSize: CGSize) {
        let path = item.kind == .image ? item.imagePath : item.filePath
        guard let path, FileManager.default.fileExists(atPath: path) else { return }

        if item.kind == .image, let image = NSImage(contentsOfFile: path) {
            previewController.show(
                displaySize: FullscreenMediaPreviewSizing.displaySize(
                    for: image.size,
                    maximumSize: maximumSize
                ),
                onDismiss: { [weak self] in
                    self?.dismiss()
                }
            ) {
                Image(nsImage: image)
                    .interpolation(.high)
                    .resizable()
                    .scaledToFit()
            }
            return
        }

        let mediaPlayer = AVPlayer(url: URL(fileURLWithPath: path))
        player = mediaPlayer
        previewController.show(
            displaySize: FullscreenMediaPreviewSizing.videoDisplaySize(maximumSize: maximumSize),
            allowsHitTesting: true,
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        ) {
            ClipboardAVPlayerView(player: mediaPlayer)
        }
    }

    func dismiss() {
        player?.pause()
        player = nil
        previewController.dismiss()
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
