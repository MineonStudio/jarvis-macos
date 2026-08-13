import AppKit
import Combine
import SwiftUI

enum ScreenshotAction {
    case saveRequested
    case confirmRequested
    case save(Data)
    case confirm(Data)
    case pin(Data)
    case cancel
    case tool(ScreenshotTool)
    case undo
    case redo
    case delete
    case duplicate
    case translateRequested(Data)
}

struct ScreenshotEditingSession: Sendable {
    let id: UUID
    let frozenScreen: ScreenshotCapture
    let selectionRect: CGRect
    let initialCapture: ScreenshotCapture

    var selectionFrame: CGRect { initialCapture.screenFrame }
}

enum ScreenshotTool: CaseIterable {
    case arrow
    case mosaic
    case text

    var icon: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .mosaic: return "checkerboard.rectangle"
        case .text: return "textformat"
        }
    }

    var title: String {
        switch self {
        case .arrow: return "箭头"
        case .mosaic: return "马赛克"
        case .text: return "文字"
        }
    }
}

@MainActor
final class ScreenshotToolbarLayoutModel: ObservableObject {
    @Published var width: CGFloat

    init(width: CGFloat) {
        self.width = width
    }
}

@MainActor
final class ScreenshotTranslationProgress: ObservableObject {
    @Published var isTranslating = false
}

