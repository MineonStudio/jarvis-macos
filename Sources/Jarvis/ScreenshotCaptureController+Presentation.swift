import AppKit
import SwiftUI

extension ScreenshotCaptureController {
    // MARK: - Capture and selection lifecycle

    func requestScreenCaptureAccess() -> Bool {
        screenshotService.requestScreenCaptureAccess()
    }

    func beginCapture(completion: @escaping (Result<ScreenshotEditingSession, Error>) -> Void) {
        guard sessionPhase == .idle else { return }
        dismissSelectionWindows()
        dismissResult()
        selectionCompletionDelivered = false
        pinNextSelectionResult = false
        let sessionID = UUID()
        activeSessionID = sessionID
        sessionPhase = .capturing

        guard !NSScreen.screens.isEmpty else {
            activeSessionID = nil
            sessionPhase = .idle
            completion(.failure(ScreenshotError.permissionDenied))
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let frozenScreens = try await screenshotService.captureFullScreens(
                    screenFrames: NSScreen.screens.map(\.frame)
                )
                presentSelection(
                    frozenScreens: frozenScreens,
                    sessionID: sessionID,
                    completion: completion
                )
            } catch {
                guard activeSessionID == sessionID else { return }
                activeSessionID = nil
                sessionPhase = .idle
                completion(.failure(error))
            }
        }
    }

    private func presentSelection(
        frozenScreens: [ScreenshotCapture],
        sessionID: UUID,
        completion: @escaping (Result<ScreenshotEditingSession, Error>) -> Void
    ) {
        guard activeSessionID == sessionID else { return }
        sessionPhase = .selecting
        // Read the window list before presenting our screen-covering panels.
        // Otherwise the overlay itself would become the frontmost window under
        // the pointer and window selection would never find the user's window.
        var windowCandidatesByScreen: [(frame: CGRect, candidates: [WindowSelectionCandidate])] = []
        for frozenScreen in frozenScreens {
            guard let screen = NSScreen.screens.first(where: { $0.frame == frozenScreen.screenFrame }) else {
                continue
            }
            windowCandidatesByScreen.append(
                (
                    frame: screen.frame,
                    candidates: WindowSelectionDetector.candidates(
                        for: screen.frame
                    )
                )
            )
        }

        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        previousFrontmostApplication = NSWorkspace.shared.frontmostApplication?.processIdentifier == currentProcessID
            ? nil
            : NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()

        for frozenScreen in frozenScreens {
            guard let screen = NSScreen.screens.first(where: { $0.frame == frozenScreen.screenFrame }),
                  let candidates = windowCandidatesByScreen.first(where: { $0.frame == screen.frame })?.candidates,
                  let window = makeSelectionWindow(
                      for: frozenScreen,
                      on: screen,
                      candidates: candidates,
                      sessionID: sessionID,
                      completion: completion
                  )
            else {
                continue
            }
            selectionWindows.append(window)
        }

        guard !selectionWindows.isEmpty else {
            selectionCompletionDelivered = true
            dismissSelectionWindows()
            activeSessionID = nil
            sessionPhase = .idle
            completion(.failure(ScreenshotError.permissionDenied))
            return
        }
    }

    private func makeSelectionWindow(
        for frozenScreen: ScreenshotCapture,
        on screen: NSScreen,
        candidates: [WindowSelectionCandidate],
        sessionID: UUID,
        completion: @escaping (Result<ScreenshotEditingSession, Error>) -> Void
    ) -> SelectionOverlayWindow? {
        guard let frozenImage = NSImage(data: frozenScreen.data) else { return nil }

        let window = SelectionOverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.acceptsMouseMovedEvents = true

        let selectionView = SelectionOverlayView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            frozenImage: frozenImage,
            windowCandidates: candidates
        )
        selectionView.onFinish = { [weak self] localRect in
            self?.finishSelection(
                localRect,
                frozenScreen: frozenScreen,
                on: screen,
                sessionID: sessionID,
                completion: completion
            )
        }
        selectionView.onCancel = { [weak self] in
            self?.cancelSelection(sessionID: sessionID, completion: completion)
        }
        selectionView.onPin = { [weak self] localRect in
            self?.finishSelection(
                localRect,
                frozenScreen: frozenScreen,
                on: screen,
                sessionID: sessionID,
                pinAfterSelection: true,
                completion: completion
            )
        }
        window.onMiddleClick = { [weak selectionView] in
            selectionView?.pinHoveredWindow()
        }
        window.onEscape = { [weak self] in
            self?.cancelSelection(sessionID: sessionID, completion: completion)
        }
        window.contentView = selectionView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(selectionView)
        return window
    }

    func showResult(
        _ session: ScreenshotEditingSession,
        translationProgress: ScreenshotTranslationProgress,
        onAction: @escaping (ScreenshotAction) -> Void
    ) {
        guard activeSessionID == session.id else { return }
        let capture = session.frozenScreen
        guard let image = NSImage(data: capture.data) else { return }
        let shouldPinImmediately = pinNextSelectionResult
        pinNextSelectionResult = false
        dismissResult()
        sessionPhase = .editing
        activeSessionID = session.id

        let editor = ScreenshotEditorModel(
            image: image,
            data: capture.data,
            outputData: session.initialCapture.data,
            canvasSize: capture.screenFrame.size,
            outputRect: session.selectionRect
        )
        activeEditor = editor
        activeCaptureScreenFrame = capture.screenFrame
        let presentation = ScreenshotPresentation(
            session: session,
            capture: capture,
            image: image,
            editor: editor,
            translationProgress: translationProgress,
            onAction: onAction
        )
        let panels = makePresentationPanels(presentation)
        panels.imagePanel.addChildWindow(panels.toolbarPanel, ordered: .above)
        resultWindow = panels.imagePanel
        toolbarWindow = panels.toolbarPanel
        toolbarLayout = panels.toolbarLayout
        panels.imagePanel.makeKeyAndOrderFront(nil)
        panels.toolbarPanel.orderFrontRegardless()

        editorObservation = editor.objectWillChange.sink { [weak self, weak editor] _ in
            DispatchQueue.main.async {
                guard let self, let editor else { return }
                self.resizeToolbar(for: editor, on: capture.screenFrame)
            }
        }

        if shouldPinImmediately {
            let frame = editor.selectionFrame(on: capture.screenFrame) ?? capture.screenFrame
            Task { @MainActor [weak self] in
                guard let self else { return }
                pinScreenshot(editor: editor, frame: frame, onAction: onAction)
            }
        }
    }

    private func makePresentationPanels(
        _ presentation: ScreenshotPresentation
    ) -> ScreenshotPresentationPanels {
        let imagePanel = makeImagePanel(presentation)
        let frame = toolbarFrame(
            for: presentation.session.selectionFrame,
            height: ScreenshotToolbarMetrics.compactHeight,
            width: ScreenshotToolbar.preferredWidth(for: nil)
        )
        let toolbarLayout = ScreenshotToolbarLayoutModel(width: frame.width)
        let toolbarPanel = makeToolbarPanel(
            frame: frame,
            layout: toolbarLayout,
            presentation: presentation
        )
        return ScreenshotPresentationPanels(
            imagePanel: imagePanel,
            toolbarPanel: toolbarPanel,
            toolbarLayout: toolbarLayout
        )
    }

    private func makeImagePanel(_ presentation: ScreenshotPresentation) -> NSPanel {
        let cancelEditing: () -> Void = { [weak self] in
            guard let self else { return }
            dismissResult()
            restorePreviousApplication()
            presentation.onAction(.cancel)
        }
        let quickCopyAndClose: () -> Void = { [weak self, weak editor = presentation.editor] in
            guard let self, let editor else { return }
            dismissResult()
            Task { @MainActor in
                presentation.onAction(.confirm(editor.finalPNGData()))
            }
        }
        let pasteToScreen: () -> Void = { [weak self, weak editor = presentation.editor] in
            guard let self, let editor else { return }
            let frame = editor.selectionFrame(on: presentation.capture.screenFrame)
                ?? presentation.capture.screenFrame
            pinScreenshot(editor: editor, frame: frame, onAction: presentation.onAction)
        }

        let imagePanel: NSPanel
        if let selectionWindow = selectionWindows.first(where: { $0.frame == presentation.capture.screenFrame }) {
            selectionWindows
                .filter { $0 !== selectionWindow }
                .forEach { $0.orderOut(nil) }
            selectionWindows.removeAll()
            if NSCursor.current == NSCursor.crosshair {
                NSCursor.pop()
            }
            imagePanel = selectionWindow
            selectionWindow.onDoubleClick = quickCopyAndClose
            selectionWindow.onMiddleClick = pasteToScreen
            selectionWindow.onEscape = cancelEditing
        } else {
            let screenshotPanel = ScreenshotImagePanel(
                contentRect: presentation.capture.screenFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            screenshotPanel.onDoubleClick = quickCopyAndClose
            screenshotPanel.onMiddleClick = pasteToScreen
            screenshotPanel.onEscape = cancelEditing
            imagePanel = screenshotPanel
        }

        imagePanel.level = .screenSaver
        imagePanel.backgroundColor = .clear
        imagePanel.isOpaque = false
        imagePanel.hasShadow = false
        imagePanel.isMovableByWindowBackground = false
        imagePanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        imagePanel.hidesOnDeactivate = false
        imagePanel.isReleasedWhenClosed = false
        let canvasHostingView = ScreenshotCanvasHostingView(
            rootView: ScreenshotCanvasView(
                image: presentation.image,
                editor: presentation.editor,
                interactive: true
            ),
            editor: presentation.editor,
            onDoubleClick: quickCopyAndClose,
            onMiddleClick: pasteToScreen,
            onEscape: cancelEditing
        )
        canvasHostingView.frame = NSRect(origin: .zero, size: presentation.capture.screenFrame.size)
        canvasHostingView.autoresizingMask = NSView.AutoresizingMask(arrayLiteral: .width, .height)
        imagePanel.contentView = canvasHostingView
        imagePanel.makeFirstResponder(canvasHostingView)
        return imagePanel
    }

    private func makeToolbarPanel(
        frame: CGRect,
        layout: ScreenshotToolbarLayoutModel,
        presentation: ScreenshotPresentation
    ) -> NSPanel {
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
                editor: presentation.editor,
                layout: layout,
                translationProgress: presentation.translationProgress,
                onAction: { [weak self] action in
                    self?.handleToolbarAction(
                        action,
                        editor: presentation.editor,
                        screenFrame: presentation.capture.screenFrame,
                        onAction: presentation.onAction
                    )
                }
            )
        )
        toolbarHostingView.autoresizingMask = NSView.AutoresizingMask(arrayLiteral: .width, .height)
        toolbarPanel.contentView = toolbarHostingView
        toolbarHostingView.frame = NSRect(origin: .zero, size: frame.size)
        return toolbarPanel
    }

    private func handleToolbarAction(
        _ action: ScreenshotAction,
        editor: ScreenshotEditorModel,
        screenFrame: CGRect,
        onAction: @escaping (ScreenshotAction) -> Void
    ) {
        switch action {
        case .saveRequested:
            finishToolbarAction(editor, onAction: onAction, makeAction: ScreenshotAction.save)
        case .confirmRequested:
            dismissResult()
            finishToolbarAction(editor, onAction: onAction, makeAction: ScreenshotAction.confirm)
        case .save, .confirm:
            onAction(action)
        case .cancel:
            dismissResult()
            restorePreviousApplication()
            onAction(.cancel)
        case let .tool(tool):
            resizeToolbar(for: editor, on: screenFrame)
            onAction(.tool(tool))
        case .translateRequested:
            onAction(action)
        case .pin:
            break
        default:
            handleToolbarEditorAction(action, editor: editor, onAction: onAction)
        }
    }

    private func finishToolbarAction(
        _ editor: ScreenshotEditorModel,
        onAction: @escaping (ScreenshotAction) -> Void,
        makeAction: @escaping (Data) -> ScreenshotAction
    ) {
        Task { @MainActor in
            onAction(makeAction(editor.finalPNGData()))
        }
    }

    private func handleToolbarEditorAction(
        _ action: ScreenshotAction,
        editor: ScreenshotEditorModel,
        onAction: @escaping (ScreenshotAction) -> Void
    ) {
        switch action {
        case .undo:
            editor.undo()
            onAction(.undo)
        case .redo:
            editor.redo()
            onAction(.redo)
        case .delete:
            editor.deleteSelectedAnnotation()
            onAction(.delete)
        case .duplicate:
            editor.duplicateSelectedAnnotation()
            onAction(.duplicate)
        default:
            break
        }
    }

    /// Reopens a persisted screenshot on the same frozen editing surface used
    /// by a fresh capture. The synthetic full-screen session keeps the editor's
    /// coordinate space identical to the PNG, so annotations are not offset on
    /// a second edit.
    func showHistoryResult(
        data: Data,
        translationProgress: ScreenshotTranslationProgress,
        onAction: @escaping (ScreenshotAction) -> Void
    ) {
        guard sessionPhase == .idle,
              let image = NSImage(data: data),
              image.size.width > 0,
              image.size.height > 0 else { return }

        let visibleFrame = NSScreen.main?.visibleFrame ?? CGRect(
            origin: .zero,
            size: image.size
        )
        let frame = CGRect(
            x: visibleFrame.midX - image.size.width / 2,
            y: visibleFrame.midY - image.size.height / 2,
            width: image.size.width,
            height: image.size.height
        )
        let capture = ScreenshotCapture(data: data, screenFrame: frame)
        let session = ScreenshotEditingSession(
            id: UUID(),
            frozenScreen: capture,
            selectionRect: CGRect(origin: .zero, size: image.size),
            initialCapture: capture
        )
        activeSessionID = session.id
        showResult(session, translationProgress: translationProgress, onAction: onAction)
    }

    func dismissResult() {
        if let resultWindow, let toolbarWindow {
            resultWindow.removeChildWindow(toolbarWindow)
        }
        toolbarWindow?.orderOut(nil)
        resultWindow?.orderOut(nil)
        toolbarWindow = nil
        resultWindow = nil
        activeEditor = nil
        activeCaptureScreenFrame = nil
        toolbarLayout = nil
        editorObservation?.cancel()
        editorObservation = nil
        if sessionPhase == .editing {
            sessionPhase = .idle
            activeSessionID = nil
        }
    }

    func saveWindow() -> NSWindow? {
        resultWindow
    }

    func currentEditingPNGData() -> Data? {
        activeEditor?.finalPNGData()
    }

    @discardableResult
    func applyTranslatedScreenshot(_ translatedSelectionData: Data) -> Bool {
        guard let activeEditor else { return false }
        let outputRect = activeEditor.outputRect ?? CGRect(origin: .zero, size: activeEditor.canvasSize)
        let fullCanvasData = ScreenshotTranslationRenderer.composite(
            baseData: activeEditor.originalData,
            translatedSelectionData: translatedSelectionData,
            outputRect: outputRect,
            canvasSize: activeEditor.canvasSize
        ) ?? translatedSelectionData
        return activeEditor.replaceBaseImage(with: fullCanvasData)
    }
}
