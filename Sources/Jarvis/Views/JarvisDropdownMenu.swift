import AppKit
import SwiftUI

// MARK: - 下拉菜单

/// 工具栏上的下拉筛选控件。
///
/// 这块原本长在 `Theme.swift` 里，占了那个文件的小一半：它自带一个 NSPanel、
/// 外部点击监听和屏幕边缘定位，是个完整的组件，而不是主题的一部分。
struct JarvisDropdownOption: Identifiable, Equatable {
    let id: String
    let title: String
}

private enum JarvisDropdownMetrics {
    static let minimumControlWidth: CGFloat = 96
    static let maximumControlWidth: CGFloat = 320
    static let optionSpacing: CGFloat = JarvisMetrics.segmentedItemSpacing
    static let triggerGap: CGFloat = JarvisMetrics.segmentedControlPadding
    static let menuEdgePadding: CGFloat = JarvisMetrics.segmentedControlPadding
    static let hoverScale: CGFloat = 1.01
    static let horizontalPadding: CGFloat = 10
    static let arrowSpacing: CGFloat = 5
    static let arrowPointSize: CGFloat = 10

    /// Width of the trigger's chevron at `arrowPointSize`. The trigger
    /// reserves the symbol's real width plus its spacing; a hand-picked
    /// fifteen points came up a point short, which clipped the longest title
    /// in a control — "超过 1 个月" lost its last character.
    static let arrowWidth: CGFloat = {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: arrowPointSize,
            weight: .semibold
        )
        let symbolWidth = NSImage(
            systemSymbolName: "chevron.down",
            accessibilityDescription: nil
        )?
            .withSymbolConfiguration(configuration)?
            .size.width
        return symbolWidth ?? 11
    }()

    static func width(
        for titles: [String],
        includesArrow: Bool = true,
        maximumWidth: CGFloat = maximumControlWidth
    ) -> CGFloat {
        let controlFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        let widestTitle = titles
            .map { title in
                (title as NSString).size(withAttributes: [.font: controlFont]).width
            }
            .max() ?? 0
        let idealWidth = ceil(
            widestTitle
                + (horizontalPadding * 2)
                + (includesArrow ? arrowSpacing + arrowWidth : 0)
        )
        return min(max(idealWidth, minimumControlWidth), maximumWidth)
    }
}

/// Shared custom SwiftUI dropdown used by every value selector and action selector.
///
/// The toolbar trigger is an ordinary button so macOS 27 cannot collapse its
/// label into an icon-only menu trigger. Its transparent anchored panel owns
/// the independent pill options, hover state, selection highlight, animation,
/// and selection action from end to end.
struct JarvisDropdownMenu: View {
    let title: String
    let options: [JarvisDropdownOption]
    let selectionID: String?
    let accessibilityLabel: String
    let help: String
    let controlWidth: CGFloat?
    let maximumControlWidth: CGFloat
    let showsChevron: Bool
    let usesLiquidGlass: Bool
    let isEnabled: Bool
    let onSelect: (String) -> Void
    @State private var isPresented = false

    init(
        title: String,
        options: [JarvisDropdownOption],
        selectionID: String? = nil,
        accessibilityLabel: String,
        help: String,
        controlWidth: CGFloat? = nil,
        maximumControlWidth: CGFloat = JarvisDropdownMetrics.maximumControlWidth,
        showsChevron: Bool = true,
        usesLiquidGlass: Bool = false,
        isEnabled: Bool = true,
        onSelect: @escaping (String) -> Void
    ) {
        self.title = title
        self.options = options
        self.selectionID = selectionID
        self.accessibilityLabel = accessibilityLabel
        self.help = help
        self.controlWidth = controlWidth
        self.maximumControlWidth = maximumControlWidth
        self.showsChevron = showsChevron
        self.usesLiquidGlass = usesLiquidGlass
        self.isEnabled = isEnabled
        self.onSelect = onSelect
    }

    private var resolvedControlWidth: CGFloat {
        controlWidth ?? JarvisDropdownMetrics.width(
            for: [title] + options.map(\.title),
            includesArrow: showsChevron,
            maximumWidth: maximumControlWidth
        )
    }

    var body: some View {
        let width = resolvedControlWidth

        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: JarvisDropdownMetrics.arrowSpacing) {
                Text(title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showsChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: JarvisDropdownMetrics.arrowPointSize, weight: .semibold))
                        .accessibilityHidden(true)
                }
            }
            .frame(width: width - (JarvisDropdownMetrics.horizontalPadding * 2))
        }
        .buttonStyle(JarvisToolbarButtonStyle.menu())
        .disabled(!isEnabled || options.isEmpty)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(title)
        .frame(width: width)
        .fixedSize(horizontal: true, vertical: false)
        .modifier(JarvisDropdownTriggerGlassModifier(isEnabled: usesLiquidGlass))
        .background(
            JarvisDropdownMenuPanelPresenter(
                isPresented: $isPresented,
                options: options,
                selectionID: selectionID,
                controlWidth: width,
                onSelect: { optionID in
                    onSelect(optionID)
                }
            )
            .allowsHitTesting(false)
        )
    }
}

private struct JarvisDropdownTriggerGlassModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.jarvisGlass(
                in: Capsule(),
                interactive: true
            )
        } else {
            content
        }
    }
}

private struct JarvisDropdownPillMenuList: View {
    let options: [JarvisDropdownOption]
    let selectionID: String?
    let controlWidth: CGFloat
    let onSelect: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealsOptions = false
    @State private var highlightedOptionID: String?

    private var visibleOptions: [JarvisDropdownOption] {
        guard let selectionID else { return options }
        return options.filter { $0.id != selectionID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisDropdownMetrics.optionSpacing) {
            ForEach(visibleOptions) { option in
                let isSelected = selectionID == option.id
                let isHighlighted = highlightedOptionID == option.id

                Button {
                    onSelect(option.id)
                } label: {
                    Text(option.title)
                }
                .buttonStyle(
                    JarvisDropdownPillButtonStyle(
                        controlWidth: controlWidth,
                        isSelected: isSelected,
                        isHighlighted: isHighlighted
                    )
                )
                .accessibilityLabel(option.title)
                .opacity(revealsOptions ? 1 : 0)
                .offset(y: revealsOptions ? 0 : -8)
                .animation(
                    JarvisMotion.animation(
                        JarvisMotion.content.delay(
                            Double(visibleOptions.firstIndex(of: option) ?? 0) * 0.045
                        ),
                        reduceMotion: reduceMotion
                    ),
                    value: revealsOptions
                )
                .onHover { isHovering in
                    withAnimation(
                        JarvisMotion.animation(
                            JarvisMotion.hover,
                            reduceMotion: reduceMotion
                        )
                    ) {
                        highlightedOptionID = isHovering ? option.id : nil
                    }
                }
            }
        }
        .frame(width: controlWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .padding(JarvisDropdownMetrics.menuEdgePadding)
        .task {
            await Task.yield()
            withAnimation(
                JarvisMotion.animation(
                    JarvisMotion.content,
                    reduceMotion: reduceMotion
                )
            ) {
                revealsOptions = true
            }
        }
        .onDisappear {
            highlightedOptionID = nil
        }
    }
}

private struct JarvisDropdownPillButtonStyle: ButtonStyle {
    let controlWidth: CGFloat
    let isSelected: Bool
    let isHighlighted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isSelected ? JarvisTypography.controlEmphasis : JarvisTypography.control)
            .foregroundStyle(
                isSelected
                    ? Color.white
                    : Color.primary
            )
            .lineLimit(1)
            .padding(.horizontal, JarvisDropdownMetrics.horizontalPadding)
            .frame(
                width: controlWidth,
                height: JarvisToolbarMetrics.controlSize,
                alignment: .leading
            )
            .contentShape(Capsule())
            .jarvisGlass(
                // Keep the material identity stable while the pointer
                // moves between options. Changing a glass tint on every
                // hover asks macOS to rebuild the material and briefly
                // exposes the transparent intermediate state.
                tint: isSelected ? .accentColor : nil,
                in: Capsule(),
                interactive: false
            )
            .overlay {
                if isHighlighted, !isSelected {
                    Capsule()
                        .fill(JarvisMotion.hoverPillTint)
                        .allowsHitTesting(false)
                }
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(
                reduceMotion
                    ? 1
                    : (isHighlighted ? JarvisDropdownMetrics.hoverScale : (configuration.isPressed ? 0.98 : 1)),
                anchor: .center
            )
            .animation(
                JarvisMotion.animation(
                    JarvisMotion.buttonPress,
                    reduceMotion: reduceMotion
                ),
                value: configuration.isPressed
            )
            .animation(
                JarvisMotion.animation(
                    JarvisMotion.hover,
                    reduceMotion: reduceMotion
                ),
                value: isHighlighted
            )
    }
}

private struct JarvisDropdownMenuPanelPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    let options: [JarvisDropdownOption]
    let selectionID: String?
    let controlWidth: CGFloat
    let onSelect: (String) -> Void

    func makeNSView(context: Context) -> NSView {
        let anchorView = NSView(frame: .zero)
        context.coordinator.anchorView = anchorView
        return anchorView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            anchorView: nsView,
            isPresented: isPresented,
            options: options,
            selectionID: selectionID,
            controlWidth: controlWidth,
            onSelect: onSelect,
            dismiss: { isPresented = false }
        )
    }

    static func dismantleNSView(
        _: NSView,
        coordinator: Coordinator
    ) {
        coordinator.dismiss()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        weak var anchorView: NSView?
        private var panel: NSPanel?
        private var outsideClickMonitor: Any?
        private var dismissAction: (() -> Void)?

        func update(
            anchorView: NSView,
            isPresented: Bool,
            options: [JarvisDropdownOption],
            selectionID: String?,
            controlWidth: CGFloat,
            onSelect: @escaping (String) -> Void,
            dismiss: @escaping () -> Void
        ) {
            self.anchorView = anchorView
            dismissAction = dismiss

            guard isPresented else {
                dismiss()
                return
            }

            if panel == nil {
                present(
                    options: options,
                    selectionID: selectionID,
                    controlWidth: controlWidth,
                    onSelect: onSelect,
                    dismiss: dismiss
                )
            } else {
                positionPanel()
            }
        }

        func dismiss() {
            if let outsideClickMonitor {
                NSEvent.removeMonitor(outsideClickMonitor)
                self.outsideClickMonitor = nil
            }

            guard let panel else { return }
            if let parentWindow = panel.parent {
                parentWindow.removeChildWindow(panel)
            }
            panel.orderOut(nil)
            panel.close()
            self.panel = nil
        }

        private func present(
            options: [JarvisDropdownOption],
            selectionID: String?,
            controlWidth: CGFloat,
            onSelect: @escaping (String) -> Void,
            dismiss: @escaping () -> Void
        ) {
            guard let anchorView, let parentWindow = anchorView.window else { return }

            let panel = JarvisDropdownMenuPanel(
                contentRect: .zero,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            let menu = JarvisDropdownPillMenuList(
                options: options,
                selectionID: selectionID,
                controlWidth: controlWidth,
                onSelect: { [self] optionID in
                    dismiss()
                    onSelect(optionID)
                    self.dismiss()
                    DispatchQueue.main.async { [weak self] in
                        self?.dismiss()
                    }
                }
            )
            let hostingView = NSHostingView(rootView: menu)
            let fittingSize = hostingView.fittingSize
            hostingView.frame = NSRect(origin: .zero, size: fittingSize)

            panel.setContentSize(fittingSize)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isFloatingPanel = true
            panel.level = .popUpMenu
            panel.hidesOnDeactivate = true
            panel.isReleasedWhenClosed = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
            panel.contentView = hostingView

            self.panel = panel
            parentWindow.addChildWindow(panel, ordered: .above)
            positionPanel()
            panel.makeKeyAndOrderFront(nil)
            installOutsideClickMonitor()
        }

        private func positionPanel() {
            guard
                let panel,
                let anchorView,
                let parentWindow = anchorView.window
            else {
                return
            }

            let anchorRect = parentWindow.convertToScreen(
                anchorView.convert(anchorView.bounds, to: nil)
            )
            let visibleFrame = parentWindow.screen?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? .zero
            let panelSize = panel.frame.size
            let horizontalOrigin = anchorRect.midX - (panelSize.width / 2)
            let maximumX = visibleFrame.maxX - panelSize.width
            let originX = min(max(horizontalOrigin, visibleFrame.minX), maximumX)
            let originY = anchorRect.minY
                - panelSize.height
                - JarvisDropdownMetrics.triggerGap

            panel.setFrameOrigin(NSPoint(x: originX, y: originY))
        }

        private func installOutsideClickMonitor() {
            outsideClickMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown]
            ) { [weak self] event in
                guard let self, let panel = self.panel else { return event }

                if event.window === panel {
                    return event
                }

                // The trigger is also the close affordance. Consume the
                // second click after dismissing the panel so the button does
                // not toggle the binding back to `true` in the same event.
                if self.isAnchorClick(event) {
                    self.dismiss()
                    self.dismissAction?()
                    return nil
                }

                self.dismiss()
                self.dismissAction?()
                return event
            }
        }

        private func isAnchorClick(_ event: NSEvent) -> Bool {
            guard
                let eventWindow = event.window,
                let anchorView,
                let anchorWindow = anchorView.window
            else {
                return false
            }

            let pointOnScreen = eventWindow.convertToScreen(
                NSRect(origin: event.locationInWindow, size: .zero)
            ).origin
            let anchorRect = anchorWindow.convertToScreen(
                anchorView.convert(anchorView.bounds, to: nil)
            )
            return anchorRect.contains(pointOnScreen)
        }
    }
}

@MainActor
private final class JarvisDropdownMenuPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
