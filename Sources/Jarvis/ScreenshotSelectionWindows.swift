import AppKit
import Combine

// MARK: - Selection windows

final class SelectionOverlayWindow: NSPanel {
    var onDoubleClick: (() -> Void)?
    var onMiddleClick: (() -> Void)?
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            onEscape?()
            return
        }
        if event.type == .leftMouseDown,
           event.clickCount == 2,
           let onDoubleClick
        {
            onDoubleClick()
            return
        }
        if event.type == .otherMouseDown,
           event.buttonNumber == 2,
           let onMiddleClick
        {
            onMiddleClick()
            return
        }
        super.sendEvent(event)
    }
}

struct WindowSelectionCandidate {
    let localRect: CGRect
    let ownerName: String
    let title: String
    let windowID: CGWindowID
}

enum WindowSelectionDetector {
    private static let dockOwnerNames: Set<String> = ["dock", "程序坞"]

    static func candidates(
        for screenFrame: CGRect
    ) -> [WindowSelectionCandidate] {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? screenFrame.maxY
        let screenBounds = CGRect(origin: .zero, size: screenFrame.size)
        let dockGlobalRect = dockRegion(for: screenFrame)
        let context = WindowSelectionContext(
            screenFrame: screenFrame,
            screenBounds: screenBounds,
            desktopTop: desktopTop,
            dockGlobalRect: dockGlobalRect
        )
        var candidates: [WindowSelectionCandidate] = []
        var seenRects = Set<String>()
        var dockCandidate: WindowSelectionCandidate?

        // CGWindowListCopyWindowInfo is front-to-back. Keeping that order means
        // the first candidate containing the pointer is the topmost window.
        for info in windowInfoList {
            if let result = candidate(
                from: info,
                context: context,
                seenRects: &seenRects
            ) {
                if result.isDock {
                    dockCandidate = result.candidate
                } else {
                    candidates.append(result.candidate)
                }
            }
        }

        // Dock icons are drawn by the Dock process and are not individual
        // CGWindow entries. Add approximate icon slots using the user's actual
        // Dock orientation, tile size and persistent app count. The Dock bar
        // itself remains as a fallback for gaps between icon slots.
        if let dockCandidate {
            let iconCandidates = dockIconCandidates(in: dockCandidate.localRect)
            candidates.append(contentsOf: iconCandidates)
            candidates.append(dockCandidate)
        } else if let dockGlobalRect {
            let localDockRect = localRect(
                for: Self.quartzRect(fromAppKitRect: dockGlobalRect, desktopTop: desktopTop),
                screenFrame: screenFrame,
                desktopTop: desktopTop,
                screenBounds: screenBounds
            )
            if localDockRect.width >= 80, localDockRect.height >= 20 {
                candidates.append(contentsOf: dockIconCandidates(in: localDockRect))
                candidates.append(
                    WindowSelectionCandidate(
                        localRect: localDockRect,
                        ownerName: "Dock",
                        title: "Dock",
                        windowID: .max
                    )
                )
            }
        }

        return candidates
    }

    private struct WindowSelectionContext {
        let screenFrame: CGRect
        let screenBounds: CGRect
        let desktopTop: CGFloat
        let dockGlobalRect: CGRect?
    }

