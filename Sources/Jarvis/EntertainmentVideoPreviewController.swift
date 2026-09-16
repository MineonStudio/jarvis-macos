import AppKit
import AVKit
import SwiftUI

/// Plays a downloaded video in the app instead of handing it to another
/// application. Mirrors `ClipboardMediaPreviewController`, including keeping
/// the player alive outside the popover that asked for it — the download
/// popover closes as soon as it loses focus.
@MainActor
final class EntertainmentVideoPreviewController {
    private let previewController = FullscreenMediaPreviewController()
    private var player: AVPlayer?

    func show(url: URL) {
        dismiss()

        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let frames = PreviewWindowSupport.screenFrames()
        let maximumSize = PreviewWindowSupport.maximumContentSize(
            for: frames.screen,
            topChromeHeight: 0
        )
        let mediaPlayer = AVPlayer(url: url)
        player = mediaPlayer
        previewController.show(
            displaySize: FullscreenMediaPreviewSizing.videoDisplaySize(maximumSize: maximumSize),
            allowsHitTesting: true,
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        ) {
            EntertainmentVideoPlayerView(player: mediaPlayer)
        }
    }

    func dismiss() {
        player?.pause()
        player = nil
        previewController.dismiss()
    }
}

private struct EntertainmentVideoPlayerView: NSViewRepresentable {
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
