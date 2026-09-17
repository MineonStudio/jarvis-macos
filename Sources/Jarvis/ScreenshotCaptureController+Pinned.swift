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
        item.containerView?.showsShadow = item.showsShadow
        // The visible halo is rendered by the transparent inset container;
        // keep AppKit from adding a second window-level shadow.
        item.window.hasShadow = false
    }

    /// 显示器排布变化后收拾贴图：所在那块屏没了的直接销毁，否则把它收回可见范围。
    ///
    /// 不做这一步，拔掉外接屏后留下的贴图会变成幽灵窗口——不在任何屏幕上、点不到、
    /// 拿不到焦点，Esc 也关不掉，只能重启应用。
    func reconcilePinnedScreenshotsWithVisibleDisplays() {
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        guard !visibleFrames.isEmpty else { return }

        for item in pinnedItems.values {
            let frame = item.window.frame
            guard let host = visibleFrames.first(where: { $0.intersects(frame) }) else {
                destroyPinnedScreenshot(item)
                continue
            }
            var clamped = frame
            clamped.origin.x = min(max(clamped.minX, host.minX), max(host.minX, host.maxX - clamped.width))
            clamped.origin.y = min(max(clamped.minY, host.minY), max(host.minY, host.maxY - clamped.height))
            guard clamped != frame else { continue }
            item.window.setFrame(clamped, display: false)
        }
        JarvisLog.notice(
            category: .window,
            event: "screenshot.pinned.reconciled",
            result: "success",
            fields: ["count": String(pinnedItems.count)]
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
            // 窗口下沿已经在选区顶边之上 = 整条工具栏在选区上方。
            placesSecondaryRowAboveMain: rect.minY >= imageFrame.maxY - 1
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
