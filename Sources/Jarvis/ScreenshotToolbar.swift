import SwiftUI
import Translation

// MARK: - Screenshot editing toolbar

/// 自绘的马赛克图标，按统一墨迹尺寸等比缩放（原来写死 24pt，比同排符号大一截）。
struct MosaicToolIcon: View {
    let color: Color
    var size: CGFloat = ScreenshotToolbarIconMetrics.targetInkHeight

    var body: some View {
        let gap = size * 0.083
        let stroke = size * 0.0625
        let square = (size - gap - stroke) / 2

        ZStack {
            VStack(spacing: gap) {
                ForEach(0 ..< 2, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0 ..< 2, id: \.self) { column in
                            Rectangle()
                                .fill((row + column).isMultiple(of: 2) ? color : .clear)
                                .frame(width: square, height: square)
                        }
                    }
                }
            }

            // 用 strokeBorder 而不是 stroke：描边居中的话有一半会落到画框外，
            // 墨迹就比同排符号高一截。
            RoundedRectangle(cornerRadius: size * 0.083, style: .continuous)
                .strokeBorder(color, lineWidth: stroke)
        }
        .frame(width: size, height: size)
    }
}

/// 两条胶囊共用同一套表面：圆角裁成胶囊 + 一层玻璃。复制两份的话，改一处漏一处
/// 不会有任何信号。
///
/// `interactive: false`：胶囊里装的是自己带玻璃的按钮，胶囊再对指针起反应就会和
/// 按钮的悬停/按下叠成两层反馈。
private struct ScreenshotToolbarPillSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .clipShape(Capsule())
            .contentShape(Capsule())
            .jarvisGlass(in: Capsule(), interactive: false)
    }
}

private extension View {
    func screenshotToolbarPill() -> some View {
        modifier(ScreenshotToolbarPillSurface())
    }
}

/// 二级行里的可选项（马赛克的模式/效果、文字的粗体/斜体/删除线）。
///
/// 选中态走全局那一套 `jarvisSelectionPill`（恒为胶囊 + accent 实心），和
/// `JarvisToolbarSelectionButton`、分组选择器是同一份实现；它到行胶囊两端的距离
/// 由 `ScreenshotToolbarMetrics.secondaryRowHorizontalPadding` 给出，和上下同值。
struct ScreenshotToolbarOptionButton: View {
    var icon: String?
    var title: String?
    let selected: Bool
    let help: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                }
                if let title {
                    Text(title)
                        .font(selected ? JarvisTypography.controlEmphasis : JarvisTypography.control)
                }
            }
            .foregroundStyle(selected ? Color.white : Color.jarvisTextSecondary)
            .padding(.horizontal, title == nil ? 0 : 9)
            .frame(width: title == nil ? 28 : nil, height: ScreenshotToolbarMetrics.secondaryControlHeight)
            .jarvisSelectionPill(isSelected: selected, isHovered: isHovered)
            .contentShape(Capsule())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.84))
        .help(help)
        .accessibilityLabel(title ?? help)
        .animation(
            JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion),
            value: isHovered
        )
        .animation(
            JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
            value: selected
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

/// 目标语言。箭头跟在文字右边，菜单从这颗胶囊的屏幕位置展开。
///
/// 不用 SwiftUI `Menu`：它在截图这层无边框面板里会把箭头拽到文字左边，弹出层也
/// 对不齐这颗按钮。
private struct TranslationLanguageChip: View {
    let title: String
    let selected: ScreenshotTranslationLanguage
    let onSelect: (ScreenshotTranslationLanguage) -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(JarvisTypography.control)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 9)
            .frame(height: ScreenshotToolbarMetrics.secondaryControlHeight)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.84))
        .accessibilityLabel("目标语言")
        .accessibilityValue(title)
        .background {
            TranslationLanguageMenuAnchor(
                isPresented: $isPresented,
                selected: selected,
                onSelect: onSelect
            )
        }
    }
}