@MainActor
final class ScreenshotCaptureController {
    private let screenshotService = ScreenshotService()
    let translationProgress = ScreenshotTranslationProgress()
    private var selectionWindows: [SelectionOverlayWindow] = []
    private var resultWindow: NSPanel?
    private var toolbarWindow: NSPanel?
    private var activeEditor: ScreenshotEditorModel?
    private var editorObservation: AnyCancellable?
    private var toolbarLayout: ScreenshotToolbarLayoutModel?
    private var selectionCompletionDelivered = false
    private var pinNextSelectionResult = false
    private var pinnedItems: [UUID: PinnedScreenshotItem] = [:]
    private var selectedPinnedID: UUID?
    private var activeCaptureScreenFrame: CGRect?
    private var previousFrontmostApplication: NSRunningApplication?
    private(set) var sessionPhase: ScreenshotSessionPhase = .idle
    private var activeSessionID: UUID?

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
                let frozenScreens = try await self.screenshotService.captureFullScreens(
                    screenFrames: NSScreen.screens.map(\.frame)
                )
                presentSelection(
                    frozenScreens: frozenScreens,
                    sessionID: sessionID,
                    completion: completion
                )
            } catch {
                guard self.activeSessionID == sessionID else { return }
                self.activeSessionID = nil
                self.sessionPhase = .idle
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
                  let frozenImage = NSImage(data: frozenScreen.data) else {
                continue
            }

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
                windowCandidates: windowCandidatesByScreen.first(where: { $0.frame == screen.frame })?.candidates ?? []
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

        let imagePanel: NSPanel
        let cancelEditing: () -> Void = { [weak self] in
            guard let self else { return }
            self.dismissResult()
            self.restorePreviousApplication()
            onAction(.cancel)
        }
        let quickCopyAndClose: () -> Void = { [weak self, weak editor] in
            guard let self, let editor else { return }
            // Close the floating editor immediately, then render the current
            // annotated image on the next main-actor turn just like the
            // toolbar's confirm action.
            self.dismissResult()
            Task { @MainActor in
                let data = editor.finalPNGData()
                onAction(.confirm(data))
            }
        }
        let pasteToScreen: () -> Void = { [weak self, weak editor] in
            guard let self, let editor else { return }
            let frame = editor.selectionFrame(on: capture.screenFrame) ?? capture.screenFrame
            self.pinScreenshot(
                editor: editor,
                frame: frame,
                onAction: onAction
            )
        }
        if let selectionWindow = selectionWindows.first(where: { $0.frame == capture.screenFrame }) {
            for otherWindow in selectionWindows where otherWindow !== selectionWindow {
                otherWindow.orderOut(nil)
            }
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
                contentRect: capture.screenFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            screenshotPanel.onDoubleClick = quickCopyAndClose
            screenshotPanel.onMiddleClick = pasteToScreen
            screenshotPanel.onEscape = cancelEditing
            imagePanel = screenshotPanel
        }
        // Keep the frozen editing surface above the Dock and other desktop UI.
        // A floating panel is below the Dock's window level on macOS.
        imagePanel.level = .screenSaver
        imagePanel.backgroundColor = .clear
        imagePanel.isOpaque = false
        imagePanel.hasShadow = false
        // Window movement is handled explicitly by ScreenshotCanvasView when
        // no annotation tool is active. This prevents drawing gestures from
        // being interpreted as window drags.
        imagePanel.isMovableByWindowBackground = false
        imagePanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        imagePanel.hidesOnDeactivate = false
        imagePanel.isReleasedWhenClosed = false
        let canvasHostingView = ScreenshotCanvasHostingView(
            rootView: ScreenshotCanvasView(
                image: image,
            editor: editor,
            interactive: true
            ),
            editor: editor,
            onDoubleClick: quickCopyAndClose,
            onMiddleClick: pasteToScreen,
            onEscape: cancelEditing
        )
        canvasHostingView.frame = NSRect(origin: .zero, size: capture.screenFrame.size)
        canvasHostingView.autoresizingMask = NSView.AutoresizingMask(arrayLiteral: .width, .height)
        imagePanel.contentView = canvasHostingView
        imagePanel.makeFirstResponder(canvasHostingView)

        let toolbarFrame = toolbarFrame(for: session.selectionFrame, height: 70, width: ScreenshotToolbar.preferredWidth(for: nil))
        let toolbarLayout = ScreenshotToolbarLayoutModel(width: toolbarFrame.width)
        let toolbarPanel = NSPanel(
            contentRect: toolbarFrame,
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
                editor: editor,
                layout: toolbarLayout,
                translationProgress: translationProgress,
                onAction: { [weak self] action in
                switch action {
                case .saveRequested:
                    Task { @MainActor in
                        let data = editor.finalPNGData()
                        onAction(.save(data))
                    }
                case .confirmRequested:
                    self?.dismissResult()
                    Task { @MainActor in
                        let data = editor.finalPNGData()
                        onAction(.confirm(data))
                    }
                case .save(let data):
                    onAction(.save(data))
                case .confirm(let data):
                    onAction(.confirm(data))
                case .pin:
                    break
                case .cancel:
                    self?.dismissResult()
                    self?.restorePreviousApplication()
                    onAction(.cancel)
                case .tool(let tool):
                    self?.resizeToolbar(for: editor, on: capture.screenFrame)
                    onAction(.tool(tool))
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
                case .translateRequested:
                    onAction(action)
                }
            })
        )
        toolbarHostingView.autoresizingMask = NSView.AutoresizingMask(arrayLiteral: .width, .height)
        toolbarPanel.contentView = toolbarHostingView
        toolbarHostingView.frame = NSRect(origin: .zero, size: toolbarFrame.size)

        imagePanel.addChildWindow(toolbarPanel, ordered: .above)
        resultWindow = imagePanel
        toolbarWindow = toolbarPanel
        self.toolbarLayout = toolbarLayout
        imagePanel.makeKeyAndOrderFront(nil)
        toolbarPanel.orderFrontRegardless()

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
                self.pinScreenshot(editor: editor, frame: frame, onAction: onAction)
            }
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

    func translationAnchorFrame() -> CGRect? {
        guard let activeEditor, let activeCaptureScreenFrame else { return nil }
        return activeEditor.selectionFrame(on: activeCaptureScreenFrame) ?? activeCaptureScreenFrame
    }

    private func pinScreenshot(
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
            self.createPinnedScreenshot(data: data, frame: frame, onAction: onAction)
            self.sessionPhase = .idle
            self.activeSessionID = nil
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
            self.destroyPinnedScreenshot(item)
        }
        item.window.onDidResignKey = { [weak self, weak item] in
            guard let self, let item,
                  self.selectedPinnedID == item.id else { return }
            // The toolbar is a child window. Clicking a toolbar control can
            // briefly move key-window status to it, so keep the pin selected.
            guard item.toolbarWindow?.isKeyWindow != true else { return }
            self.deselectPinnedScreenshot(item)
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
                self.selectPinnedScreenshot(item)
            },
            onEscape: { [weak self, weak item] in
                guard let self, let item else { return }
                self.destroyPinnedScreenshot(item)
            }
        )
        let containerView = PinnedScreenshotContainerView(
            frame: NSRect(origin: .zero, size: item.window.frame.size),
            imageSize: image.size,
            contentInset: item.contentInset,
            editor: item.editor,
            onActivate: { [weak self, weak item] in
                guard let self, let item else { return }
                self.selectPinnedScreenshot(item)
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
        showPinnedToolbar(for: item)
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
        // The Snipaste-style shadow is rendered by the transparent inset
        // container so it follows the image's rounded outline.
        item.window.hasShadow = false
    }

    private func showPinnedToolbar(for item: PinnedScreenshotItem) {
        guard item.toolbarWindow == nil else {
            resizePinnedToolbar(for: item)
            return
        }

        let frame = toolbarFrame(
            for: item.imageFrame,
            height: 70,
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
                translationProgress: translationProgress,
                onAction: { [weak self, weak item] action in
                    guard let self, let item else { return }
                    self.handlePinnedToolbarAction(action, for: item)
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
            height: item.editor.secondaryBarVisible ? 111 : 70,
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
            let editor = item.editor
            let onAction = item.onAction
            destroyPinnedScreenshot(item)
            Task { @MainActor in
                let data = editor.finalPNGData()
                onAction?(.save(data))
            }
        case .confirmRequested:
            let editor = item.editor
            let onAction = item.onAction
            destroyPinnedScreenshot(item)
            Task { @MainActor in
                let data = editor.finalPNGData()
                onAction?(.confirm(data))
            }
        case .save(let data):
            let onAction = item.onAction
            destroyPinnedScreenshot(item)
            onAction?(.save(data))
        case .confirm(let data):
            let onAction = item.onAction
            destroyPinnedScreenshot(item)
            onAction?(.confirm(data))
        case .cancel:
            destroyPinnedScreenshot(item)
        case .tool(let tool):
            resizePinnedToolbar(for: item)
            item.onAction?(.tool(tool))
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
        case .translateRequested(let data):
            item.onAction?(.translateRequested(data))
        case .pin:
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

    private func toolbarFrame(for imageFrame: CGRect, height toolbarHeight: CGFloat, width requestedWidth: CGFloat) -> NSRect {
        let toolbarGap: CGFloat = 16
        let screen = NSScreen.screens.first { $0.frame.intersects(imageFrame) }
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let availableWidth = max(1, visibleFrame.width - 24)
        let toolbarWidth = min(requestedWidth, availableWidth)
        let fitsBelow = imageFrame.minY - toolbarHeight - toolbarGap >= visibleFrame.minY
        let y = fitsBelow
            ? imageFrame.minY - toolbarHeight - toolbarGap
            : imageFrame.maxY + toolbarGap
        let x = min(
            max(imageFrame.midX - toolbarWidth / 2, visibleFrame.minX + 12),
            visibleFrame.maxX - toolbarWidth - 12
        )

        return NSRect(
            x: x,
            y: y,
            width: toolbarWidth,
            height: toolbarHeight
        )
    }

    private func resizeToolbar(for editor: ScreenshotEditorModel, on screenFrame: CGRect) {
        guard let toolbarWindow else { return }
        let imageFrame = editor.selectionFrame(on: screenFrame) ?? screenFrame
        let frame = toolbarFrame(
            for: imageFrame,
            height: editor.secondaryBarVisible ? 111 : 70,
            width: ScreenshotToolbar.preferredWidth(for: editor.selectedTool, mosaicMode: editor.mosaicMode)
        )
        toolbarWindow.setFrame(frame, display: true, animate: false)
        toolbarWindow.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        toolbarLayout?.width = frame.width
    }

    private func finishSelection(
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

    private func cancelSelection(
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

    private func dismissSelectionWindows() {
        selectionWindows.forEach { $0.orderOut(nil) }
        selectionWindows.removeAll()
        if NSCursor.current == NSCursor.crosshair {
            NSCursor.pop()
        }
    }

    private func restorePreviousApplication() {
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

final class SelectionOverlayWindow: NSPanel {
    var onDoubleClick: (() -> Void)?
    var onMiddleClick: (() -> Void)?
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            onEscape?()
            return
        }
        if event.type == .leftMouseDown,
           event.clickCount == 2,
           let onDoubleClick {
            onDoubleClick()
            return
        }
        if event.type == .otherMouseDown,
           event.buttonNumber == 2,
           let onMiddleClick {
            onMiddleClick()
            return
        }
        super.sendEvent(event)
    }
}

fileprivate struct WindowSelectionCandidate {
    let localRect: CGRect
    let ownerName: String
    let title: String
    let windowID: CGWindowID
}

private enum WindowSelectionDetector {
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

        let desktopTop = NSScreen.screens.map { $0.frame.maxY }.max() ?? screenFrame.maxY
        let screenBounds = CGRect(origin: .zero, size: screenFrame.size)
        let dockGlobalRect = dockRegion(for: screenFrame)
        var candidates: [WindowSelectionCandidate] = []
        var seenRects = Set<String>()
        var dockCandidate: WindowSelectionCandidate?

        // CGWindowListCopyWindowInfo is front-to-back. Keeping that order means
        // the first candidate containing the pointer is the topmost window.
        for info in windowInfoList {
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            // Desktop, wallpaper and the cursor use very large negative or
            // positive layers. Menubar, Dock and menu-extra windows are in the
            // small positive range and must remain eligible.
            guard layer >= 0, layer < 1_000 else { continue }

            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.01 else { continue }

            let ownerName = (info[kCGWindowOwnerName as String] as? String) ?? ""
            let normalizedOwnerName = ownerName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalizedOwnerName.isEmpty else { continue }

            let title = (info[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTitle = title?.lowercased() ?? ""
            // The localized Dock window title is not stable across macOS
            // versions. The owner name is the reliable discriminator; any
            // negative-layer Dock wallpaper entries were already filtered.
            let isDock = dockOwnerNames.contains(normalizedOwnerName)
            let isMenubar = normalizedTitle == "menubar"

            guard let boundsValue = info[kCGWindowBounds as String] as? NSDictionary,
                  let quartzBounds = CGRect(dictionaryRepresentation: boundsValue) else {
                continue
            }

            // The Dock reports a full-screen backing window. Its actual
            // selectable surface is the region outside NSScreen.visibleFrame.
            let globalRect = isDock
                ? dockGlobalRect
                : quartzBounds
            guard let globalRect else { continue }

            let localRect = localRect(
                for: globalRect,
                screenFrame: screenFrame,
                desktopTop: desktopTop,
                screenBounds: screenBounds
            )
            let minimumWidth: CGFloat = (layer > 0 || isMenubar) ? 18 : 80
            let minimumHeight: CGFloat = (layer > 0 || isMenubar) ? 10 : 60
            guard localRect.width >= minimumWidth, localRect.height >= minimumHeight else {
                continue
            }

            let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
            let rectKey = "\(windowID):\(Int(localRect.minX.rounded())):\(Int(localRect.minY.rounded())):\(Int(localRect.width.rounded())):\(Int(localRect.height.rounded()))"
            guard seenRects.insert(rectKey).inserted else { continue }

            let candidate = WindowSelectionCandidate(
                localRect: localRect,
                ownerName: ownerName,
                title: title.flatMap { $0.isEmpty ? nil : $0 } ?? ownerName,
                windowID: windowID
            )
            if isDock {
                dockCandidate = candidate
            } else {
                candidates.append(candidate)
            }
        }

        // Dock icons are drawn by the Dock process and are not individual
        // CGWindow entries. Add approximate icon slots using the user's actual
        // Dock orientation, tile size and persistent app count. The Dock bar
        // itself remains as a fallback for gaps between icon slots.
        if let dockCandidate {
            let iconCandidates = dockIconCandidates(
                in: dockCandidate.localRect
            )
            candidates.append(contentsOf: iconCandidates)
            candidates.append(dockCandidate)
        } else if let dockGlobalRect {
            let localDockRect = localRect(
                for: dockGlobalRect,
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

    private static func localRect(
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
        if left > bottom, left >= right { return "left" }
        if right > bottom, right > left { return "right" }
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
            for index in 0..<iconCount {
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
            for index in 0..<iconCount {
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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            onEscape?()
            return
        }
        super.sendEvent(event)
    }

    func windowDidResignKey(_ notification: Notification) {
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
            updateShadowAppearance()
        }
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
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // A pin can float above an inactive app. Accept the first click so the
    // entire pin activates immediately instead of requiring a second click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
              let initialMouseLocation else {
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
        if isSelected {
            // Use an even, zero-offset halo rather than a heavy downward drop
            // shadow. Inactive pins intentionally have no shadow at all.
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

        if isSelected {
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
        self.imageSize = image.size
        self.editor = ScreenshotEditorModel(
            image: image,
            data: data,
            outputData: data,
            canvasSize: image.size,
            outputRect: CGRect(origin: .zero, size: image.size)
        )
        self.window = PinnedScreenshotWindow(
            contentRect: frame.insetBy(dx: -contentInset, dy: -contentInset),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
    }
}

final class ScreenshotImagePanel: NSPanel {
    var onDoubleClick: (() -> Void)?
    var onMiddleClick: (() -> Void)?
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            onEscape?()
            return
        }
        if event.type == .leftMouseDown,
           event.clickCount == 2,
           let onDoubleClick {
            onDoubleClick()
            return
        }
        if event.type == .otherMouseDown,
           event.buttonNumber == 2,
           let onMiddleClick {
            onMiddleClick()
            return
        }
        super.sendEvent(event)
    }
}

final class ScreenshotCanvasHostingView: NSHostingView<ScreenshotCanvasView> {
    private let editor: ScreenshotEditorModel
    private let allowsSelectionTransform: Bool
    private let onActivate: (() -> Void)?
    private let onDoubleClick: (() -> Void)?
    private let onMiddleClick: (() -> Void)?
    private let onEscape: (() -> Void)?
    private enum ResizeHandle {
        case topLeading
        case top
        case topTrailing
        case trailing
        case bottomTrailing
        case bottom
        case bottomLeading
        case leading
    }

    private enum SelectionInteraction {
        case move
        case resize(ResizeHandle)
    }

    private var selectionInteraction: SelectionInteraction?
    private var selectionStartRect: CGRect?
    private var selectionStartPoint: CGPoint?
    private var initialWindowOrigin: NSPoint?
    private var initialMouseLocation: NSPoint?

    init(
        rootView: ScreenshotCanvasView,
        editor: ScreenshotEditorModel,
        allowsSelectionTransform: Bool = true,
        onActivate: (() -> Void)? = nil,
        onDoubleClick: (() -> Void)? = nil,
        onMiddleClick: (() -> Void)? = nil,
        onEscape: (() -> Void)? = nil
    ) {
        self.editor = editor
        self.allowsSelectionTransform = allowsSelectionTransform
        self.onActivate = onActivate
        self.onDoubleClick = onDoubleClick
        self.onMiddleClick = onMiddleClick
        self.onEscape = onEscape
        super.init(rootView: rootView)
    }

    @MainActor
    required init(rootView: ScreenshotCanvasView) {
        self.editor = rootView.editor
        self.allowsSelectionTransform = true
        self.onActivate = nil
        self.onDoubleClick = nil
        self.onMiddleClick = nil
        self.onEscape = nil
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, let onEscape {
            onEscape()
            return
        }

        let commandPressed = event.modifierFlags.contains(.command)
        let shiftPressed = event.modifierFlags.contains(.shift)
        let characters = event.charactersIgnoringModifiers?.lowercased()

        if editor.selectedAnnotationID != nil,
           event.keyCode == 51 || event.keyCode == 117 {
            editor.deleteSelectedAnnotation()
            return
        }

        if commandPressed, characters == "d" {
            editor.duplicateSelectedAnnotation()
            return
        }

        if commandPressed, characters == "z" {
            if shiftPressed {
                editor.redo()
            } else {
                editor.undo()
            }
            return
        }

        if event.keyCode == 53, editor.selectedAnnotationID != nil {
            editor.clearSelection()
            return
        }

        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if event.type == .otherMouseDown, event.buttonNumber == 2 {
            onMiddleClick?()
            return
        }

        onActivate?()

        if allowsSelectionTransform,
           editor.selectedTool == nil,
           let selectionRect = editor.selectionRect {
            let canvasPoint = canvasPoint(for: event)
            if let interaction = selectionInteraction(at: canvasPoint, in: selectionRect) {
                selectionInteraction = interaction
                selectionStartRect = selectionRect
                selectionStartPoint = canvasPoint
                return
            }
        }

        guard editor.selectedTool == nil,
              (allowsSelectionTransform ? editor.editingRect == nil : true),
              let window else {
            super.mouseDown(with: event)
            return
        }
        initialWindowOrigin = window.frame.origin
        initialMouseLocation = NSEvent.mouseLocation
    }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 {
            onMiddleClick?()
            return
        }
        super.otherMouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if let selectionInteraction,
           let selectionStartRect,
           let selectionStartPoint {
            let currentPoint = canvasPoint(for: event)
            let delta = CGSize(
                width: currentPoint.x - selectionStartPoint.x,
                height: currentPoint.y - selectionStartPoint.y
            )
            let updatedRect: CGRect
            switch selectionInteraction {
            case .move:
                updatedRect = movedRect(selectionStartRect, by: delta)
            case .resize(let handle):
                updatedRect = resizedRect(selectionStartRect, handle: handle, by: delta)
            }
            editor.updateSelectionRect(updatedRect)
            return
        }

        guard editor.selectedTool == nil,
              editor.editingRect == nil,
              let window,
              let initialWindowOrigin,
              let initialMouseLocation else {
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
        if selectionInteraction != nil {
            selectionInteraction = nil
            selectionStartRect = nil
            selectionStartPoint = nil
            return
        }

        guard editor.selectedTool == nil else {
            super.mouseUp(with: event)
            return
        }
        initialWindowOrigin = nil
        initialMouseLocation = nil
    }

    private func canvasPoint(for event: NSEvent) -> CGPoint {
        let localPoint = convert(event.locationInWindow, from: nil)
        // NSHostingView is flipped, so its local event coordinates already
        // use SwiftUI's top-left origin. Inverting Y here made vertical
        // selection movement feel backwards while horizontal movement stayed
        // correct.
        return CGPoint(x: localPoint.x, y: localPoint.y)
    }

    private func selectionInteraction(
        at point: CGPoint,
        in rect: CGRect
    ) -> SelectionInteraction? {
        let radius: CGFloat = 14
        let nearLeft = abs(point.x - rect.minX) <= radius
        let nearRight = abs(point.x - rect.maxX) <= radius
        let nearTop = abs(point.y - rect.minY) <= radius
        let nearBottom = abs(point.y - rect.maxY) <= radius

        if nearLeft, nearTop { return .resize(.topLeading) }
        if nearTop, nearRight { return .resize(.topTrailing) }
        if nearLeft, nearBottom { return .resize(.bottomLeading) }
        if nearRight, nearBottom { return .resize(.bottomTrailing) }
        if nearTop, point.x >= rect.minX, point.x <= rect.maxX { return .resize(.top) }
        if nearRight, point.y >= rect.minY, point.y <= rect.maxY { return .resize(.trailing) }
        if nearBottom, point.x >= rect.minX, point.x <= rect.maxX { return .resize(.bottom) }
        if nearLeft, point.y >= rect.minY, point.y <= rect.maxY { return .resize(.leading) }
        if rect.contains(point) { return .move }
        return nil
    }

    private func movedRect(_ rect: CGRect, by delta: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: self.bounds.size)
        let x = min(max(rect.minX + delta.width, bounds.minX), bounds.maxX - rect.width)
        let y = min(max(rect.minY + delta.height, bounds.minY), bounds.maxY - rect.height)
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    private func resizedRect(
        _ rect: CGRect,
        handle: ResizeHandle,
        by delta: CGSize
    ) -> CGRect {
        let minimum: CGFloat = 24
        let bounds = CGRect(origin: .zero, size: self.bounds.size)
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY

        switch handle {
        case .topLeading:
            minX = clamp(rect.minX + delta.width, lower: bounds.minX, upper: rect.maxX - minimum)
            minY = clamp(rect.minY + delta.height, lower: bounds.minY, upper: rect.maxY - minimum)
        case .top:
            minY = clamp(rect.minY + delta.height, lower: bounds.minY, upper: rect.maxY - minimum)
        case .topTrailing:
            maxX = clamp(rect.maxX + delta.width, lower: rect.minX + minimum, upper: bounds.maxX)
            minY = clamp(rect.minY + delta.height, lower: bounds.minY, upper: rect.maxY - minimum)
        case .trailing:
            maxX = clamp(rect.maxX + delta.width, lower: rect.minX + minimum, upper: bounds.maxX)
        case .bottomTrailing:
            maxX = clamp(rect.maxX + delta.width, lower: rect.minX + minimum, upper: bounds.maxX)
            maxY = clamp(rect.maxY + delta.height, lower: rect.minY + minimum, upper: bounds.maxY)
        case .bottom:
            maxY = clamp(rect.maxY + delta.height, lower: rect.minY + minimum, upper: bounds.maxY)
        case .bottomLeading:
            minX = clamp(rect.minX + delta.width, lower: bounds.minX, upper: rect.maxX - minimum)
            maxY = clamp(rect.maxY + delta.height, lower: rect.minY + minimum, upper: bounds.maxY)
        case .leading:
            minX = clamp(rect.minX + delta.width, lower: bounds.minX, upper: rect.maxX - minimum)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}

final class SelectionOverlayView: NSView {
    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var onPin: ((CGRect) -> Void)?

    private let frozenImage: NSImage
    private let frozenCGImage: CGImage?
    private let windowCandidates: [WindowSelectionCandidate]
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var movedSelectionRect: CGRect?
    private var moveAnchor: CGPoint?
    private var hoveredWindowCandidate: WindowSelectionCandidate?
    private var windowCandidateAtMouseDown: WindowSelectionCandidate?
    private var didDragSelection = false
    private var spacePressed = false

    fileprivate init(
        frame frameRect: NSRect,
        frozenImage: NSImage,
        windowCandidates: [WindowSelectionCandidate]
    ) {
        self.frozenImage = frozenImage
        var proposedRect = NSRect(origin: .zero, size: frozenImage.size)
        self.frozenCGImage = frozenImage.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        )
        self.windowCandidates = windowCandidates
        super.init(frame: frameRect)
        updateTrackingArea()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    private var selectionTrackingArea: NSTrackingArea?

    private func updateTrackingArea() {
        if let selectionTrackingArea {
            removeTrackingArea(selectionTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        selectionTrackingArea = trackingArea
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTrackingArea()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else if event.keyCode == 49 {
            spacePressed = true
        } else {
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            spacePressed = false
        } else {
            super.keyUp(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        movedSelectionRect = nil
        moveAnchor = nil
        didDragSelection = false
        windowCandidateAtMouseDown = windowCandidate(at: startPoint)
        needsDisplay = true
    }

    func pinHoveredWindow() {
        let pointerCandidate: WindowSelectionCandidate?
        if let window {
            let screenPoint = NSEvent.mouseLocation
            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            let localPoint = convert(windowPoint, from: nil)
            pointerCandidate = windowCandidate(at: localPoint)
        } else {
            pointerCandidate = nil
        }
        guard let candidate = pointerCandidate ?? hoveredWindowCandidate else { return }
        resetPointerState()
        onPin?(candidate.localRect)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let startPoint,
           hypot(point.x - startPoint.x, point.y - startPoint.y) > 4 {
            didDragSelection = true
            hoveredWindowCandidate = nil
        }
        if spacePressed, let selectionRect {
            if moveAnchor == nil {
                movedSelectionRect = selectionRect
                moveAnchor = point
            } else if let moveAnchor, var movedSelectionRect {
                movedSelectionRect.origin.x += point.x - moveAnchor.x
                movedSelectionRect.origin.y += point.y - moveAnchor.y
                self.movedSelectionRect = clampedRect(movedSelectionRect)
                self.moveAnchor = point
            }
        } else {
            currentPoint = point
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !didDragSelection,
           !spacePressed,
           let windowCandidateAtMouseDown {
            resetPointerState()
            onFinish?(windowCandidateAtMouseDown.localRect)
            return
        }
        if spacePressed, let selectionRect, let moveAnchor {
            var movedSelectionRect = selectionRect
            movedSelectionRect.origin.x += point.x - moveAnchor.x
            movedSelectionRect.origin.y += point.y - moveAnchor.y
            self.movedSelectionRect = clampedRect(movedSelectionRect)
        } else {
            currentPoint = point
        }
        guard let selection = selectionRect else {
            resetPointerState()
            onCancel?()
            return
        }
        resetPointerState()
        onFinish?(selection)
    }

    override func mouseMoved(with event: NSEvent) {
        guard startPoint == nil, movedSelectionRect == nil, moveAnchor == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        let candidate = windowCandidate(at: point)
        if candidate?.windowID != hoveredWindowCandidate?.windowID {
            hoveredWindowCandidate = candidate
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.interpolationQuality = .high
        if let frozenCGImage {
            context.draw(frozenCGImage, in: bounds)
        } else {
            frozenImage.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        }
        context.setFillColor(NSColor.black.withAlphaComponent(0.58).cgColor)
        context.fill(bounds)

        if let selectionRect {
            context.saveGState()
            context.clip(to: selectionRect)
            if let frozenCGImage {
                context.draw(frozenCGImage, in: bounds)
            } else {
                frozenImage.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
            }
            context.restoreGState()

            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.95).cgColor)
            context.setLineWidth(2)
            context.stroke(selectionRect)

            drawDimensionLabel(in: selectionRect, context: context)
        } else if let hoveredWindowCandidate {
            context.saveGState()
            context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.08).cgColor)
            context.fill(hoveredWindowCandidate.localRect)
            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.95).cgColor)
            context.setLineWidth(2)
            context.setLineDash(phase: 0, lengths: [7, 4])
            context.stroke(hoveredWindowCandidate.localRect)
            context.restoreGState()

            drawWindowHint(for: hoveredWindowCandidate, context: context)
        }

        drawHint(in: bounds, context: context)
    }

    private var selectionRect: CGRect? {
        if let movedSelectionRect {
            return movedSelectionRect
        }
        guard let startPoint, let currentPoint else { return nil }
        return clampedRect(CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        ))
    }

    private func clampedRect(_ rect: CGRect) -> CGRect {
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        let x = min(max(rect.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(rect.minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func windowCandidate(at point: CGPoint?) -> WindowSelectionCandidate? {
        guard let point else { return nil }
        return windowCandidates.first(where: { $0.localRect.contains(point) })
    }

    private func resetPointerState() {
        startPoint = nil
        currentPoint = nil
        movedSelectionRect = nil
        moveAnchor = nil
        windowCandidateAtMouseDown = nil
        didDragSelection = false
    }

    private func drawWindowHint(
        for candidate: WindowSelectionCandidate,
        context: CGContext
    ) {
        let text = "窗口 · 单击自动选中"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let labelRect = CGRect(
            x: candidate.localRect.minX,
            y: min(
                bounds.maxY - size.height - 16,
                candidate.localRect.maxY + 8
            ),
            width: size.width + 16,
            height: size.height + 8
        )
        NSColor.systemBlue.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5).fill()
        text.draw(
            at: CGPoint(x: labelRect.minX + 8, y: labelRect.minY + 4),
            withAttributes: attributes
        )
    }

    private func drawHint(in bounds: CGRect, context: CGContext) {
        guard selectionRect == nil else { return }
        let text = hoveredWindowCandidate == nil
            ? "悬停窗口后单击自动选中  ·  拖动自定义框选  ·  ESC 取消"
            : "单击选中窗口  ·  拖动自定义框选  ·  ESC 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9)
        ]
        let size = text.size(withAttributes: attributes)
        let rect = CGRect(
            x: bounds.midX - size.width / 2 - 14,
            y: bounds.maxY - 70,
            width: size.width + 28,
            height: size.height + 14
        )
        NSColor.black.withAlphaComponent(0.52).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        text.draw(at: CGPoint(x: rect.minX + 14, y: rect.minY + 7), withAttributes: attributes)
    }

    private func drawDimensionLabel(in rect: CGRect, context: CGContext) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let labelRect = CGRect(
            x: rect.minX,
            y: max(8, rect.minY - size.height - 12),
            width: size.width + 16,
            height: size.height + 8
        )
        NSColor.systemBlue.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5).fill()
        text.draw(at: CGPoint(x: labelRect.minX + 8, y: labelRect.minY + 4), withAttributes: attributes)
    }
}

struct ScreenshotToolbar: View {
    static let baseWidth: CGFloat = 440

    static func preferredWidth(
        for tool: ScreenshotTool?,
        mosaicMode: ScreenshotMosaicMode = .rectangle
    ) -> CGFloat {
        switch tool {
        case .mosaic: return mosaicMode == .brush ? 520 : baseWidth
        case .text: return 520
        case .arrow: return 520
        default: return baseWidth
        }
    }

    @ObservedObject var editor: ScreenshotEditorModel
    @ObservedObject var layout: ScreenshotToolbarLayoutModel
    @ObservedObject var translationProgress: ScreenshotTranslationProgress
    let onAction: (ScreenshotAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                toolButton(.arrow)
                toolButton(.mosaic)
                toolButton(.text)

                toolbarDivider

                actionButton(icon: "arrow.uturn.backward", help: "撤销", enabled: editor.canUndo) {
                    onAction(.undo)
                }
                actionButton(icon: "arrow.uturn.forward", help: "重做", enabled: editor.canRedo) {
                    onAction(.redo)
                }

                toolbarDivider

                actionButton(
                    icon: "character.bubble",
                    help: translationProgress.isTranslating ? "翻译中…" : "自动翻译截图",
                    enabled: !translationProgress.isTranslating
                ) {
                    onAction(.translateRequested(editor.finalPNGData()))
                }

                actionButton(icon: "square.and.arrow.down", help: "另存为") {
                    onAction(.saveRequested)
                }
                actionButton(icon: "xmark", help: "取消") {
                    onAction(.cancel)
                }
                actionButton(icon: "checkmark", help: "确认") {
                    onAction(.confirmRequested)
                }
            }
            .frame(height: 64)

            if editor.secondaryBarVisible {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 1)
                    .padding(.horizontal, 5)

                secondaryControl
                    .frame(height: 40)
            }
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 6)
        .frame(
            width: layout.width,
            height: editor.secondaryBarVisible ? 111 : 70
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .jarvisGlass(cornerRadius: 16)
    }

    private func toolButton(_ tool: ScreenshotTool) -> some View {
        Button {
            editor.selectTool(editor.selectedTool == tool ? nil : tool)
            onAction(.tool(tool))
        } label: {
            Group {
                if tool == .text {
                    Text("T")
                        .font(.system(size: 24, weight: .regular, design: .serif))
                } else if tool == .mosaic {
                    MosaicToolIcon(
                        color: editor.selectedTool == tool ? Color.primary : Color.secondary
                    )
                } else {
                    Image(systemName: tool.icon)
                        .font(.system(size: 21, weight: .medium))
                }
            }
            .foregroundStyle(editor.selectedTool == tool ? Color.primary : Color.secondary)
            .frame(width: 24, height: 24)
            .frame(width: 42, height: 42)
            .jarvisGlass(
                tint: editor.selectedTool == tool ? .accentColor : nil,
                cornerRadius: 8,
                interactive: false
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tool.title)
    }

    private struct MosaicToolIcon: View {
        let color: Color

        var body: some View {
            ZStack {
                VStack(spacing: 2) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 2) {
                            ForEach(0..<2, id: \.self) { column in
                                Rectangle()
                                    .fill((row + column).isMultiple(of: 2) ? color : .clear)
                                    .frame(width: 9, height: 9)
                            }
                        }
                    }
                }

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(color, lineWidth: 1.5)
            }
            .frame(width: 24, height: 24)
        }
    }

    @ViewBuilder
    private var secondaryControl: some View {
        if editor.selectedTool == .arrow {
            arrowStyleControl
        } else if editor.selectedTool == .mosaic {
            mosaicStyleControl
        } else if editor.selectedTool == .text {
            textStyleControl
        }
    }

    private var arrowStyleControl: some View {
        HStack(spacing: 9) {
            Text("颜色")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.secondary)

            colorButtons(selected: editor.arrowColor) { color in
                editor.arrowColor = color
            }

            Rectangle()
                .fill(Color.primary.opacity(0.16))
                .frame(width: 1, height: 22)

            Text("粗细")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.secondary)

            Slider(value: $editor.arrowLineWidth, in: 2...12, step: 1)
                .frame(width: 82)

            Text("\(Int(editor.arrowLineWidth))")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .frame(width: 18, alignment: .leading)

            Menu {
                ForEach(ScreenshotArrowHeadStyle.allCases) { style in
                    Button {
                        editor.arrowHeadStyle = style
                    } label: {
                        Label(style.title, systemImage: style == .none ? "line.diagonal" : "arrow.up.right")
                    }
                }
            } label: {
                Label(editor.arrowHeadStyle.title, systemImage: "arrow.up.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("箭头样式")
        }
        .padding(.horizontal, 6)
    }

    private var mosaicStyleControl: some View {
        HStack(spacing: 8) {
            mosaicModePicker

            Rectangle()
                .fill(Color.primary.opacity(0.16))
                .frame(width: 1, height: 22)

            mosaicEffectPicker

            if editor.mosaicMode == .brush {
                Rectangle()
                    .fill(Color.primary.opacity(0.16))
                    .frame(width: 1, height: 22)
                mosaicBrushSizeControl
            }
        }
        .padding(.horizontal, 6)
        .help("支持涂抹、框选，并调整马赛克效果")
    }

    private var mosaicModePicker: some View {
        HStack(spacing: 2) {
            ForEach(ScreenshotMosaicMode.allCases) { mode in
                mosaicOptionButton(
                    icon: mode.icon,
                    title: mode.title,
                    selected: editor.mosaicMode == mode
                ) {
                    editor.mosaicMode = mode
                }
            }
        }
        .padding(2)
        .jarvisGlass(cornerRadius: 8, interactive: false)
    }

    private var mosaicEffectPicker: some View {
        HStack(spacing: 2) {
            ForEach(ScreenshotMosaicStyle.allCases) { style in
                mosaicOptionButton(
                    icon: style.icon,
                    title: style.title,
                    selected: editor.mosaicStyle == style
                ) {
                    editor.mosaicStyle = style
                }
            }
        }
        .padding(2)
        .jarvisGlass(cornerRadius: 8, interactive: false)
    }

    private var mosaicBrushSizeControl: some View {
        HStack(spacing: 6) {
            Text("笔触")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.secondary)

            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(Color.secondary)

            Slider(value: $editor.mosaicBrushSize, in: 8...72, step: 2)
                .frame(width: 76)

            Image(systemName: "circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color.secondary)
        }
    }

    private func mosaicOptionButton(
        icon: String,
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 7)
            .frame(height: 26)
            .jarvisGlass(
                tint: selected ? .accentColor : nil,
                cornerRadius: 6,
                interactive: false
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var textStyleControl: some View {
        HStack(spacing: 9) {
            Text("字号")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.secondary)

            Slider(value: $editor.textFontSize, in: 12...48, step: 1)
                .frame(width: 86)

            Text("\(Int(editor.textFontSize))")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .frame(width: 22, alignment: .leading)

            Rectangle()
                .fill(Color.primary.opacity(0.16))
                .frame(width: 1, height: 22)

            HStack(spacing: 2) {
                textToggleButton(icon: "bold", selected: editor.textBold, help: "粗体") {
                    editor.textBold.toggle()
                }
                textToggleButton(icon: "italic", selected: editor.textItalic, help: "斜体") {
                    editor.textItalic.toggle()
                }
                textToggleButton(icon: "strikethrough", selected: editor.textStrikethrough, help: "删除线") {
                    editor.textStrikethrough.toggle()
                }
            }
            .padding(2)
            .jarvisGlass(cornerRadius: 8, interactive: false)

            Rectangle()
                .fill(Color.primary.opacity(0.16))
                .frame(width: 1, height: 22)

            HStack(spacing: 6) {
                ForEach(ScreenshotTextColor.allCases) { color in
                    Button {
                        editor.textColor = color
                    } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 16, height: 16)
                            .overlay {
                                Circle()
                                    .stroke(
                                        editor.textColor == color ? Color.accentColor : Color.black.opacity(0.2),
                                        lineWidth: editor.textColor == color ? 2 : 1
                                    )
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("文字颜色")
                }
            }
        }
        .padding(.horizontal, 6)
        .help("文字样式")
    }

    private func textToggleButton(
        icon: String,
        selected: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .frame(width: 28, height: 28)
                .jarvisGlass(
                    tint: selected ? .accentColor : nil,
                    cornerRadius: 6,
                    interactive: false
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func colorButtons(
        selected: ScreenshotTextColor,
        action: @escaping (ScreenshotTextColor) -> Void
    ) -> some View {
        HStack(spacing: 5) {
            ForEach(ScreenshotTextColor.allCases) { color in
                Button {
                    action(color)
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 15, height: 15)
                        .overlay {
                            Circle()
                                .stroke(
                                        selected == color ? Color.accentColor : Color.primary.opacity(0.2),
                                    lineWidth: selected == color ? 2 : 1
                                )
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actionButton(
        icon: String,
        help: String,
        selected: Bool = false,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(enabled ? (selected ? Color.primary : Color.secondary) : Color.secondary.opacity(0.35))
                .frame(width: 24, height: 24)
                .frame(width: 42, height: 42)
                .jarvisGlass(
                    tint: selected ? .accentColor : nil,
                    cornerRadius: 8,
                    interactive: false
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.22))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 8)
    }
}
