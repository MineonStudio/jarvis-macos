import AppKit
import SwiftUI

// MARK: - Jarvis visual language

enum JarvisTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func resolvedColorScheme(system: ColorScheme) -> ColorScheme {
        preferredColorScheme ?? system
    }
}

enum JarvisTypography {
    static let pageTitle = Font.system(size: 26, weight: .semibold, design: .rounded)
    static let cardTitle = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 14)
    static let bodyEmphasis = Font.system(size: 14, weight: .semibold)
    static let control = Font.system(size: 13, weight: .medium)
    static let controlEmphasis = Font.system(size: 13, weight: .semibold)
    static let secondary = Font.system(size: 13)
    static let caption = Font.system(size: 12)
    static let captionEmphasis = Font.system(size: 12, weight: .medium)
    static let monospaced = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let badge = Font.system(size: 11, weight: .bold, design: .rounded)
    static let metricValue = Font.system(size: 22, weight: .semibold, design: .rounded)
}

/// Uses SwiftUI's presentation-level appearance API with the current system
/// scheme resolved explicitly. Resolving .system to .light/.dark avoids a
/// macOS Settings scene retaining the previous preferred scheme until another
/// interaction causes it to redraw.
private struct JarvisThemeModifier: ViewModifier {
    let theme: JarvisTheme
    let systemColorScheme: ColorScheme

    func body(content: Content) -> some View {
        content.preferredColorScheme(theme.resolvedColorScheme(system: systemColorScheme))
    }
}

extension Color {
    // Keep these names stable for the rest of the app, but use semantic system
    // colors instead of a fixed dark palette so the window follows macOS.
    static let jarvisBackground = Color(nsColor: .textBackgroundColor)
    static let jarvisPanel = Color(nsColor: .controlBackgroundColor)
    static let jarvisCyan = Color.accentColor
    static let jarvisTextSecondary = Color.secondary
}

enum JarvisMetrics {
    static let pageInset: CGFloat = 30
    static let shellHorizontalPadding: CGFloat = 10
    static let shellVerticalPadding: CGFloat = 10
    static let shellContentSpacing: CGFloat = 10
    static let cardRadius: CGFloat = 14
    static let controlRadius: CGFloat = 10
    static let iconTintOpacity: CGFloat = 0.22
    static let segmentedItemHeight: CGFloat = 28
    static let segmentedControlPadding: CGFloat = 2
    static let segmentedItemSpacing: CGFloat = 2
    static let segmentedItemVerticalPadding: CGFloat = 4
    static let sidebarMinimumWidth: CGFloat = 152
    static let sidebarWidth: CGFloat = 168
    static let sidebarMaximumWidth: CGFloat = 220
    static let sidebarContentPadding: CGFloat = 8
}

/// Metrics shared by every control rendered in the native window toolbar.
///
/// The chat toolbar is the reference implementation: controls occupy one
/// 32-point row, use an 8-point rhythm, and do not draw a parent surface.
enum JarvisToolbarMetrics {
    static let controlSize: CGFloat = 32
    static let controlSpacing: CGFloat = 8
    static let iconSize: CGFloat = 13
    static let searchFieldWidth: CGFloat = 240
}

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

/// Marks a toolbar item whose view owns its own capsule, glass, or other
/// background. Native macOS toolbars otherwise add their shared item surface
/// around that view, producing the recurring double-layer control.
struct JarvisToolbarSurface<Content: View>: ToolbarContent {
    private let id: String
    private let placement: ToolbarItemPlacement
    private let content: Content

    init(
        id: String,
        placement: ToolbarItemPlacement = .automatic,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self.placement = placement
        self.content = content()
    }

