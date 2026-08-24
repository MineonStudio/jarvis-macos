import AppKit
import AVKit
import SwiftUI

@MainActor
final class ClipboardMediaPreviewModel: ObservableObject {
    @Published var zoom: CGFloat = 1
    @Published var offset: CGSize = .zero

    func setZoom(_ value: CGFloat) {
        zoom = min(max(value, 0.25), 4)
        if zoom <= 1 {
            offset = .zero
        }
    }

    func adjustZoom(by delta: CGFloat) {
        setZoom(zoom + delta)
    }
}

private struct ClipboardMediaSource {
    let image: NSImage?
    let displaySize: CGSize
    let player: AVPlayer?
}

@MainActor
final class ClipboardMediaPreviewController {
    private var dimmingPanel: ClipboardMediaDimmingPanel?
    private var panel: ClipboardMediaPreviewPanel?
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
        let visibleFrame = frames.visible
        let maximumSize = PreviewWindowSupport.maximumContentSize(for: screenFrame)
        let source = mediaSource(for: item, path: path, maximumSize: maximumSize)
        let image = source.image
        let displaySize = source.displaySize
        let mediaPlayer = source.player

        let contentWidth = max(displaySize.width, ClipboardMediaPreviewToolbar.preferredWidth + 22)
        let contentHeight = displaySize.height
        let contentFrame = PreviewWindowSupport.centeredFrame(
            contentSize: CGSize(width: contentWidth, height: contentHeight),
            visibleFrame: visibleFrame
        )

        let previewPanel = ClipboardMediaPreviewPanel(
            contentRect: contentFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        PreviewWindowSupport.configurePreviewPanel(
            previewPanel,
            title: item.createdAt.formatted(date: .abbreviated, time: .shortened)
        )

        let model = ClipboardMediaPreviewModel()
        previewPanel.onWindowClose = { [weak self] in
            self?.dismiss()
        }
        previewPanel.onEscape = { [weak self] in
            self?.dismiss()
        }
        previewPanel.onScrollZoom = { [weak model] delta in
            model?.adjustZoom(by: delta)
        }

        let hostingView = NSHostingView(
            rootView: ClipboardMediaPreview(
                item: item,
                image: image,
                displaySize: displaySize,
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
        hostingView.frame = NSRect(origin: .zero, size: contentFrame.size)
        hostingView.autoresizingMask = [.width, .height]
        previewPanel.contentView = hostingView

        let dimmingPanel = ClipboardMediaDimmingPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        PreviewWindowSupport.configureDimmingPanel(dimmingPanel, screenFrame: screenFrame)

        self.dimmingPanel = dimmingPanel
        panel = previewPanel
        player = mediaPlayer
        dimmingPanel.orderFrontRegardless()
        previewPanel.makeKeyAndOrderFront(nil)
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
                displaySize: Self.videoDisplaySize(maximumSize: maximumSize),
                player: AVPlayer(url: URL(fileURLWithPath: path))
            )
        }
        return ClipboardMediaSource(
            image: image,
            displaySize: Self.displaySize(for: image.size, maximumSize: maximumSize),
            player: nil
        )
    }

    func dismiss() {
        let previewPanel = panel
        let dimmingPanel = dimmingPanel
        player?.pause()
        previewPanel?.onWindowClose = nil
        previewPanel?.onEscape = nil
        self.dimmingPanel = nil
        panel = nil
        player = nil
        previewPanel?.orderOut(nil)
        previewPanel?.close()
        dimmingPanel?.orderOut(nil)
        dimmingPanel?.close()
    }

    private static func displaySize(for mediaSize: CGSize, maximumSize: CGSize) -> CGSize {
        guard mediaSize.width > 0, mediaSize.height > 0 else {
            return CGSize(width: 720, height: 520)
        }
        let maximumScale = min(
            maximumSize.width / mediaSize.width,
            maximumSize.height / mediaSize.height
        )
        let minimumDisplayWidth: CGFloat = 560
        let minimumDisplayHeight: CGFloat = 420
        let requestedScale = max(
            1,
            max(
                minimumDisplayWidth / mediaSize.width,
                minimumDisplayHeight / mediaSize.height
            )
        )
        let fitsAtOriginalSize = mediaSize.width <= maximumSize.width
            && mediaSize.height <= maximumSize.height
        let scale = fitsAtOriginalSize ? min(maximumScale, requestedScale) : maximumScale
        return CGSize(width: mediaSize.width * scale, height: mediaSize.height * scale)
    }

    private static func videoDisplaySize(maximumSize: CGSize) -> CGSize {
        let preferred = CGSize(width: 960, height: 620)
        let scale = min(1, min(maximumSize.width / preferred.width, maximumSize.height / preferred.height))
        return CGSize(width: preferred.width * scale, height: preferred.height * scale)
    }
}