    private static func candidate(
        from info: [String: Any],
        context: WindowSelectionContext,
        seenRects: inout Set<String>
    ) -> (candidate: WindowSelectionCandidate, isDock: Bool)? {
        let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        guard layer >= 0, layer < 1000 else { return nil }

        let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        guard alpha > 0.01 else { return nil }

        let ownerName = (info[kCGWindowOwnerName as String] as? String) ?? ""
        let normalizedOwnerName = ownerName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedOwnerName.isEmpty else { return nil }

        let title = (info[kCGWindowName as String] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = title?.lowercased() ?? ""
        let isDock = dockOwnerNames.contains(normalizedOwnerName)
        let isMenubar = normalizedTitle == "menubar"

        guard let boundsValue = info[kCGWindowBounds as String] as? NSDictionary,
              let quartzBounds = CGRect(dictionaryRepresentation: boundsValue)
        else {
            return nil
        }

        let convertedBounds: CGRect? = if isDock {
            context.dockGlobalRect.map {
                Self.quartzRect(fromAppKitRect: $0, desktopTop: context.desktopTop)
            }
        } else {
            quartzBounds
        }
        guard let convertedBounds else { return nil }
        let localRect = localRect(
            for: convertedBounds,
            screenFrame: context.screenFrame,
            desktopTop: context.desktopTop,
            screenBounds: context.screenBounds
        )
        let isFullScreenSystemSurface = layer > 0
            && !isDock
            && localRect.width >= context.screenBounds.width * 0.9
            && localRect.height >= context.screenBounds.height * 0.9
        guard !isFullScreenSystemSurface else { return nil }

        let minimumWidth: CGFloat = (layer > 0 || isMenubar) ? 18 : 80
        let minimumHeight: CGFloat = (layer > 0 || isMenubar) ? 10 : 60
        guard localRect.width >= minimumWidth, localRect.height >= minimumHeight else {
            return nil
        }

        let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
        let rectKey = "\(windowID):\(Int(localRect.minX.rounded())):\(Int(localRect.minY.rounded())):\(Int(localRect.width.rounded())):\(Int(localRect.height.rounded()))"
        guard seenRects.insert(rectKey).inserted else { return nil }

        return (
            WindowSelectionCandidate(
                localRect: localRect,
                ownerName: ownerName,
                title: title.flatMap { $0.isEmpty ? nil : $0 } ?? ownerName,
                windowID: windowID
            ),
            isDock
        )
    }

    static func quartzRect(fromAppKitRect rect: CGRect, desktopTop: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: desktopTop - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func localRect(
        for globalRect: CGRect,
        screenFrame: CGRect,
        desktopTop: CGFloat,
        screenBounds: CGRect
    ) -> CGRect {
        CGRect(
            x: globalRect.minX - screenFrame.minX,
            y: desktopTop - globalRect.maxY - screenFrame.minY,
            width: globalRect.width,
            height: globalRect.height
        ).intersection(screenBounds)
    }

    private static func dockRegion(for screenFrame: CGRect) -> CGRect? {
        guard let screen = NSScreen.screens.first(where: { $0.frame == screenFrame }) else {
            return nil
        }

        let visibleFrame = screen.visibleFrame
        let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.dock") ?? [:]
        let configuredOrientation = domain["orientation"] as? String
        let orientation = configuredOrientation ?? inferredDockOrientation(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame
        )

        switch orientation {
        case "left":
            let width = visibleFrame.minX - screenFrame.minX
            guard width >= 20 else { return nil }
            return CGRect(x: screenFrame.minX, y: screenFrame.minY, width: width, height: screenFrame.height)
        case "right":
            let width = screenFrame.maxX - visibleFrame.maxX
            guard width >= 20 else { return nil }
            return CGRect(x: visibleFrame.maxX, y: screenFrame.minY, width: width, height: screenFrame.height)
        default:
            let height = visibleFrame.minY - screenFrame.minY
            guard height >= 20 else { return nil }
            return CGRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: height)
        }
    }

    private static func inferredDockOrientation(
        screenFrame: CGRect,
        visibleFrame: CGRect
    ) -> String {
        let bottom = visibleFrame.minY - screenFrame.minY
        let left = visibleFrame.minX - screenFrame.minX
        let right = screenFrame.maxX - visibleFrame.maxX
        if left > bottom, left >= right {
            return "left"
        }
        if right > bottom, right > left {
            return "right"
        }
        return "bottom"
    }

    private static func dockIconCandidates(
        in dockRect: CGRect
    ) -> [WindowSelectionCandidate] {
        let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.dock") ?? [:]
        let persistentApps = domain["persistent-apps"] as? [Any] ?? []
        let persistentOthers = domain["persistent-others"] as? [Any] ?? []
        let iconCount = persistentApps.count + persistentOthers.count
        guard iconCount > 0 else { return [] }

        let tileSize = max(
            32,
            (domain["tilesize"] as? NSNumber)?.doubleValue ?? 64
        )
        let slotSize = tileSize + 7
        // macOS defaults to a bottom Dock when no preference exists. The
        // screen-frame fallback above is global coordinates, while dockRect is
        // local overlay coordinates, so do not infer orientation from them.
        let orientation = (domain["orientation"] as? String) ?? "bottom"
        var result: [WindowSelectionCandidate] = []
        result.reserveCapacity(iconCount)
        var syntheticWindowID = CGWindowID.max - 1

        if orientation == "left" || orientation == "right" {
            let totalHeight = CGFloat(iconCount) * slotSize
            let startY = dockRect.midY - totalHeight / 2
            let x = orientation == "left"
                ? dockRect.maxX - tileSize - 8
                : dockRect.minX + 8
            for index in 0 ..< iconCount {
                result.append(
                    WindowSelectionCandidate(
                        localRect: CGRect(
                            x: x,
                            y: startY + CGFloat(index) * slotSize,
                            width: tileSize + 16,
                            height: slotSize
                        ).intersection(dockRect),
                        ownerName: "Dock",
                        title: "Dock 图标",
                        windowID: syntheticWindowID
                    )
                )
                syntheticWindowID = syntheticWindowID > 0 ? syntheticWindowID - 1 : .max - 1
            }
        } else {
            let totalWidth = CGFloat(iconCount) * slotSize
            let startX = dockRect.midX - totalWidth / 2
            let y = dockRect.minY + 8
            for index in 0 ..< iconCount {
                result.append(
                    WindowSelectionCandidate(
                        localRect: CGRect(
                            x: startX + CGFloat(index) * slotSize,
                            y: y,
                            width: slotSize,
                            height: tileSize + 16
                        ).intersection(dockRect),
                        ownerName: "Dock",
                        title: "Dock 图标",
                        windowID: syntheticWindowID
                    )
                )
                syntheticWindowID = syntheticWindowID > 0 ? syntheticWindowID - 1 : .max - 1
            }
        }

        return result.filter { $0.localRect.width >= 16 && $0.localRect.height >= 16 }
    }
}

final class PinnedScreenshotWindow: NSPanel, NSWindowDelegate {
    var onEscape: (() -> Void)?
    var onDidResignKey: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            onEscape?()
            return
        }
        super.sendEvent(event)
    }

    func windowDidResignKey(_: Notification) {
        onDidResignKey?()
    }
}