    var body: some ToolbarContent {
        ToolbarItem(id: id, placement: placement) {
            content
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

/// Shared toolbar search field used by clipboard, wallpaper, and meetings.
///
/// Height comes from the native toolbar item surface, not a custom 32-point
/// glass capsule. Hiding that surface and drawing our own glass made the
/// field shorter than adjacent toolbar controls.
struct JarvisToolbarSearchField: View {
    @Binding var text: String
    var placeholder: String
    var help: String?
    var accessibilityTitle: String?
    var focusesOnAppear = false
    var onSubmit: (() -> Void)?
    var onClear: (() -> Void)?
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: JarvisToolbarMetrics.iconSize, weight: .medium))
                .foregroundStyle(Color.jarvisTextSecondary)
                .frame(
                    width: JarvisToolbarMetrics.iconSize,
                    height: JarvisToolbarMetrics.iconSize
                )

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(JarvisTypography.control)
                .controlSize(.regular)
                .focused($isFocused)
                .onSubmit {
                    onSubmit?()
                }

            if !text.isEmpty {
                Button {
                    if let onClear {
                        onClear()
                    } else {
                        text = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: JarvisToolbarMetrics.iconSize, weight: .semibold))
                        .frame(
                            width: JarvisToolbarMetrics.iconSize,
                            height: JarvisToolbarMetrics.iconSize
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.jarvisTextSecondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: JarvisToolbarMetrics.searchFieldWidth)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused = true
        }
        .onAppear {
            if focusesOnAppear {
                isFocused = true
            }
        }
        .help(help ?? placeholder)
        .accessibilityLabel(accessibilityTitle ?? placeholder)
    }
}

/// Shared capsule surface for compact text-entry controls.
struct JarvisCapsuleInputFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .frame(minHeight: JarvisToolbarMetrics.controlSize)
            .jarvisGlass(in: Capsule(), interactive: false)
    }
}

/// Shared content-area shell for every module in the main window.
///
/// The shell owns the window toolbar and the body inset. Modules provide only
/// leading and trailing toolbar content plus their body, so the system can
/// place the operation bar alongside the native sidebar control and reflow it
/// when the split view changes width.
struct JarvisContentArea<LeadingToolbar: ToolbarContent, TrailingToolbar: ToolbarContent, Content: View>: View {
    private let leadingToolbar: LeadingToolbar
    private let trailingToolbar: TrailingToolbar
    private let content: Content

    init(
        @ToolbarContentBuilder leadingToolbar: () -> LeadingToolbar,
        @ToolbarContentBuilder trailingToolbar: () -> TrailingToolbar,
        @ViewBuilder content: () -> Content
    ) {
        self.leadingToolbar = leadingToolbar()
        self.trailingToolbar = trailingToolbar()
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, JarvisMetrics.shellContentSpacing)
            .padding(.horizontal, JarvisMetrics.shellHorizontalPadding)
            .padding(.bottom, JarvisMetrics.shellVerticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.jarvisBackground)
            .toolbar {
                leadingToolbar
                ToolbarSpacer(.flexible, placement: .automatic)
                trailingToolbar
            }
    }
}

struct JarvisPageTopBar: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(JarvisTypography.cardTitle)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct JarvisCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .jarvisContentSurface(cornerRadius: JarvisMetrics.cardRadius)
    }
}

struct JarvisEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 56, height: 56)
                .background(
                    Color.accentColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.75)
                }
            Text(title)
                .font(JarvisTypography.cardTitle)
                .multilineTextAlignment(.center)
            Text(message)
                .font(JarvisTypography.secondary)
                .foregroundStyle(Color.jarvisTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .jarvisContentSurface(cornerRadius: JarvisMetrics.cardRadius)
    }
}

/// Standard content-layer surface for cards and collections.
///
/// Liquid Glass belongs primarily to the functional layer (toolbars,
/// navigation, and transient controls). Content cards use a semantic macOS
/// control background instead so dense content remains legible and calm.
struct JarvisContentSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                Color.jarvisPanel,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
    }
}

struct JarvisInlineLoadingState: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("正在加载")
        }
        .foregroundStyle(Color.jarvisTextSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在加载")
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(JarvisTypography.pageTitle)
            .foregroundStyle(.primary)
    }
}

