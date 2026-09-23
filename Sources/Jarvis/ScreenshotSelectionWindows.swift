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

    /// Quartz 全局坐标的翻转基准：主屏高度。
    ///
    /// 不是「所有屏里最高的那块」——Quartz 的原点跟着主屏走，取最高屏会在有屏排到
    /// 主屏上方时让所有局部坐标整体平移。`ScreenshotWindowSelectionGeometryTests`
    /// 用 AppKit 侧的主屏高度交叉验证这个值。
    static var quartzDesktopTop: CGFloat {
        CGDisplayBounds(CGMainDisplayID()).maxY
    }

    static func candidates(
        for screenFrame: CGRect
    ) -> [WindowSelectionCandidate] {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        let desktopTop = quartzDesktopTop
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

enum PinnedScreenshotZoom {
    static let step: CGFloat = 0.1
    static let minimum: CGFloat = 0.2
    static let maximum: CGFloat = 4

    static func scrollDelta(
        scrollingDeltaY: CGFloat,
        isWindowKey: Bool
    ) -> CGFloat? {
        guard isWindowKey, abs(scrollingDeltaY) > 0.01 else { return nil }
        return scrollingDeltaY > 0 ? step : -step
    }

    static func adjustedZoom(
        from current: CGFloat,
        scrollingDeltaY: CGFloat,
        isWindowKey: Bool
    ) -> CGFloat? {
        guard let delta = scrollDelta(
            scrollingDeltaY: scrollingDeltaY,
            isWindowKey: isWindowKey
        ) else {
            return nil
        }
        let stepped = (current / step).rounded() * step + delta
        return min(max(stepped, minimum), maximum)
    }
}

final class PinnedScreenshotWindow: NSPanel, NSWindowDelegate {
    var onEscape: (() -> Void)?
    var onDidResignKey: (() -> Void)?
    var onScrollZoom: ((CGFloat) -> Void)?

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
        if event.type == .scrollWheel {
            guard let delta = PinnedScreenshotZoom.scrollDelta(
                scrollingDeltaY: event.scrollingDeltaY,
                isWindowKey: isKeyWindow
            ) else {
                super.sendEvent(event)
                return
            }
            onScrollZoom?(delta)
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
    /// 右键菜单里的「编辑」（由控制器接到编辑流程上）。
    var onEdit: (() -> Void)?
    /// 「编辑」当前能不能开：同时只允许一场编辑，会话进行中这一项置灰。
    var canEdit: (() -> Bool)?
    /// 右键菜单里的「销毁」（由控制器接到销毁流程上）。
    var onDestroy: (() -> Void)?
    var isSelected = false {
        didSet {
            needsDisplay = true
        }
    }

    /// 贴图周围那圈光晕。右键菜单里能关掉，`PinnedScreenshotItem` 换图时会
    /// 把它带过去，所以别在这里写死。
    var showsShadow = true {
        didSet { needsDisplay = true }
    }

    private var initialWindowOrigin: NSPoint?
    private var initialMouseLocation: NSPoint?
    private(set) var zoom: CGFloat = 1

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

    /// 复制、编辑、找到存到哪儿去都没有入口。
    override func menu(for _: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let copyItem = NSMenuItem(
            title: "复制图片",
            action: #selector(copyImageToPasteboard),
            keyEquivalent: ""
        )
        copyItem.target = self
        menu.addItem(copyItem)

        let editItem = NSMenuItem(title: "编辑", action: #selector(editPin), keyEquivalent: "")
        editItem.target = self
        editItem.isEnabled = canEdit?() ?? true
        menu.addItem(editItem)

        // 标题报的是**点下去会做什么**：现在有光晕就写「隐藏阴影」。
        // 当前状态用不着写在标题里——光晕本身就看得见。
        let shadowItem = NSMenuItem(
            title: showsShadow ? "隐藏阴影" : "显示阴影",
            action: #selector(toggleShadow),
            keyEquivalent: ""
        )
        shadowItem.target = self
        menu.addItem(shadowItem)

        menu.addItem(.separator())
        let destroyItem = NSMenuItem(title: "销毁", action: #selector(destroyPin), keyEquivalent: "")
        destroyItem.target = self
        menu.addItem(destroyItem)
        return menu
    }

    @objc private func copyImageToPasteboard() {
        // 导出是异步的（渲染 + 编码在后台），菜单动作里开个任务等它。
        Task { @MainActor [weak self] in
            guard let self else { return }
            let data = await editor.finalPNGData()
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.setData(data, forType: .png) else { return }
            JarvisLog.notice(category: .window, event: "screenshot.pinned.copy", result: "success")
        }
    }

    @objc private func editPin() {
        onEdit?()
    }

    @objc private func toggleShadow() {
        showsShadow.toggle()
        JarvisLog.notice(
            category: .window,
            event: "screenshot.pinned.shadow",
            result: "success",
            fields: ["shows": String(showsShadow)]
        )
    }

    @objc private func destroyPin() {
        onDestroy?()
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

    func updateZoom(_ zoom: CGFloat) {
        self.zoom = zoom
        setFrameSize(containerSize)
        needsDisplay = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        guard let canvasView = subviews.first as? ScreenshotCanvasHostingView else { return }
        canvasView.updateCanvasScale(zoom)
        canvasView.frame = NSRect(
            x: contentInset,
            y: contentInset,
            width: imageSize.width * zoom,
            height: imageSize.height * zoom
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let imageRect = CGRect(
            x: contentInset,
            y: contentInset,
            width: imageSize.width * zoom,
            height: imageSize.height * zoom
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

        // 选中描边要画在图片**外面**：图片是子视图，压在容器上面，落在图片范围内的
        // 描边根本看不见（原来那条就是这么没的）。关掉阴影之后光晕也没了，这圈描边
        // 是唯一说明「这张贴图是选中的」的东西，所以它不能再跟着阴影一起消失。
        if isSelected {
            let selectionPath = NSBezierPath(rect: imageRect.insetBy(dx: -1, dy: -1))
            NSColor.systemBlue.withAlphaComponent(0.92).setStroke()
            selectionPath.lineWidth = 2
            selectionPath.stroke()
        }
    }

    private func updateShadowAppearance() {
        guard let layer else { return }
        let imageRect = CGRect(
            x: contentInset,
            y: contentInset,
            width: imageSize.width * zoom,
            height: imageSize.height * zoom
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

    private var containerSize: CGSize {
        CGSize(
            width: imageSize.width * zoom + contentInset * 2,
            height: imageSize.height * zoom + contentInset * 2
        )
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
    var containerView: PinnedScreenshotContainerView?
    var onAction: ((ScreenshotAction) -> Void)?
    private(set) var zoom: CGFloat = 1

    var imageFrame: CGRect {
        CGRect(
            x: window.frame.minX + contentInset,
            y: window.frame.minY + contentInset,
            width: imageSize.width * zoom,
            height: imageSize.height * zoom
        )
    }

    func adjustZoom(by scrollingDeltaY: CGFloat) {
        guard let nextZoom = PinnedScreenshotZoom.adjustedZoom(
            from: zoom,
            scrollingDeltaY: scrollingDeltaY,
            isWindowKey: window.isKeyWindow
        ), nextZoom != zoom else {
            return
        }

        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        zoom = nextZoom
        let size = CGSize(
            width: imageSize.width * zoom + contentInset * 2,
            height: imageSize.height * zoom + contentInset * 2
        )
        window.setFrame(
            NSRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            display: true
        )
        containerView?.updateZoom(zoom)
    }

    init(data: Data, image: NSImage, frame: CGRect) {
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
            styleMask: [.borderless, .nonactivatingPanel],
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
        window.animationBehavior = .none
        window.becomesKeyOnlyIfNeeded = false
    }
}