/// 把语言列表贴在胶囊上。截图窗口盖住全屏，弹层必须是它的子窗口，否则会落到画面后面
/// 或相对错误的坐标系弹出。选项样式跟主窗口工具栏的下拉菜单是同一套。
private struct TranslationLanguageMenuAnchor: NSViewRepresentable {
    @Binding var isPresented: Bool
    let selected: ScreenshotTranslationLanguage
    let onSelect: (ScreenshotTranslationLanguage) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            anchorView: nsView,
            isPresented: isPresented,
            selected: selected,
            onSelect: onSelect,
            dismiss: { isPresented = false }
        )
    }

    static func dismantleNSView(_: NSView, coordinator: Coordinator) {
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
            selected: ScreenshotTranslationLanguage,
            onSelect: @escaping (ScreenshotTranslationLanguage) -> Void,
            dismiss: @escaping () -> Void
        ) {
            self.anchorView = anchorView
            dismissAction = dismiss
            guard isPresented, anchorView.bounds.width > 1, anchorView.bounds.height > 1 else {
                self.dismiss()
                return
            }
            if panel == nil {
                present(selected: selected, onSelect: onSelect)
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
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            panel.close()
            self.panel = nil
        }

        private func present(
            selected: ScreenshotTranslationLanguage,
            onSelect: @escaping (ScreenshotTranslationLanguage) -> Void
        ) {
            guard let anchorView, let parentWindow = anchorView.window else { return }

            let panel = TranslationLanguageMenuPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            let options = ScreenshotTranslationLanguage.allCases.map { language in
                JarvisDropdownOption(id: language.rawValue, title: language.title)
            }
            let menu = JarvisDropdownPillMenuList(
                options: options,
                selectionID: selected.rawValue,
                showsSelectedOption: true,
                controlWidth: JarvisDropdownMetrics.menuWidth(
                    for: selected.title,
                    options: options
                ),
                onSelect: { [weak self] optionID in
                    guard let language = ScreenshotTranslationLanguage(rawValue: optionID) else { return }
                    self?.dismiss()
                    self?.dismissAction?()
                    onSelect(language)
                }
            )
            let hostingView = NSHostingView(rootView: menu.jarvisAccentAware())
            let fittingSize = hostingView.fittingSize
            hostingView.frame = NSRect(origin: .zero, size: fittingSize)
            panel.setContentSize(fittingSize)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isFloatingPanel = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.contentView = hostingView

            self.panel = panel
            parentWindow.addChildWindow(panel, ordered: .above)
            positionPanel()
            panel.makeKeyAndOrderFront(nil)
            installOutsideClickMonitor()
        }

        private func positionPanel() {
            guard let panel, let anchorView, let parentWindow = anchorView.window else { return }
            let anchorRect = parentWindow.convertToScreen(anchorView.convert(anchorView.bounds, to: nil))
            let visibleFrame = parentWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let panelSize = panel.frame.size
            let gap = JarvisDropdownMetrics.triggerGap
            let below = anchorRect.minY - gap - panelSize.height
            let originY = below >= visibleFrame.minY
                ? below
                : min(anchorRect.maxY + gap, visibleFrame.maxY - panelSize.height)
            let originX = JarvisDropdownMetrics.menuOriginX(
                anchorMinX: anchorRect.minX,
                panelWidth: panelSize.width,
                visibleFrame: visibleFrame
            )
            panel.setFrameOrigin(NSPoint(x: originX, y: originY))
        }

        private func installOutsideClickMonitor() {
            outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                guard let self, let panel = self.panel else { return event }
                if event.window === panel {
                    return event
                }
                let closesFromAnchor = self.isAnchorClick(event)
                self.dismiss()
                self.dismissAction?()
                return closesFromAnchor ? nil : event
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
            let point = eventWindow.convertToScreen(
                NSRect(origin: event.locationInWindow, size: .zero)
            ).origin
            let anchorRect = anchorWindow.convertToScreen(anchorView.convert(anchorView.bounds, to: nil))
            return anchorRect.contains(point)
        }
    }
}

/// 截图浮层在 `.screenSaver`，普通弹层会落到画面后面。这层面板盖在工具栏上，
/// 并且能成为 key window，悬浮跟踪才跟主窗口下拉菜单一样生效。
private final class TranslationLanguageMenuPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

/// 箭头、框选、画笔的五档线宽。每一档是一个固定粗细，档位本身用越来越粗的笔触表示。
private struct ScreenshotStrokeStagePicker: View {
    @Binding var width: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(ScreenshotStrokeWidth.stages.enumerated()), id: \.offset) { index, stage in
                ScreenshotStrokeStageButton(
                    markHeight: Self.markHeight(at: index),
                    stage: stage,
                    selected: width == stage
                ) {
                    width = stage
                }
            }
        }
    }

    /// 按钮里的笔触高度。和真实线宽同一方向变粗，但收进 26pt 高的控件里。
    private static func markHeight(at index: Int) -> CGFloat {
        let heights: [CGFloat] = [2, 3.5, 5, 7, 10]
        guard heights.indices.contains(index) else { return heights.last ?? 2 }
        return heights[index]
    }
}

