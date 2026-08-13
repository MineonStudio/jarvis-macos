import AVKit
import AppKit
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

@MainActor
final class ClipboardMediaPreviewController {
    private var dimmingPanel: ClipboardMediaDimmingPanel?
    private var panel: ClipboardMediaPreviewPanel?
    private var player: AVPlayer?

    func show(item: ClipboardItem, app: AppModel) {
        guard item.kind == .image || item.kind == .video,
              let path = item.kind == .image ? item.imagePath : item.filePath,
              FileManager.default.fileExists(atPath: path) else {
            return
        }

        dismiss()

        let screenFrame = NSScreen.main?.frame ?? CGRect(
            origin: .zero,
            size: CGSize(width: 1200, height: 800)
        )
        let visibleFrame = NSScreen.main?.visibleFrame ?? screenFrame
        let titlebarHeight: CGFloat = 28
        let maximumSize = CGSize(
            width: screenFrame.width - 80,
            height: screenFrame.height - 80 - titlebarHeight
        )
        let displaySize: CGSize
        let image: NSImage?
        let mediaPlayer: AVPlayer?

        if item.kind == .image,
           let loadedImage = NSImage(contentsOfFile: path) {
            image = loadedImage
            displaySize = Self.displaySize(for: loadedImage.size, maximumSize: maximumSize)
            mediaPlayer = nil
        } else {
            image = nil
            displaySize = Self.videoDisplaySize(maximumSize: maximumSize)
            mediaPlayer = AVPlayer(url: URL(fileURLWithPath: path))
        }

        let contentWidth = max(displaySize.width, ClipboardMediaPreviewToolbar.preferredWidth + 22)
        let contentHeight = displaySize.height
        let contentFrame = CGRect(
            x: visibleFrame.midX - contentWidth / 2,
            y: visibleFrame.midY - (contentHeight + titlebarHeight) / 2,
            width: contentWidth,
            height: contentHeight
        )

        let previewPanel = ClipboardMediaPreviewPanel(
            contentRect: contentFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        previewPanel.level = .screenSaver
        previewPanel.title = item.createdAt.formatted(date: .abbreviated, time: .shortened)
        previewPanel.titleVisibility = .visible
        previewPanel.titlebarAppearsTransparent = false
        previewPanel.titlebarSeparatorStyle = .none
        previewPanel.backgroundColor = .black
        previewPanel.isOpaque = true
        previewPanel.hasShadow = true
        previewPanel.hidesOnDeactivate = false
        previewPanel.isReleasedWhenClosed = false
        previewPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        previewPanel.standardWindowButton(.closeButton)?.isHidden = false
        previewPanel.standardWindowButton(.miniaturizeButton)?.isHidden = false
        previewPanel.standardWindowButton(.zoomButton)?.isHidden = false
        previewPanel.standardWindowButton(.zoomButton)?.isEnabled = true

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
        dimmingPanel.level = .screenSaver
        dimmingPanel.backgroundColor = NSColor.black.withAlphaComponent(0.58)
        dimmingPanel.isOpaque = false
        dimmingPanel.hasShadow = false
        dimmingPanel.ignoresMouseEvents = true
        dimmingPanel.hidesOnDeactivate = false
        dimmingPanel.isReleasedWhenClosed = false
        dimmingPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        self.dimmingPanel = dimmingPanel
        self.panel = previewPanel
        self.player = mediaPlayer
        dimmingPanel.orderFrontRegardless()
        previewPanel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        player?.pause()
        dimmingPanel?.orderOut(nil)
        panel?.orderOut(nil)
        dimmingPanel = nil
        panel = nil
        player = nil
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
                    ClipboardAVPlayerView(player: player)
                        .frame(width: displaySize.width, height: displaySize.height)
                        .scaleEffect(model.zoom)
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

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.videoGravity = AVLayerVideoGravity.resizeAspect
        view.showsFullScreenToggleButton = false
        view.allowsVideoFrameAnalysis = false
        DispatchQueue.main.async {
            guard view.player === player else { return }
            player.play()
        }
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player?.pause()
            view.player = player
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}

struct ClipboardMediaPreviewToolbar: View {
    static let preferredWidth: CGFloat = 300
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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performClose(_ sender: Any?) {
        onWindowClose?()
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