final class PinnedScreenshotContainerView: NSView {
    private let imageSize: CGSize
    private let contentInset: CGFloat
    private let editor: ScreenshotEditorModel
    private let onActivate: (() -> Void)?
    var isSelected = false {
        didSet {
            needsDisplay = true
        }
    }

    var showsShadow = true {
        didSet { needsDisplay = true }
    }

    private var initialWindowOrigin: NSPoint?
    private var initialMouseLocation: NSPoint?

    init(
        frame frameRect: NSRect,
        imageSize: CGSize,
        contentInset: CGFloat,
        editor: ScreenshotEditorModel,
        onActivate: (() -> Void)?
    ) {
        self.imageSize = imageSize
        self.contentInset = contentInset
        self.editor = editor
        self.onActivate = onActivate
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        updateShadowAppearance()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A pin can float above an inactive app. Accept the first click so the
    /// entire pin activates immediately instead of requiring a second click.
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // With no annotation tool selected, the whole image is a draggable
        // pin. Once a tool is active, let the hosted SwiftUI canvas receive
        // the gesture so drawing and moving cannot conflict.
        if bounds.contains(point), editor.selectedTool == nil {
            return self
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
        guard editor.selectedTool == nil, let window else {
            super.mouseDown(with: event)
            return
        }
        initialWindowOrigin = window.frame.origin
        initialMouseLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard editor.selectedTool == nil,
              let window,
              let initialWindowOrigin,
              let initialMouseLocation
        else {
            super.mouseDragged(with: event)
            return
        }

        let currentMouseLocation = NSEvent.mouseLocation
        window.setFrameOrigin(
            NSPoint(
                x: initialWindowOrigin.x + currentMouseLocation.x - initialMouseLocation.x,
                y: initialWindowOrigin.y + currentMouseLocation.y - initialMouseLocation.y
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        initialWindowOrigin = nil
        initialMouseLocation = nil
        if editor.selectedTool != nil {
            super.mouseUp(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let imageRect = CGRect(
            x: contentInset,
            y: contentInset,
            width: imageSize.width,
            height: imageSize.height
        ).insetBy(dx: 1, dy: 1)
        let cornerRadius: CGFloat = 8
        let path = NSBezierPath(
            roundedRect: imageRect,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )

        NSColor.white.setFill()
        if showsShadow {
            // Use an even, zero-offset halo rather than a heavy downward drop
            // shadow. The user can toggle this appearance from the context menu.
            context.saveGState()
            context.setShadow(
                offset: .zero,
                blur: 34,
                color: NSColor.systemBlue.withAlphaComponent(0.34).cgColor
            )
            path.fill()
            context.restoreGState()
        } else {
            path.fill()
        }

        if isSelected, showsShadow {
            NSColor.systemBlue.withAlphaComponent(0.92).setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }

    private func updateShadowAppearance() {
        guard let layer else { return }
        let imageRect = CGRect(
            x: contentInset,
            y: contentInset,
            width: imageSize.width,
            height: imageSize.height
        ).insetBy(dx: 1, dy: 1)
        layer.shadowPath = CGPath(
            roundedRect: imageRect,
            cornerWidth: 8,
            cornerHeight: 8,
            transform: nil
        )
        // The halo is rendered once in draw(_:). Disable the layer shadow so
        // AppKit does not stack a second dark shadow on top of it.
        layer.shadowColor = NSColor.clear.cgColor
        layer.shadowOpacity = 0
        layer.shadowRadius = 0
        layer.shadowOffset = .zero
        layer.masksToBounds = false
    }
}

@MainActor
final class PinnedScreenshotItem {
    let id = UUID()
    let editor: ScreenshotEditorModel
    let window: PinnedScreenshotWindow
    let imageSize: CGSize
    // Keep enough transparent room for the soft halo to fade out naturally.
    // The imageFrame calculation still points to the original screenshot
    // bounds, so this does not change the pin's visible position or size.
    let contentInset: CGFloat = 40
    var data: Data
    var containerView: PinnedScreenshotContainerView?
    var toolbarWindow: NSPanel?
    var toolbarLayout: ScreenshotToolbarLayoutModel?
    var editorObservation: AnyCancellable?
    var onAction: ((ScreenshotAction) -> Void)?
    var showsToolbar = false
    var showsShadow = true

    var imageFrame: CGRect {
        CGRect(
            x: window.frame.minX + contentInset,
            y: window.frame.minY + contentInset,
            width: imageSize.width,
            height: imageSize.height
        )
    }

    init(data: Data, image: NSImage, frame: CGRect) {
        self.data = data
        imageSize = image.size
        editor = ScreenshotEditorModel(
            image: image,
            data: data,
            outputData: data,
            canvasSize: image.size,
            outputRect: CGRect(origin: .zero, size: image.size)
        )
        window = PinnedScreenshotWindow(
            contentRect: frame.insetBy(dx: -contentInset, dy: -contentInset),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.sharingType = .readOnly
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
    }
}