private struct ScreenshotStrokeStageButton: View {
    let markHeight: CGFloat
    let stage: CGFloat
    let selected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(selected ? Color.white : Color.secondary)
                .frame(width: 14, height: markHeight)
                .frame(width: 28, height: ScreenshotToolbarMetrics.secondaryControlHeight)
                .jarvisSelectionPill(isSelected: selected, isHovered: isHovered)
                .contentShape(Capsule())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.84))
        .accessibilityLabel("粗细 \(Int(stage))")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(
            JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion),
            value: isHovered
        )
        .animation(
            JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
            value: selected
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

/// 二级行里的文字按钮：与下拉芯片同一种胶囊外形。
private struct SecondaryCapsuleButton: View {
    let title: String
    var isProminent = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(isProminent ? JarvisTypography.controlEmphasis : JarvisTypography.control)
                .foregroundStyle(
                    isEnabled
                        ? (isProminent ? Color.white : Color.primary)
                        : Color.secondary.opacity(0.5)
                )
                .padding(.horizontal, 11)
                .frame(height: ScreenshotToolbarMetrics.secondaryControlHeight)
                .background(
                    isProminent && isEnabled
                        ? AnyShapeStyle(JarvisMotion.selectionPillTint)
                        : AnyShapeStyle(Color.primary.opacity(0.06)),
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.84))
        .disabled(!isEnabled)
    }
}

/// 分隔线的统一口径：一级行和二级行原来各写一个透明度（0.22 / 0.16）。
enum ScreenshotToolbarDivider {
    static let color = Color.primary.opacity(0.18)
}

struct ScreenshotToolbar: View {
    @ObservedObject var editor: ScreenshotEditorModel
    @ObservedObject var layout: ScreenshotToolbarLayoutModel
    let onAction: (ScreenshotAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 悬停中的一级工具 / 翻译按钮 / 行内动作按钮：同一时刻只会悬停在其中之一，
    /// 一排按钮共用一组状态就够了。
    @State private var hoveredTool: ScreenshotTool?
    @State private var isHoveringTranslation = false
    @State private var hoveredAction: String?
}

extension ScreenshotToolbar {
    var body: some View {
        VStack(spacing: ScreenshotToolbarMetrics.pillSpacing) {
            if layout.placesSecondaryRowAboveMain {
                // 工具栏在选区上方：主行贴着选区（窗口下沿），二级行向上伸展。
                // 否则收起二级行时窗口一变矮，主行会跟着弹一下。
                secondaryRow
                mainRow
            } else {
                mainRow
                secondaryRow
            }
        }
        // 不额外留边：胶囊就是窗口本身，留白会变成同样的死区，也会让工具栏放到
        // 选区上方时的间距比放下方时多出一截。
        .frame(
            width: layout.width,
            height: editor.secondaryBarVisible
                ? ScreenshotToolbarMetrics.expandedHeight
                : ScreenshotToolbarMetrics.compactHeight
        )
        .translationTask(editor.appleTranslationConfiguration) { @Sendable session in
            await editor.consumeAppleTranslationSession(session)
        }
        .jarvisAccentAware()
    }

    /// 主按钮行：撑满窗口宽度（面板按固定宽度摆位，胶囊收窄就会留下看得见截图、
    /// 点下去却没反应的死区）。
    private var mainRow: some View {
        mainToolRow
            .frame(height: ScreenshotToolbarMetrics.mainRowHeight)
            .padding(.horizontal, ScreenshotToolbarMetrics.mainRowHorizontalPadding)
            .frame(maxWidth: .infinity)
            .screenshotToolbarPill()
    }

    /// 二级行：按内容自适应，居中显示。
    @ViewBuilder
    private var secondaryRow: some View {
        if editor.secondaryBarVisible {
            secondaryControl
                .frame(height: ScreenshotToolbarMetrics.secondaryRowHeight)
                .padding(.horizontal, ScreenshotToolbarMetrics.secondaryRowHorizontalPadding)
                .screenshotToolbarPill()
        }
    }