/// Native macOS 26 Liquid Glass wrapper shared by cards and controls.
struct JarvisGlassModifier: ViewModifier {
    let tint: Color?
    let cornerRadius: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        if let tint {
            content.glassEffect(
                .regular.tint(tint).interactive(interactive),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content.glassEffect(
                .regular.interactive(interactive),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}

struct JarvisGlassShapeModifier<GlassShape: Shape>: ViewModifier {
    let tint: Color?
    let shape: GlassShape
    let interactive: Bool

    func body(content: Content) -> some View {
        if let tint {
            content.glassEffect(
                .regular.tint(tint).interactive(interactive),
                in: shape
            )
        } else {
            content.glassEffect(
                .regular.interactive(interactive),
                in: shape
            )
        }
    }
}

struct JarvisFloatingPanelModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                Color.jarvisPanel,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(0.11), radius: 16, y: 6)
    }
}

extension View {
    func jarvisTheme(_ theme: JarvisTheme, systemColorScheme: ColorScheme) -> some View {
        modifier(JarvisThemeModifier(theme: theme, systemColorScheme: systemColorScheme))
    }

    func jarvisCapsuleInputField() -> some View {
        modifier(JarvisCapsuleInputFieldModifier())
    }

    func jarvisGlass(
        tint: Color? = nil,
        cornerRadius: CGFloat = JarvisMetrics.controlRadius,
        interactive: Bool = true
    ) -> some View {
        modifier(JarvisGlassModifier(tint: tint, cornerRadius: cornerRadius, interactive: interactive))
    }

    func jarvisGlass(
        tint: Color? = nil,
        in shape: some Shape,
        interactive: Bool = true
    ) -> some View {
        modifier(JarvisGlassShapeModifier(tint: tint, shape: shape, interactive: interactive))
    }

    func jarvisFloatingPanel(cornerRadius: CGFloat = 16) -> some View {
        modifier(JarvisFloatingPanelModifier(cornerRadius: cornerRadius))
    }

    func jarvisContentSurface(cornerRadius: CGFloat = JarvisMetrics.cardRadius) -> some View {
        modifier(JarvisContentSurfaceModifier(cornerRadius: cornerRadius))
    }

    /// A lighter Liquid Glass treatment for the small icon containers used
    /// throughout the pages. Full-strength accent tint makes these bubbles
    /// read as solid dark badges instead of translucent glass.
    func jarvisIconGlass(
        tint: Color = .accentColor,
        in shape: some Shape,
        interactive: Bool = false
    ) -> some View {
        jarvisGlass(
            tint: tint.opacity(JarvisMetrics.iconTintOpacity),
            in: shape,
            interactive: interactive
        )
    }
}

