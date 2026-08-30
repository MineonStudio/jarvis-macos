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

    func show(item: ClipboardItem, app: AppModel) {
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
                app: app,
                model: model,
                player: mediaPlayer,
                onCopy: { [weak app] in
                    app?.copyClipboard(item)
                },
                onClose: { [weak self] in
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
    @ObservedObject var app: AppModel
    @ObservedObject var model: FullscreenMediaPreviewModel
    let player: AVPlayer?
    let onCopy: () -> Void
    let onClose: () -> Void

    var body: some View {
        FullscreenMediaPreview(
            containerSize: containerSize,
            mediaDisplaySize: displaySize,
            model: model,
            allowsMediaHitTesting: player != nil,
            onMaskClick: onClose
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
        .overlay(alignment: .bottom) {
            ClipboardMediaPreviewToolbar(
                onCopy: onCopy,
                onClose: onClose
            )
            .padding(.bottom, 18)
        }
        .overlay(alignment: .top) {
            JarvisToastHost(message: app.toastMessage)
                .padding(.top, 18)
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

struct ClipboardMediaPreviewToolbar: View {
    static let preferredWidth: CGFloat = 180
    static let preferredHeight: CGFloat = 70

    let onCopy: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            actionButton(icon: "doc.on.doc", help: "一键复制", action: onCopy)
            toolbarDivider
            actionButton(icon: "xmark", help: "关闭", action: onClose)
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 6)
        .frame(width: Self.preferredWidth, height: Self.preferredHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .jarvisGlass(cornerRadius: 16)
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 8)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.16))
            .frame(width: 1, height: 30)
            .padding(.horizontal, 8)
    }

    private func actionButton(
        icon: String,
        help: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .medium))
                .frame(width: 34, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.76))
        .foregroundStyle(enabled ? Color.secondary : Color.secondary.opacity(0.35))
        .disabled(!enabled)
        .help(help)
    }
}