    /// 主按钮行自己是一条胶囊。格子来自 `ScreenshotToolbarComposition`，这里不再另列一份。
    private var mainToolRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(ScreenshotToolbarComposition.mainRow.enumerated()), id: \.offset) { _, slot in
                toolbarSlot(slot)
            }
        }
    }

    @ViewBuilder
    private func toolbarSlot(_ slot: ScreenshotToolbarSlot) -> some View {
        switch slot {
        case let .tool(tool):
            toolButton(tool)
        case .translate:
            translationButton
        case .undo:
            actionButton(icon: "arrow.uturn.backward", help: "撤销", enabled: editor.canUndo) {
                onAction(.undo)
            }
        case .redo:
            actionButton(icon: "arrow.uturn.forward", help: "重做", enabled: editor.canRedo) {
                onAction(.redo)
            }
        case .save:
            actionButton(
                icon: "square.and.arrow.down",
                help: "保存",
                enabled: !editor.translationState.isRunning && !editor.isExporting
            ) {
                onAction(.saveRequested)
            }
        case .pin:
            actionButton(
                icon: "pin",
                help: "贴图",
                enabled: !editor.translationState.isRunning && !editor.isExporting
            ) {
                onAction(.pinRequested)
            }
        case .cancel:
            actionButton(
                icon: "xmark",
                help: "取消",
                // 取消不受翻译/导出状态限制：它们是唯一能退出会话的方式，
                // 灰掉就只剩 Esc 一条路（而 Esc 恰恰是最不容易被想到的）。
                enabled: true,
                iconColor: .red
            ) {
                onAction(.cancel)
            }
        case .confirm:
            actionButton(
                icon: "checkmark",
                help: "完成",
                enabled: !editor.translationState.isRunning && !editor.isExporting,
                iconColor: .green
            ) {
                onAction(.confirmRequested)
            }
        case .divider:
            toolbarDivider
        }
    }

    private func toolButton(_ tool: ScreenshotTool) -> some View {
        Button {
            let isDeselecting = editor.selectedTool == tool
            editor.selectTool(isDeselecting ? nil : tool)
            // 取消选中的那一下不能再上报「已选择某某工具」——状态栏会写着工具已激活，
            // 而编辑器里其实没有工具，用户照着提示去拖拽什么都不会发生。
            if !isDeselecting {
                onAction(.tool(tool))
            }
        } label: {
            Group {
                if tool == .text {
                    Text("T")
                        .font(
                            .system(
                                size: ScreenshotToolbarIconMetrics.textPointSize,
                                weight: .regular,
                                design: .serif
                            )
                        )
                } else if tool == .mosaic {
                    // 自绘图标不吃外层的 foregroundStyle，得自己跟上：选中的底色就是
                    // accent，图标再用 accent 画就整个糊在一起了。
                    MosaicToolIcon(
                        color: editor.selectedTool == tool ? Color.white : Color.secondary
                    )
                } else {
                    Image(systemName: tool.icon)
                        .font(
                            .system(
                                size: ScreenshotToolbarIconMetrics.pointSize(for: tool.icon),
                                weight: .medium
                            )
                        )
                }
            }
            // 选中就是胶囊，和二级行、别的模块的分段控件同一套（`jarvisSelectionPill`）：
            // 42 高的胶囊嵌在 64 高的行里，四边各让出 11——正好是行高减按钮高的一半，
            // 圆头和行胶囊同心。原来只把图标染成 accent、没有胶囊，「选中了哪个」在
            // 一排图标里要靠颜色去猜。
            .foregroundStyle(editor.selectedTool == tool ? Color.white : Color.secondary)
            .frame(
                width: ScreenshotToolbarIconMetrics.box,
                height: ScreenshotToolbarIconMetrics.box
            )
            .frame(
                width: ScreenshotToolbarMetrics.mainButtonSize,
                height: ScreenshotToolbarMetrics.mainButtonSize
            )
            .jarvisSelectionPill(
                isSelected: editor.selectedTool == tool,
                isHovered: hoveredTool == tool
            )
            // 命中区仍是整块 42×42：胶囊只管观感。改成 Capsule 会把这颗按钮四角
            // 约两成面积变成点不动的死区，同一行里别的按钮却还是矩形。
            .contentShape(Rectangle())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.76))
        .animation(
            JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion),
            value: hoveredTool
        )
        .onHover { isHovering in
            withAnimation(
                JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion)
            ) {
                if isHovering {
                    hoveredTool = tool
                } else if hoveredTool == tool {
                    hoveredTool = nil
                }
            }
        }
        .help(tool.title)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(editor.selectedTool == tool ? .isSelected : [])
        .disabled(editor.translationState.isRunning)
    }

    /// 点一下展开二级栏，再点一下收起。翻译本身由二级栏里的「开始翻译」发起。
    private var translationButton: some View {
        Button {
            editor.toggleTranslationMode()
        } label: {
            if editor.translationState.isRunning {
                ProgressView()
                    .controlSize(.small)
            } else {
                ScreenshotTranslationIcon(
                    isSelected: editor.translationMode,
                    selectedColor: .white
                )
            }
        }
        .frame(
            width: ScreenshotToolbarMetrics.mainButtonSize,
            height: ScreenshotToolbarMetrics.mainButtonSize
        )
        // 翻译按钮和四个工具按钮同在一个容器里，选中态就得是同一枚胶囊；
        // 只给图标染色的话，这一排里就剩它一个「选了没选要靠猜」。
        .jarvisSelectionPill(isSelected: editor.translationMode, isHovered: isHoveringTranslation)
        .contentShape(Rectangle())
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.76))
        .animation(
            JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion),
            value: isHoveringTranslation
        )
        .onHover { isHoveringTranslation = $0 }
        .help("截图翻译")
        .accessibilityLabel("截图翻译")
        .accessibilityAddTraits(editor.translationMode ? .isSelected : [])
        .disabled(editor.translationState.isRunning)
    }

    @ViewBuilder
    private var secondaryControl: some View {
        if editor.translationMode {
            translationControl
        } else if editor.selectedTool == .arrow {
            arrowStyleControl
        } else if editor.selectedTool == .rectangle {
            rectangleStyleControl
        } else if editor.selectedTool == .pen {
            penStyleControl
        } else if editor.selectedTool == .mosaic {
            mosaicStyleControl
        } else if editor.selectedTool == .text {
            textStyleControl
        }
    }

    private var translationControl: some View {
        HStack(spacing: 8) {
            Text("目标语言")
                .font(JarvisTypography.control)
                .foregroundStyle(Color.secondary)

            TranslationLanguageChip(
                title: editor.translationTargetLanguage.title,
                selected: editor.translationTargetLanguage
            ) { language in
                editor.translationTargetLanguage = language
                UserDefaults.standard.set(
                    language.rawValue,
                    forKey: ScreenshotTranslationConfiguration.targetLanguageKey
                )
            }

            SecondaryCapsuleButton(
                title: editor.translationActionTitle,
                isProminent: true,
                isEnabled: !editor.translationState.isRunning
            ) {
                onAction(.startTranslation)
            }

            SecondaryCapsuleButton(
                title: editor.translationVisible ? "显示原文" : "显示译文",
                isEnabled: !editor.translationState.isRunning && !editor.translationBlocks.isEmpty
            ) {
                onAction(.toggleTranslationVisibility)
            }
        }
    }

    private var arrowStyleControl: some View {
        strokeStyleControl(color: editor.arrowColor, width: $editor.arrowLineWidth) { color in
            editor.arrowColor = color
        }
    }

    private var rectangleStyleControl: some View {
        strokeStyleControl(color: editor.rectangleColor, width: $editor.rectangleLineWidth) { color in
            editor.rectangleColor = color
        }
    }

    private var penStyleControl: some View {
        strokeStyleControl(color: editor.penColor, width: $editor.penLineWidth) { color in
            editor.penColor = color
        }
    }

    private func strokeStyleControl(
        color: ScreenshotTextColor,
        width: Binding<CGFloat>,
        setColor: @escaping (ScreenshotTextColor) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            colorButtons(selected: color, action: setColor)
            secondaryDivider
            ScreenshotStrokeStagePicker(width: width)
        }
    }

    /// 马赛克的全部控件装在同一条胶囊里：模式、效果、笔触是一个整体的工具设置，
    /// 原来各占一块玻璃再加一条裸滑杆，看着像三件互不相干的东西。
    private var mosaicStyleControl: some View {
        HStack(spacing: 8) {
            mosaicModePicker

            secondaryDivider

            mosaicEffectPicker

            if editor.mosaicMode == .brush {
                secondaryDivider
                mosaicBrushSizeControl
            }
        }
    }

    private var mosaicModePicker: some View {
        HStack(spacing: 2) {
            ForEach(ScreenshotMosaicMode.allCases) { mode in
                ScreenshotToolbarOptionButton(
                    icon: mode.icon,
                    title: mode.title,
                    selected: editor.mosaicMode == mode,
                    help: mode.title
                ) {
                    editor.mosaicMode = mode
                }
            }
        }
    }

    private var mosaicEffectPicker: some View {
        HStack(spacing: 2) {
            ForEach(ScreenshotMosaicStyle.allCases) { style in
                ScreenshotToolbarOptionButton(
                    icon: style.icon,
                    title: style.title,
                    selected: editor.mosaicStyle == style,
                    help: style.title
                ) {
                    editor.mosaicStyle = style
                }
            }
        }
    }

    /// 二级行里分组之间的竖线。
    private var secondaryDivider: some View {
        Rectangle()
            .fill(ScreenshotToolbarDivider.color)
            .frame(width: 1, height: 22)
    }

    private var mosaicBrushSizeControl: some View {
        HStack(spacing: 6) {
            Text("笔触")
                .font(JarvisTypography.control)
                .foregroundStyle(Color.secondary)

            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(Color.secondary)

            Slider(value: $editor.mosaicBrushSize, in: 8 ... 72, step: 2)
                .frame(width: 76)

            Image(systemName: "circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color.secondary)
        }
    }

    private var textStyleControl: some View {
        HStack(spacing: 8) {
            colorButtons(selected: editor.textColor) { color in
                editor.textColor = color
            }

            secondaryDivider

            HStack(spacing: 2) {
                ScreenshotToolbarOptionButton(
                    icon: "bold",
                    selected: editor.textBold,
                    help: "粗体"
                ) {
                    editor.textBold.toggle()
                }
                ScreenshotToolbarOptionButton(
                    icon: "italic",
                    selected: editor.textItalic,
                    help: "斜体"
                ) {
                    editor.textItalic.toggle()
                }
                ScreenshotToolbarOptionButton(
                    icon: "strikethrough",
                    selected: editor.textStrikethrough,
                    help: "删除线"
                ) {
                    editor.textStrikethrough.toggle()
                }
            }

            secondaryDivider

            HStack(spacing: 2) {
                ForEach(ScreenshotTextSize.options) { option in
                    ScreenshotToolbarOptionButton(
                        title: option.title,
                        selected: editor.textFontSize == option.size,
                        help: option.title
                    ) {
                        editor.textFontSize = option.size
                    }
                }
            }
        }
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
                                    selected == color ? Color.jarvisAccent : Color.primary.opacity(0.2),
                                    lineWidth: selected == color ? 2 : 1
                                )
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.76))
            }
        }
    }

    private func actionButton(
        icon: String,
        help: String,
        enabled: Bool = true,
        iconColor: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let actionKind = help
        let tint = iconColor ?? Color.secondary
        return Button(action: action) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: ScreenshotToolbarIconMetrics.pointSize(for: icon),
                        weight: .medium
                    )
                )
                .foregroundStyle(enabled ? tint : tint.opacity(0.35))
                .frame(
                    width: ScreenshotToolbarIconMetrics.box,
                    height: ScreenshotToolbarIconMetrics.box
                )
                .frame(
                    width: ScreenshotToolbarMetrics.mainButtonSize,
                    height: ScreenshotToolbarMetrics.mainButtonSize
                )
                .jarvisSelectionPill(isSelected: false, isHovered: hoveredAction == actionKind)
                .contentShape(Rectangle())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.76))
        .animation(
            JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion),
            value: hoveredAction
        )
        .onHover { isHovering in
            withAnimation(
                JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion)
            ) {
                if isHovering {
                    hoveredAction = actionKind
                } else if hoveredAction == actionKind {
                    hoveredAction = nil
                }
            }
        }
        .help(help)
        .accessibilityLabel(help)
        .disabled(!enabled)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(ScreenshotToolbarDivider.color)
            .frame(width: ScreenshotToolbarMetrics.dividerLineWidth, height: 28)
            .padding(.horizontal, ScreenshotToolbarMetrics.dividerHorizontalPadding)
    }
}