struct JarvisPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(JarvisTypography.controlEmphasis)
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .opacity(configuration.isPressed ? 0.78 : (isEnabled ? 1 : 0.78))
            .jarvisGlass(
                tint: isEnabled ? .accentColor : Color.primary.opacity(0.12),
                cornerRadius: JarvisMetrics.controlRadius
            )
            .contentShape(RoundedRectangle(cornerRadius: JarvisMetrics.controlRadius, style: .continuous))
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1))
            .animation(
                JarvisMotion.animation(JarvisMotion.buttonPress, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

/// Text-first action style for module operation bars. The operation bar owns
/// placement and spacing; individual actions provide only their label and
/// hover/press feedback, so no control can grow into a toolbar background.
/// Controls that intentionally draw their own surface must be wrapped in
/// `JarvisToolbarSurface` at the ToolbarItem boundary.
struct JarvisToolbarButtonStyle: ButtonStyle {
    let tint: Color?
    let hoverScale: CGFloat
    let animatesPress: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(tint: Color? = nil, hoverScale: CGFloat = 1.03, animatesPress: Bool = true) {
        self.tint = tint
        self.hoverScale = hoverScale
        self.animatesPress = animatesPress
    }

    /// Menu labels must keep a stable frame. Hovering popup items toggles
    /// press/hover on macOS and would otherwise flicker the attached list.
    static func menu(tint: Color? = nil) -> Self {
        Self(tint: tint, hoverScale: 1, animatesPress: false)
    }

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = animatesPress && configuration.isPressed
        configuration.label
            .font(tint == nil ? JarvisTypography.control : JarvisTypography.controlEmphasis)
            .foregroundStyle(tint ?? Color.primary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .frame(height: JarvisToolbarMetrics.controlSize)
            .opacity(isPressed ? 0.68 : 1)
            .contentShape(Capsule())
            .jarvisHoverFeedback(in: Capsule(), scale: hoverScale)
            .scaleEffect(reduceMotion || !isPressed ? 1 : 0.98)
            .animation(
                JarvisMotion.animation(JarvisMotion.buttonPress, reduceMotion: reduceMotion),
                value: isPressed
            )
    }
}

/// A single selection control for the native toolbar. Selection is rendered
/// by the button itself; there is intentionally no parent capsule or group
/// surface around a row of options.
struct JarvisToolbarSelectionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(isSelected ? JarvisTypography.controlEmphasis : JarvisTypography.control)
                .foregroundStyle(isSelected ? Color.white : Color.jarvisTextSecondary)
                .padding(.horizontal, 10)
                .frame(height: JarvisToolbarMetrics.controlSize)
                .background {
                    Capsule()
                        .fill(
                            isSelected
                                ? JarvisMotion.selectionPillTint
                                : (isHovered ? JarvisMotion.hoverPillTint : .clear)
                        )
                }
                .contentShape(Capsule())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.82))
        .scaleEffect(
            reduceMotion || isSelected || !isHovered ? 1 : 1.02,
            anchor: .center
        )
        .animation(
            JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion),
            value: isHovered
        )
        .animation(
            JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
            value: isSelected
        )
        .onHover { isHovering in
            withAnimation(
                JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion)
            ) {
                isHovered = isHovering
            }
        }
    }
}

/// Shared zoom pair used by the clipboard, screenshot, and resume toolbars.
///
/// The native toolbar item surface sets the height, so the row fills its host
/// instead of forcing a custom frame; a custom 32-point capsule was shorter
/// than adjacent toolbar controls.
struct JarvisToolbarZoomControl: View {
    let canZoomOut: Bool
    let canZoomIn: Bool
    let zoomOutLabel: String
    let zoomInLabel: String
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            zoomButton(
                systemName: "minus",
                help: zoomOutLabel,
                isEnabled: canZoomOut,
                action: onZoomOut
            )

            Divider()
                .frame(height: 16)
                .opacity(0.35)

            zoomButton(
                systemName: "plus",
                help: zoomInLabel,
                isEnabled: canZoomIn,
                action: onZoomIn
            )
        }
        .padding(.horizontal, 2)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func zoomButton(
        systemName: String,
        help: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(
                JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion)
            ) {
                action()
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.92, pressedOpacity: 0.75))
        .opacity(isEnabled ? 1 : 0.35)
        .disabled(!isEnabled)
        .accessibilityLabel(help)
        .help(help)
    }
}

struct JarvisSecondaryButtonStyle: ButtonStyle {
    let tint: Color?

    init(tint: Color? = nil) {
        self.tint = tint
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(JarvisTypography.control)
            .foregroundStyle(tint ?? .primary)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .opacity(configuration.isPressed ? 0.68 : 1)
            .jarvisGlass(cornerRadius: JarvisMetrics.controlRadius)
            .contentShape(RoundedRectangle(cornerRadius: JarvisMetrics.controlRadius, style: .continuous))
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1))
            .animation(
                JarvisMotion.animation(JarvisMotion.buttonPress, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}