struct ClipboardMediaPreview: View {
    let item: ClipboardItem
    let image: NSImage?
    let displaySize: CGSize
    @ObservedObject var model: ClipboardMediaPreviewModel
    let player: AVPlayer?
    let onCopy: () -> Void
    let onClose: () -> Void
    @State private var gestureZoomStart: CGFloat?
    @State private var gestureOffsetStart: CGSize?
    @State private var toolbarOffset: CGSize = .zero
    @State private var toolbarDragStartOffset: CGSize?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .interpolation(.high)
                        .resizable()
                        .scaledToFit()
                        .frame(width: displaySize.width, height: displaySize.height)
                        .scaleEffect(model.zoom)
                        .offset(model.offset)
                        .contentShape(Rectangle())
                        .gesture(dragGesture)
                        .simultaneousGesture(magnificationGesture)
                        .onTapGesture(count: 2) {
                            model.setZoom(model.zoom > 1 ? 1 : 2)
                        }
                } else if let player {
                    ClipboardAVPlayerView(player: player, zoom: model.zoom)
                        .frame(width: displaySize.width, height: displaySize.height)
                        // AVPlayerView's magnification scales only the video
                        // for zoom-in. Keep the legacy zoom-out range while
                        // avoiding a second scale transform for playback UI.
                        .scaleEffect(model.zoom < 1 ? model.zoom : 1)
                        .offset(model.offset)
                        .contentShape(Rectangle())
                        .gesture(dragGesture)
                        .simultaneousGesture(magnificationGesture)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .clipped()
            .overlay(alignment: .bottom) {
                ClipboardMediaPreviewToolbar(
                    onCopy: onCopy,
                    onClose: onClose,
                    model: model
                )
                .padding(.bottom, 18)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .highPriorityGesture(toolbarDragGesture(in: geometry.size))
                .offset(toolbarOffset)
            }
            .coordinateSpace(name: "clipboardMediaPreview")
        }
        .background(Color.black)
        .onExitCommand(perform: onClose)
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if gestureZoomStart == nil {
                    gestureZoomStart = model.zoom
                }
                model.setZoom((gestureZoomStart ?? model.zoom) * value)
            }
            .onEnded { _ in
                gestureZoomStart = nil
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard model.zoom > 1 else { return }
                if gestureOffsetStart == nil {
                    gestureOffsetStart = model.offset
                }
                model.offset = CGSize(
                    width: (gestureOffsetStart ?? model.offset).width + value.translation.width,
                    height: (gestureOffsetStart ?? model.offset).height + value.translation.height
                )
            }
            .onEnded { _ in
                gestureOffsetStart = nil
            }
    }

    private func toolbarDragGesture(in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("clipboardMediaPreview"))
            .onChanged { value in
                if toolbarDragStartOffset == nil {
                    toolbarDragStartOffset = toolbarOffset
                }
                let start = toolbarDragStartOffset ?? .zero
                toolbarOffset = CGSize(
                    width: min(max(start.width + value.translation.width, -containerSize.width / 2), containerSize.width / 2),
                    height: min(max(start.height + value.translation.height, -(containerSize.height - 18)), 18)
                )
            }
            .onEnded { _ in
                toolbarDragStartOffset = nil
            }
    }
}

private struct ClipboardAVPlayerView: NSViewRepresentable {
    let player: AVPlayer
    let zoom: CGFloat

    func makeNSView(context _: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.videoGravity = AVLayerVideoGravity.resizeAspect
        view.showsFullScreenToggleButton = false
        view.allowsVideoFrameAnalysis = false
        view.allowsMagnification = true
        view.magnification = max(1, zoom)
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
        view.magnification = max(1, zoom)
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator _: ()) {
        view.player?.pause()
        view.player = nil
    }
}

struct ClipboardMediaPreviewToolbar: View {
    static let preferredWidth: CGFloat = 356
    static let preferredHeight: CGFloat = 70

    let onCopy: () -> Void
    let onClose: () -> Void
    @ObservedObject var model: ClipboardMediaPreviewModel

    var body: some View {
        HStack(spacing: 0) {
            actionButton(icon: "minus.magnifyingglass", help: "缩小", enabled: model.zoom > 0.25) {
                model.adjustZoom(by: -0.25)
            }
            Button {
                model.setZoom(1)
            } label: {
                Text("\(Int(model.zoom * 100))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .frame(minWidth: 42, minHeight: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("重置缩放")
            actionButton(icon: "plus.magnifyingglass", help: "放大", enabled: model.zoom < 4) {
                model.adjustZoom(by: 0.25)
            }
            toolbarDivider
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
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.secondary : Color.secondary.opacity(0.35))
        .disabled(!enabled)
        .help(help)
    }
}

private final class ClipboardMediaDimmingPanel: NSPanel {}

private final class ClipboardMediaPreviewPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onScrollZoom: ((CGFloat) -> Void)?
    var onWindowClose: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func performClose(_: Any?) {
        onWindowClose?()
    }

    override func close() {
        let closeHandler = onWindowClose
        onWindowClose = nil
        closeHandler?()
        super.close()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            onEscape?()
            return
        }
        if event.type == .scrollWheel, abs(event.scrollingDeltaY) > 0.01 {
            onScrollZoom?(event.scrollingDeltaY > 0 ? 0.1 : -0.1)
            return
        }
        super.sendEvent(event)
    }
}
