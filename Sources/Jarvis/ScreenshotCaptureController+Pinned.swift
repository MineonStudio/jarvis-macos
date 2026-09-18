import AppKit
import Combine
import SwiftUI

extension ScreenshotCaptureController {
    func pinScreenshot(
        editor: ScreenshotEditorModel,
        frame: CGRect,
        onAction: @escaping (ScreenshotAction) -> Void
    ) {
        // 中键贴在**正在编辑**的这张贴图上：先把这张贴图抓到手上，编辑面拆完之后
        // 它还在。结果要换回原位那张图，不再新开一张——旧的那张还藏着，新开就叠成
        // 两张了。
        //
        // 认「正在编辑」看的是会话阶段：编辑面开着时会话必定处于编辑中，只有这时
        // `editingPinnedItem` 才作数。否则一个陈旧的值会把编辑结束之后的普通中键
        // 也拐到这条路上，把刚截的图写进一张看不见的旧贴图。
        let editingItem = sessionPhase == .editing ? editingPinnedItem : nil
        sessionPhase = .pinning
        // Close the frozen editing surface immediately. Rendering the final
        // image can include annotations and should not make the middle-click
        // feel delayed.
        dismissResult()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let data = await editor.finalPNGData()
            if let editingItem {
                applyPinnedEdit(data, to: editingItem)
            } else {
                createPinnedScreenshot(data: data, frame: frame, onAction: onAction)
            }
            sessionPhase = .idle
            activeSessionID = nil
            onAction(.pin(data))
        }
    }

    private func createPinnedScreenshot(
        data: Data,
        frame: CGRect,
        showsShadow: Bool = true,
        onAction: ((ScreenshotAction) -> Void)?
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
            },
            // 贴图上的键盘动作（⌫/⌘D/⌘Z）：先作用在它自己的编辑器上，再转给上层
            // 更新状态栏——两条路走同一条通道，提示和实际动作才不会脱节。
            onAction: { [weak self, weak item] action in
                guard let self, let item else { return }
                handlePinnedCanvasAction(action, for: item)
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
        containerView.showsShadow = showsShadow
        containerView.canEdit = { [weak self] in
            self?.canBeginPinnedEdit ?? false
        }
        containerView.onEdit = { [weak self, weak item] in
            guard let self, let item else { return }
            beginPinnedEdit(item)
        }
        containerView.onDestroy = { [weak self, weak item] in
            guard let self, let item else { return }
            destroyPinnedScreenshot(item)
        }
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
        // 阴影归用户：右键菜单里能开关，这里不再替它决定；换图时也由调用方
        // 把原状态带过去。
        // The visible halo is rendered by the transparent inset container;
        // keep AppKit from adding a second window-level shadow.
        item.window.hasShadow = false
    }

    // MARK: - 编辑贴图

    /// 编辑会话里的一个动作，贴图该怎么收场。
    enum PinnedEditOutcome: Equatable {
        /// 把编辑结果写回原位。
        case apply(Data)
        /// 原样放回去——这场编辑什么都没存过。
        case restore
        /// 贴图这一刻不动。
        case ignore
    }

    /// 「完成」当场写回；「保存」在这一刻什么都不做（它还没真的存盘，见
    /// `notePinnedEditSaved`）；中键贴图的结果已经在 `pinScreenshot` 里换过了；
    /// Esc 收场分两种：存过盘就用存的那份，什么都没存才原样放回去——存过盘的一次
    /// 编辑不该因为按了 Esc 就看不见了。
    nonisolated static func pinnedEditOutcome(
        for action: ScreenshotAction,
        committedData: Data?
    ) -> PinnedEditOutcome {
        switch action {
        case let .confirm(data):
            .apply(data)
        case .cancel:
            committedData.map(PinnedEditOutcome.apply) ?? .restore
        default:
            .ignore
        }
    }

    /// 「编辑」能不能开。同时只允许一场编辑：另一张贴图的「编辑」会置灰，
    /// 正在截图时也不能从贴图里再开一个编辑面。
    var canBeginPinnedEdit: Bool {
        sessionPhase == .idle && editingPinnedItem == nil
    }

    /// 右键「编辑」：把这张贴图放回编辑面，位置和大小就是它原来那张图的位置。
    ///
    /// 贴图在编辑期间藏起来——编辑面正好盖在它身上，不藏会看到两层。会话收场时
    /// 要么把结果写回原位，要么原样放回去。
    func beginPinnedEdit(_ item: PinnedScreenshotItem) {
        guard canBeginPinnedEdit, pinnedItems[item.id] != nil else { return }
        // 先占位：导出要几百毫秒（有标注时真的会挂起），这期间再右键一次不能再开
        // 一场——「编辑」此刻是灰的。
        editingPinnedItem = item
        editingPinnedCommittedData = nil
        Task { @MainActor [weak self, weak item] in
            guard let self, let item, pinnedItems[item.id] != nil else { return }
            let data = await item.editor.finalPNGData()
            guard editingPinnedItem === item,
                  sessionPhase == .idle,
                  let image = NSImage(data: data),
                  image.size.width > 0,
                  image.size.height > 0
            else {
                // 只清自己的占位：这中间可能已经有别人的一场编辑开起来了，清掉就是
                // 把人家刚开好的会话拆了（贴图会停在藏起来的状态回不来）。
                if editingPinnedItem === item {
                    editingPinnedItem = nil
                    editingPinnedCommittedData = nil
                }
                return
            }
            let frame = item.imageFrame
            let onAction = item.onAction
            item.window.orderOut(nil)
            JarvisLog.notice(
                category: .window,
                event: "screenshot.pinned.edit",
                result: "success",
                fields: ["phase": "begin"]
            )
            let opened = showPinnedEditSurface(data: data, frame: frame) { [weak self, weak item] action in
                guard let self, let item else { return }
                handlePinnedEditAction(action, for: item, forward: onAction)
            }
            if !opened {
                // 编辑面没开起来（图读不出来之类）：贴图已经藏起来了，得放回去。
                restorePinnedScreenshot(item)
            }
        }
    }

    /// 「保存」真的写到盘上了：这次编辑有了存过盘的结果，Esc 收场时用它。
    ///
    /// 不能拿 `.save(data)` 那个动作当提交点——它在系统保存面板弹出来**之前**就发出
    /// 来了，用户接着在面板上点取消也一样发过。所以由 AppModel 在写盘成功之后回头
    /// 说一声（`finishSavePanel`）。
    func notePinnedEditSaved(_ data: Data) {
        guard editingPinnedItem != nil else { return }
        editingPinnedCommittedData = data
    }

    /// 编辑面按贴图在原位铺开。走的是「重新编辑历史截图」同一条路（`showResult`），
    /// 只是承载面板落在贴图原位而不是屏幕中央——看起来就像在贴图本身上面标注。
    ///
    /// 这两个开关都关掉：这是**标注**这张贴图，不是重新框一次选区。开着的话贴着边
    /// 拖一下就把贴图裁了（编辑器里还没法撤销），空手拖一下画布就跟着走、工具栏
    /// 留在原地。
    ///
    /// - Returns: 编辑面有没有真的开起来。没开起来时调用方要把贴图放回去。
    private func showPinnedEditSurface(
        data: Data,
        frame: CGRect,
        onAction: @escaping (ScreenshotAction) -> Void
    ) -> Bool {
        let capture = ScreenshotCapture(data: data, screenFrame: frame)
        let session = ScreenshotEditingSession(
            id: UUID(),
            frozenScreen: capture,
            // 选区是画布坐标：画布就是贴在屏幕上的那块，铺满。
            selectionRect: CGRect(origin: .zero, size: frame.size),
            initialCapture: capture
        )
        activeSessionID = session.id
        showResult(
            session,
            onAction: onAction,
            allowsSelectionTransform: false,
            allowsWindowDrag: false
        )
        return resultWindow != nil
    }

    /// 会话收场：按 outcome 表决定这张贴图变成什么，再把动作原样转给上层。
    ///
    /// 贴图**从闭包里带进来**，不在交付这一刻回头去读 `editingPinnedItem`：「完成」
    /// 是先拆掉编辑面、渲染几百毫秒、最后才交付动作的，这中间用户完全可能去动别的
    /// 贴图，回头再读就可能读到另一张（甚至读空），把 A 的结果写进 B。
    private func handlePinnedEditAction(
        _ action: ScreenshotAction,
        for item: PinnedScreenshotItem,
        forward: ((ScreenshotAction) -> Void)?
    ) {
        switch Self.pinnedEditOutcome(for: action, committedData: editingPinnedCommittedData) {
        case let .apply(data):
            applyPinnedEdit(data, to: item)
        case .restore:
            restorePinnedScreenshot(item)
        case .ignore:
            break
        }
        // 上层（AppModel）该做的事照旧：剪贴板、历史、状态栏提示。
        forward?(action)
    }

    /// 把编辑结果写回原位：位置照旧，换一张图。
    ///
    /// 旧窗口连着换掉——不这么做，贴图的编辑器和画布都还指着旧的那张图。换完重新
    /// 选中并前置，编辑面收场之后它就是眼前这张。
    private func applyPinnedEdit(_ data: Data, to item: PinnedScreenshotItem) {
        if editingPinnedItem === item {
            editingPinnedItem = nil
            editingPinnedCommittedData = nil
        }
        guard pinnedItems[item.id] != nil else { return }
        // 先确认这份结果能用，再销毁旧的：`createPinnedScreenshot` 拿不到图会
        // 静默返回，那就成了「编辑一下，贴图没了」。
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
            selectPinnedScreenshot(item)
            return
        }
        // 尺寸认新的这张图，位置认原地：编辑面里拖选区手柄改出来的裁切会让新图变小，
        // 窗口要是还照旧尺寸建，多出来的那圈是透明的却照样接点击——一块看不见、
        // 点得着、还拖着贴图到处跑的死区。没裁过时两者相等，位置一个点都不动。
        let frame = CGRect(origin: item.imageFrame.origin, size: image.size)
        let showsShadow = item.containerView?.showsShadow ?? true
        let onAction = item.onAction
        destroyPinnedScreenshot(item)
        createPinnedScreenshot(
            data: data,
            frame: frame,
            showsShadow: showsShadow,
            onAction: onAction
        )
        JarvisLog.notice(
            category: .window,
            event: "screenshot.pinned.edit",
            result: "success",
            fields: ["phase": "apply"]
        )
    }

    /// 这场编辑什么都没存过：把贴图原样放回去，位置不动。
    private func restorePinnedScreenshot(_ item: PinnedScreenshotItem) {
        if editingPinnedItem === item {
            editingPinnedItem = nil
            editingPinnedCommittedData = nil
        }
        selectPinnedScreenshot(item)
        JarvisLog.notice(
            category: .window,
            event: "screenshot.pinned.edit",
            result: "success",
            fields: ["phase": "restore"]
        )
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

    /// 贴图画布上的键盘动作。
    func handlePinnedCanvasAction(_ action: ScreenshotAction, for item: PinnedScreenshotItem) {
        switch action {
        case .undo:
            item.editor.undo()
        case .redo:
            item.editor.redo()
        case .delete:
            item.editor.deleteSelectedAnnotation()
        case .duplicate:
            item.editor.duplicateSelectedAnnotation()
        default:
            break
        }
        item.onAction?(action)
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
