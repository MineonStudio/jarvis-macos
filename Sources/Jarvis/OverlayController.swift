import AppKit
import SwiftUI

@MainActor
final class TranslationOverlayModel: ObservableObject {
    @Published var text = ""
    @Published var ocrText = ""
    @Published var targetLanguage = "中文"
    @Published var isTranslating = false
    @Published var isReviewingOCR = false
    @Published var errorMessage = ""
}

@MainActor
final class OverlayController {
    private var panel: TranslationOverlayPanel?
    private weak var parentWindow: NSWindow?
    let model = TranslationOverlayModel()
    private var retryAction: (() -> Void)?
    private var closeAction: (() -> Void)?
    private var translateOCRAction: ((String) -> Void)?

    func show(
        text: String,
        targetLanguage: String = "中文",
        anchorWindow: NSWindow? = nil,
        anchorFrame: CGRect? = nil,
        onRetry: @escaping () -> Void = {}
    ) {
        preparePanel()
        model.text = text
        model.ocrText = ""
        model.targetLanguage = targetLanguage
        model.isTranslating = false
        model.isReviewingOCR = false
        model.errorMessage = ""
        retryAction = onRetry
        translateOCRAction = nil
        closeAction = { [weak self] in self?.dismiss() }
        setPanelContentSize(height: 330)
        present(anchorWindow: anchorWindow, anchorFrame: anchorFrame)
    }

    func showLoading(
        targetLanguage: String,
        anchorWindow: NSWindow?,
        anchorFrame: CGRect?,
        onRetry: @escaping () -> Void
    ) {
        preparePanel()
        model.text = ""
        model.ocrText = ""
        model.targetLanguage = targetLanguage
        model.isTranslating = true
        model.isReviewingOCR = false
        model.errorMessage = ""
        retryAction = onRetry
        translateOCRAction = nil
        closeAction = { [weak self] in self?.dismiss() }
        setPanelContentSize(height: 330)
        present(anchorWindow: anchorWindow, anchorFrame: anchorFrame)
    }

    func showOCRReview(
        text: String,
        targetLanguage: String,
        anchorWindow: NSWindow?,
        anchorFrame: CGRect?,
        onCancel: @escaping () -> Void,
        onTranslate: @escaping (String) -> Void
    ) {
        preparePanel()
        model.text = ""
        model.ocrText = text
        model.targetLanguage = targetLanguage
        model.isTranslating = false
        model.isReviewingOCR = true
        model.errorMessage = ""
        retryAction = nil
        closeAction = onCancel
        translateOCRAction = onTranslate
        setPanelContentSize(height: 410)
        present(anchorWindow: anchorWindow, anchorFrame: anchorFrame)
    }

    func showError(
        message: String,
        targetLanguage: String,
        anchorWindow: NSWindow?,
        anchorFrame: CGRect?,
        onRetry: @escaping () -> Void
    ) {
        preparePanel()
        model.text = ""
        model.ocrText = ""
        model.targetLanguage = targetLanguage
        model.isTranslating = false
        model.isReviewingOCR = false
        model.errorMessage = message
        retryAction = onRetry
        translateOCRAction = nil
        closeAction = { [weak self] in self?.dismiss() }
        setPanelContentSize(height: 330)
        present(anchorWindow: anchorWindow, anchorFrame: anchorFrame)
    }

    func dismiss() {
        if let parentWindow, let panel {
            parentWindow.removeChildWindow(panel)
        }
        panel?.orderOut(nil)
        panel = nil
        parentWindow = nil
        retryAction = nil
        closeAction = nil
        translateOCRAction = nil
    }

    private func preparePanel() {
        guard panel == nil else { return }

        let newPanel = TranslationOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 330),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.onClose = { [weak self] in self?.closeAction?() }
        newPanel.level = .floating
        newPanel.isMovableByWindowBackground = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.titleVisibility = .hidden
        newPanel.titlebarAppearsTransparent = true
        newPanel.isReleasedWhenClosed = false
        newPanel.contentView = NSHostingView(
            rootView: FloatingTranslationView(
                model: model,
                onClose: { [weak self] in self?.closeAction?() },
                onRetry: { [weak self] in self?.retryAction?() },
                onTranslateOCR: { [weak self] text in self?.translateOCRAction?(text) }
            )
        )
        panel = newPanel
    }

    private func setPanelContentSize(height: CGFloat) {
        panel?.setContentSize(NSSize(width: 420, height: height))
    }

    private func present(anchorWindow: NSWindow?, anchorFrame: CGRect?) {
        guard let panel else { return }

        if parentWindow !== anchorWindow {
            if let parentWindow {
                parentWindow.removeChildWindow(panel)
            }
            parentWindow = anchorWindow
            if let anchorWindow {
                anchorWindow.addChildWindow(panel, ordered: .above)
                panel.level = anchorWindow.level
            } else {
                panel.level = .floating
            }
        }

        position(panel, near: anchorFrame)
        panel.makeKeyAndOrderFront(nil)
    }

    private func position(_ panel: NSPanel, near anchorFrame: CGRect?) {
        let screen = anchorFrame.flatMap { frame in
            NSScreen.screens.first { $0.frame.intersects(frame) }
        } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = panel.frame.size
        let reference = anchorFrame ?? visibleFrame
        let rightX = reference.maxX + 16
        let leftX = reference.minX - size.width - 16
        let x = rightX + size.width <= visibleFrame.maxX
            ? rightX
            : max(visibleFrame.minX + 16, leftX)
        let y = min(
            max(reference.maxY - size.height, visibleFrame.minY + 16),
            visibleFrame.maxY - size.height - 16
        )
        panel.setFrameOrigin(NSPoint(
            x: max(visibleFrame.minX + 16, x),
            y: max(visibleFrame.minY + 16, y)
        ))
    }
}

private final class TranslationOverlayPanel: NSPanel {
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performClose(_ sender: Any?) {
        onClose?()
    }
}
