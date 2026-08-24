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
            let data = editor.finalPNGData()
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
            guard item.toolbarWindow?.isKeyWindow != true else { return }
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
            },
            makeContextMenu: { [weak self, weak item] in
                guard let self, let item else { return nil }
                return makePinnedContextMenu(for: item)
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
        item.window.makeKeyAndOrderFront(nil)

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
        item.window.makeKeyAndOrderFront(nil)
        if item.showsToolbar {
            showPinnedToolbar(for: item)
        } else {
            hidePinnedToolbar(for: item)
        }
    }

    private func deselectPinnedScreenshot(_ item: PinnedScreenshotItem) {
        hidePinnedToolbar(for: item)
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

    private func makePinnedContextMenu(for item: PinnedScreenshotItem) -> NSMenu {
        let target = PinnedScreenshotContextMenuTarget(
            onToggleToolbar: { [weak self, weak item] in
                guard let self, let item else { return }
                togglePinnedToolbar(for: item)
            },
            onToggleShadow: { [weak self, weak item] in
                guard let self, let item else { return }
                togglePinnedShadow(for: item)
            }
        )
        item.contextMenuTarget = target

        let menu = NSMenu()
        let toolbarItem = NSMenuItem(
            title: "显示操作栏",
            action: #selector(PinnedScreenshotContextMenuTarget.toggleToolbar(_:)),
            keyEquivalent: ""
        )
        toolbarItem.target = target
        toolbarItem.state = item.showsToolbar ? .on : .off
        menu.addItem(toolbarItem)

        let shadowItem = NSMenuItem(
            title: "显示阴影",
            action: #selector(PinnedScreenshotContextMenuTarget.toggleShadow(_:)),
            keyEquivalent: ""
        )
        shadowItem.target = target
        shadowItem.state = item.showsShadow ? .on : .off
        menu.addItem(shadowItem)
        return menu
    }

    private func togglePinnedToolbar(for item: PinnedScreenshotItem) {
        guard pinnedItems[item.id] != nil else { return }
        item.showsToolbar.toggle()
        if selectedPinnedID != item.id {
            selectPinnedScreenshot(item)
        } else if item.showsToolbar {
            showPinnedToolbar(for: item)
        } else {
            hidePinnedToolbar(for: item)
        }
    }

    private func togglePinnedShadow(for item: PinnedScreenshotItem) {
        guard pinnedItems[item.id] != nil else { return }
        item.showsShadow.toggle()
        item.containerView?.showsShadow = item.showsShadow
    }

    private func showPinnedToolbar(for item: PinnedScreenshotItem) {
        guard item.toolbarWindow == nil else {
            resizePinnedToolbar(for: item)
            return
        }

        let frame = toolbarFrame(
            for: item.imageFrame,
            height: ScreenshotToolbarMetrics.compactHeight,
            width: ScreenshotToolbar.preferredWidth(for: nil)
        )
        let layout = ScreenshotToolbarLayoutModel(width: frame.width)
        let toolbarPanel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        toolbarPanel.level = .screenSaver
        toolbarPanel.backgroundColor = .clear
        toolbarPanel.isOpaque = false
        toolbarPanel.hasShadow = false
        toolbarPanel.hidesOnDeactivate = false
        toolbarPanel.isReleasedWhenClosed = false

        let toolbarHostingView = NSHostingView(
            rootView: ScreenshotToolbar(
                editor: item.editor,
                layout: layout,
                onAction: { [weak self, weak item] action in
                    guard let self, let item else { return }
                    handlePinnedToolbarAction(action, for: item)
                }
            )
        )
        toolbarHostingView.autoresizingMask = NSView.AutoresizingMask(arrayLiteral: .width, .height)
        toolbarHostingView.frame = NSRect(origin: .zero, size: frame.size)
        toolbarPanel.contentView = toolbarHostingView

        item.window.addChildWindow(toolbarPanel, ordered: .above)
        item.toolbarWindow = toolbarPanel
        item.toolbarLayout = layout
        toolbarPanel.orderFrontRegardless()

        item.editorObservation = item.editor.objectWillChange.sink { [weak self, weak item] _ in
            DispatchQueue.main.async {
                guard let self, let item else { return }
                self.resizePinnedToolbar(for: item)
            }
        }
    }

    private func hidePinnedToolbar(for item: PinnedScreenshotItem) {
        if let toolbarWindow = item.toolbarWindow {
            item.window.removeChildWindow(toolbarWindow)
            toolbarWindow.orderOut(nil)
        }
        item.toolbarWindow = nil
        item.toolbarLayout = nil
        item.editorObservation?.cancel()
        item.editorObservation = nil
        item.editor.selectTool(nil)
    }

    private func resizePinnedToolbar(for item: PinnedScreenshotItem) {
        guard let toolbarWindow = item.toolbarWindow else { return }
        let frame = toolbarFrame(
            for: item.imageFrame,
            height: item.editor.secondaryBarVisible
                ? ScreenshotToolbarMetrics.expandedHeight
                : ScreenshotToolbarMetrics.compactHeight,
            width: ScreenshotToolbar.preferredWidth(
                for: item.editor.selectedTool,
                mosaicMode: item.editor.mosaicMode
            )
        )
        toolbarWindow.setFrame(frame, display: true, animate: false)
        toolbarWindow.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        item.toolbarLayout?.width = frame.width
    }

    private func handlePinnedToolbarAction(
        _ action: ScreenshotAction,
        for item: PinnedScreenshotItem
    ) {
        switch action {
        case .saveRequested:
            finishPinnedScreenshot(item, makeAction: ScreenshotAction.save)
        case .confirmRequested:
            finishPinnedScreenshot(item, makeAction: ScreenshotAction.confirm)
        case let .save(data):
            let onAction = item.onAction
            destroyPinnedScreenshot(item)
            onAction?(.save(data))
        case let .confirm(data):
            let onAction = item.onAction
            destroyPinnedScreenshot(item)
            onAction?(.confirm(data))
        case .cancel:
            destroyPinnedScreenshot(item)
        case let .tool(tool):
            resizePinnedToolbar(for: item)
            item.onAction?(.tool(tool))
        case .undo, .redo, .delete, .duplicate:
            handlePinnedEditorAction(action, for: item)
        case .pin:
            break
        }
    }

    private func finishPinnedScreenshot(
        _ item: PinnedScreenshotItem,
        makeAction: @escaping (Data) -> ScreenshotAction
    ) {
        let editor = item.editor
        let onAction = item.onAction
        destroyPinnedScreenshot(item)
        Task { @MainActor in
            onAction?(makeAction(editor.finalPNGData()))
        }
    }

    private func handlePinnedEditorAction(_ action: ScreenshotAction, for item: PinnedScreenshotItem) {
        switch action {
        case .undo:
            item.editor.undo()
            item.onAction?(.undo)
        case .redo:
            item.editor.redo()
            item.onAction?(.redo)
        case .delete:
            item.editor.deleteSelectedAnnotation()
            item.onAction?(.delete)
        case .duplicate:
            item.editor.duplicateSelectedAnnotation()
            item.onAction?(.duplicate)
        default:
            break
        }
    }

    private func destroyPinnedScreenshot(_ item: PinnedScreenshotItem) {
        guard pinnedItems.removeValue(forKey: item.id) != nil else { return }
        hidePinnedToolbar(for: item)
        item.window.onEscape = nil
        item.window.onDidResignKey = nil
        item.window.orderOut(nil)
        item.window.close()
        if selectedPinnedID == item.id {
            selectedPinnedID = nil
        }
    }

    func toolbarFrame(for imageFrame: CGRect, height toolbarHeight: CGFloat, width requestedWidth: CGFloat) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(imageFrame) }
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let availableWidth = max(1, visibleFrame.width - ScreenshotToolbarMetrics.availableWidthInset)
        let toolbarWidth = min(requestedWidth, availableWidth)
        let fitsBelow = imageFrame.minY - toolbarHeight - ScreenshotToolbarMetrics.gap >= visibleFrame.minY
        let y = fitsBelow
            ? imageFrame.minY - toolbarHeight - ScreenshotToolbarMetrics.gap
            : imageFrame.maxY + ScreenshotToolbarMetrics.gap
        let x = min(
            max(
                imageFrame.midX - toolbarWidth / 2,
                visibleFrame.minX + ScreenshotToolbarMetrics.screenHorizontalInset
            ),
            visibleFrame.maxX - toolbarWidth - ScreenshotToolbarMetrics.screenHorizontalInset
        )

        return NSRect(
            x: x,
            y: y,
            width: toolbarWidth,
            height: toolbarHeight
        )
    }

    func resizeToolbar(for editor: ScreenshotEditorModel, on screenFrame: CGRect) {
        guard let toolbarWindow else { return }
        let imageFrame = editor.selectionFrame(on: screenFrame) ?? screenFrame
        let frame = toolbarFrame(
            for: imageFrame,
            height: editor.secondaryBarVisible
                ? ScreenshotToolbarMetrics.expandedHeight
                : ScreenshotToolbarMetrics.compactHeight,
            width: ScreenshotToolbar.preferredWidth(for: editor.selectedTool, mosaicMode: editor.mosaicMode)
        )
        toolbarWindow.setFrame(frame, display: true, animate: false)
        toolbarWindow.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        toolbarLayout?.width = frame.width
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
            cancelSelection(
                sessionID: sessionID,
                completion: completion,
                error: ScreenshotError.invalidSelection
            )
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
        restorePreviousApplication()
        activeSessionID = nil
        sessionPhase = .idle
        completion(.failure(error))
    }

    func dismissSelectionWindows() {
        selectionWindows.forEach { $0.orderOut(nil) }
        selectionWindows.removeAll()
        if NSCursor.current == NSCursor.crosshair {
            NSCursor.pop()
        }
    }

    func restorePreviousApplication() {
        guard let previousApplication = previousFrontmostApplication else { return }
        previousFrontmostApplication = nil
        guard !previousApplication.isTerminated else { return }

        // The capture overlay activates Jarvis so it can receive Escape. Once
        // the user cancels, hide Jarvis and hand focus back to the app that
        // was in front instead of exposing Jarvis's main window.
        NSApp.hide(nil)
        previousApplication.activate(options: [])
    }
}
