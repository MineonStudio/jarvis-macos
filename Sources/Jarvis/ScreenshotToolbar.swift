import SwiftUI

// MARK: - Screenshot editing toolbar

struct ScreenshotToolbar: View {
    static let baseWidth = ScreenshotToolbarMetrics.baseWidth

    static func preferredWidth(
        for tool: ScreenshotTool?,
        mosaicMode: ScreenshotMosaicMode = .rectangle
    ) -> CGFloat {
        switch tool {
        case .mosaic: mosaicMode == .brush ? 520 : baseWidth
        case .text: 520
        case .arrow: 520
        default: baseWidth
        }
    }

    @ObservedObject var editor: ScreenshotEditorModel
    @ObservedObject var layout: ScreenshotToolbarLayoutModel
    @ObservedObject var translationProgress: ScreenshotTranslationProgress
    let onAction: (ScreenshotAction) -> Void
}

extension ScreenshotToolbar {
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
            height: editor.secondaryBarVisible
                ? ScreenshotToolbarMetrics.expandedHeight
                : ScreenshotToolbarMetrics.compactHeight
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
                        color: editor.selectedTool == tool ? Color.accentColor : Color.secondary
                    )
                } else {
                    Image(systemName: tool.icon)
                        .font(.system(size: 21, weight: .medium))
                }
            }
            .foregroundStyle(editor.selectedTool == tool ? Color.accentColor : Color.secondary)
            .frame(width: 24, height: 24)
            .frame(width: 42, height: 42)
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
                    ForEach(0 ..< 2, id: \.self) { row in
                        HStack(spacing: 2) {
                            ForEach(0 ..< 2, id: \.self) { column in
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

            Slider(value: $editor.arrowLineWidth, in: 2 ... 12, step: 1)
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

            Slider(value: $editor.mosaicBrushSize, in: 8 ... 72, step: 2)
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

            Slider(value: $editor.textFontSize, in: 12 ... 48, step: 1)
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
                .foregroundStyle(enabled ? (selected ? Color.accentColor : Color.secondary) : Color.secondary.opacity(0.35))
                .frame(width: 24, height: 24)
                .frame(width: 42, height: 42)
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
