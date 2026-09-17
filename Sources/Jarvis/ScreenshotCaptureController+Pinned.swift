import AppKit
import Combine
import SwiftUI

extension ScreenshotCaptureController {
    func pinScreenshot(
        editor: ScreenshotEditorModel,
        frame: CGRect,
        onAction: @escaping (ScreenshotAction) -> Void
    ) {
        sessionPhase = .pinning
        // Close the frozen editing surface immediately. Rendering the final
        // image can include annotations and should not make the middle-click
        // feel delayed.
        dismissResult()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let data = await editor.finalPNGData()
            createPinnedScreenshot(data: data, frame: frame, onAction: onAction)
            sessionPhase = .idle
            activeSessionID = nil
            onAction(.pin(data))
        }
    }

    private func createPinnedScreenshot(
        data: Data,
        frame: CGRect,
        onAction: @escaping (ScreenshotAction) -> Void
    ) {
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return
        }

        let item = PinnedScreenshotItem(data: data, image: image, frame: frame)
        item.onAction = onAction
        item.window.delegate = item.window
        item.window.onEscape = { [weak self, weak item] in
            guard let self, let item else { return }
            destroyPinnedScreenshot(item)
        }
        item.window.onDidResignKey = { [weak self, weak item] in
            guard let self, let item,
                  selectedPinnedID == item.id else { return }
            // The toolbar is a child window. Clicking a toolbar control can
            // briefly move key-window status to it, so keep the pin selected.
            deselectPinnedScreenshot(item)
        }

        let hostingView = ScreenshotCanvasHostingView(
            rootView: ScreenshotCanvasView(
                image: image,
                editor: item.editor,
                interactive: true,
                showsSelectionOverlay: false
            ),
            editor: item.editor,
            allowsSelectionTransform: false,
            onActivate: { [weak self, weak item] in
                guard let self, let item else { return }
                selectPinnedScreenshot(item)
            },
            onEscape: { [weak self, weak item] in
                guard let self, let item else { return }
                destroyPinnedScreenshot(item)
            }
        )
        let containerView = PinnedScreenshotContainerView(
            frame: NSRect(origin: .zero, size: item.window.frame.size),
            imageSize: image.size,
            contentInset: item.contentInset,
            editor: item.editor,
            onActivate: { [weak self, weak item] in
                guard let self, let item else { return }
                selectPinnedScreenshot(item)
            }
        )
        hostingView.frame = NSRect(
            x: item.contentInset,
            y: item.contentInset,
            width: image.size.width,
            height: image.size.height
        )
        containerView.addSubview(hostingView)
        item.containerView = containerView
        item.window.contentView = containerView
        item.window.orderFrontRegardless()
        item.window.makeKey()

        pinnedItems[item.id] = item
        selectPinnedScreenshot(item)
    }

    private func selectPinnedScreenshot(_ item: PinnedScreenshotItem) {
        guard pinnedItems[item.id] != nil else { return }
        for other in pinnedItems.values where other.id != item.id {
            deselectPinnedScreenshot(other)
        }

        selectedPinnedID = item.id
        setPinnedSelectionAppearance(item, selected: true)
        item.window.orderFrontRegardless()
        item.window.makeKey()
    }

    private func deselectPinnedScreenshot(_ item: PinnedScreenshotItem) {
        setPinnedSelectionAppearance(item, selected: false)
        if selectedPinnedID == item.id {
            selectedPinnedID = nil
        }
    }

    private func setPinnedSelectionAppearance(
        _ item: PinnedScreenshotItem,
        selected: Bool
    ) {
        item.containerView?.isSelected = selected
        // 阴影恒开：贴图没有可以关掉它的入口，原来那层 item.showsShadow 间接
        // 永远传 true。
        item.containerView?.showsShadow = true
        // The visible halo is rendered by the transparent inset container;
        // keep AppKit from adding a second window-level shadow.
        item.window.hasShadow = false
    }

    /// 显示器排布变化后收拾贴图：所在那块屏没了的直接销毁，否则把它收回可见范围。
    ///
    /// 不做这一步，拔掉外接屏后留下的贴图会变成幽灵窗口——不在任何屏幕上、点不到、
    /// 拿不到焦点，Esc 也关不掉，只能重启应用。
    func reconcilePinnedScreenshotsWithVisibleDisplays() {
        // 只在**屏幕集合本身**变了的时候动手。Dock 收起/菜单栏变化等也会发这个
        // 通知，那种时候用户没动过的贴图不该被挪走。
        let screens = NSScreen.screens.map(\.frame)
        guard screens != lastKnownScreenFrames else { return }
        lastKnownScreenFrames = screens
        guard !screens.isEmpty else { return }

        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        var destroyed = 0
        var moved = 0
        for item in pinnedItems.values {
            let frame = item.window.frame
            // 还看得见的一律不动：用户的摆放位置归用户。
            guard !visibleFrames.contains(where: { $0.intersects(frame) }) else { continue }
            // 看不见了才处理：先试着收进它主要覆盖的那块屏。
            let host = visibleFrames.max { a, b in
                a.intersection(frame).area < b.intersection(frame).area
            }
            guard let host, host.intersection(frame).area > 0 || visibleFrames.count == 1 else {
                destroyPinnedScreenshot(item)
                destroyed += 1
                continue
            }
            var clamped = frame
            clamped.size.width = min(clamped.width, host.width)
            clamped.size.height = min(clamped.height, host.height)
            clamped.origin.x = min(max(clamped.minX, host.minX), host.maxX - clamped.width)
            clamped.origin.y = min(max(clamped.minY, host.minY), host.maxY - clamped.height)
            item.window.setFrame(clamped, display: false)
            moved += 1
        }
        JarvisLog.notice(
            category: .window,
            event: "screenshot.pinned.reconciled",
            result: "success",
            fields: [
                "screens": String(screens.count),
                "moved": String(moved),
                "destroyed": String(destroyed)
            ]
        )
    }

    private func destroyPinnedScreenshot(_ item: PinnedScreenshotItem) {
        guard pinnedItems.removeValue(forKey: item.id) != nil else { return }
        item.editor.cancelTranslation()
        item.window.onEscape = nil
        item.window.onDidResignKey = nil
        item.window.orderOut(nil)
        item.window.close()
        if selectedPinnedID == item.id {
            selectedPinnedID = nil
        }
    }

    /// 工具栏窗口的落位，外加它是落在选区上方还是下方。
    struct ToolbarFramePlacement {
        let rect: NSRect
        let placesSecondaryRowAboveMain: Bool
    }

    func toolbarFrame(
        for imageFrame: CGRect,
        height toolbarHeight: CGFloat,
        width requestedWidth: CGFloat
    ) -> ToolbarFramePlacement {
        let screen = NSScreen.screens.first { $0.frame.intersects(imageFrame) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero
        let rect = ScreenshotToolbarPlacement.frame(
            for: imageFrame,
            in: visibleFrame,
            height: toolbarHeight,
            width: requestedWidth
        )
        return ToolbarFramePlacement(
            rect: rect,
            // 由落位本身给出，不再从矩形反推：压在图上（overlay）那一支同样以窗口
            // 下沿为基准，反推会漏掉它，于是接近全屏的选区上主行照样会弹。
            placesSecondaryRowAboveMain: ScreenshotToolbarPlacement.anchor(
                for: imageFrame,
                in: visibleFrame,
                requestedWidth: requestedWidth
            ).anchorsWindowBottom
        )
    }

    private func applyToolbarFrame(
        _ placement: ToolbarFramePlacement,
        to window: NSWindow,
        updating layout: ScreenshotToolbarLayoutModel?
    ) {
        let frame = placement.rect
        if window.frame != frame {
            window.setFrame(frame, display: false, animate: false)
            window.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        }
        guard let layout else { return }
        if layout.width != frame.width {
            layout.width = frame.width
        }
        if layout.placesSecondaryRowAboveMain != placement.placesSecondaryRowAboveMain {
            layout.placesSecondaryRowAboveMain = placement.placesSecondaryRowAboveMain
        }
    }

    func resizeToolbar(for editor: ScreenshotEditorModel, on screenFrame: CGRect) {
        guard let toolbarWindow else { return }
        let imageFrame = editor.selectionFrame(on: screenFrame) ?? screenFrame
        let placement = toolbarFrame(
            for: imageFrame,
            height: editor.secondaryBarVisible
                ? ScreenshotToolbarMetrics.expandedHeight
                : ScreenshotToolbarMetrics.compactHeight,
            width: ScreenshotToolbarMetrics.baseWidth
        )
        applyToolbarFrame(placement, to: toolbarWindow, updating: toolbarLayout)
    }

    func finishSelection(
        _ localRect: CGRect,
        frozenScreen: ScreenshotCapture,
        on screen: NSScreen,
        sessionID: UUID,
        pinAfterSelection: Bool = false,
        completion: @escaping (Result<ScreenshotEditingSession, Error>) -> Void
    ) {
        guard activeSessionID == sessionID,
              !selectionCompletionDelivered else { return }
        guard localRect.width >= 24, localRect.height >= 24 else {
            // 太小的选区（在空白桌面上点一下、或者手抖拖出十几点）不当作一次截图：
            // 留着遮罩和冻结帧，让用户在同一屏上重新拖。原来这里直接 cancelSelection，
            // 整场截图被销毁，用户得重新按热键再等一次全屏采集。
            return
        }

        do {
            let capture = try screenshotService.crop(
                frozenScreen,
                to: localRect,
                on: screen.frame
            )
            let session = ScreenshotEditingSession(
                id: sessionID,
                frozenScreen: frozenScreen,
                selectionRect: localRect,
                initialCapture: capture
            )
            pinNextSelectionResult = pinAfterSelection
            selectionCompletionDelivered = true
            completion(.success(session))
        } catch {
            dismissSelectionWindows()
            pinNextSelectionResult = false
            selectionCompletionDelivered = true
            activeSessionID = nil
            sessionPhase = .idle
            completion(.failure(error))
        }
    }

    func cancelSelection(
        sessionID: UUID,
        completion: @escaping (Result<ScreenshotEditingSession, Error>) -> Void,
        error: Error = ScreenshotError.cancelled
    ) {
        guard activeSessionID == sessionID,
              !selectionCompletionDelivered else { return }
        selectionCompletionDelivered = true
        dismissSelectionWindows()
        activeSessionID = nil
        sessionPhase = .idle
        completion(.failure(error))
    }

    func dismissSelectionWindows() {
        for window in selectionWindows {
            window.orderOut(nil)
            window.close()
        }
        selectionWindows.removeAll()
        popCrosshairCursorIfNeeded()
    }

    func popCrosshairCursorIfNeeded() {
        guard didPushCrosshairCursor else { return }
        NSCursor.pop()
        didPushCrosshairCursor = false
    }
}

private extension CGRect {
    /// 相交面积（比较「主要落在哪块屏上」用）。
    var area: CGFloat {
        let rect = isNull || isEmpty ? .zero : self
        return rect.width * rect.height
    }
}
