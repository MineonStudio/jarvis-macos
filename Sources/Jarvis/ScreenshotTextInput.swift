import AppKit
import SwiftUI

/// 截图上的单行文字输入。
///
/// 为什么不直接用 SwiftUI 的控件：
/// - `TextEditor` 是滚动的，滚动条去不干净（内容一多就冒出来）。
/// - `TextField` / `TextEditor` 都带自己的内容内边距，而那个内边距是看不到又改不掉的：
///   光标停在一处、确认之后文字却落在偏左上一点，差的就是它。
///
/// 自己拿 `NSTextView` 搭可以把 `textContainerInset` 和 `lineFragmentPadding` 都归零，
/// 于是**文字起点就是视图原点**——把视图放在锚点上，光标就和确认后的文字严丝合缝。
/// 顺带：回车即确认（单行，不插换行）、拖动整段文字（而不是框选文字）也都在这里控制。
struct ScreenshotSingleLineTextInput: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let isBold: Bool
    let isItalic: Bool
    let isStrikethrough: Bool
    let color: NSColor
    /// 回车：确认。
    let onCommit: () -> Void
    /// 按住文字拖动：位移（画布坐标，y 向下）。
    let onMove: (CGPoint) -> Void

    func makeNSView(context: Context) -> ScreenshotTextInputTextView {
        let textView = ScreenshotTextInputTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.onCommit = onCommit
        textView.onMove = onMove
        textView.string = text
        applyStyle(to: textView)
        return textView
    }

    func updateNSView(_ textView: ScreenshotTextInputTextView, context: Context) {
        textView.onCommit = onCommit
        textView.onMove = onMove
        if textView.string != text {
            textView.string = text
        }
        applyStyle(to: textView)
        // 出现时取一次焦点（输入区在的时候它就是输入口）。只在第一次抢：每次
        // SwiftUI 更新都抢的话，用户点开到别的控件会被又拽回来。
        if !context.coordinator.hasTakenFocusOnce,
           let window = textView.window,
           window.firstResponder !== textView
        {
            context.coordinator.hasTakenFocusOnce = true
            window.makeFirstResponder(textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit)
    }

    private func applyStyle(to textView: ScreenshotTextInputTextView) {
        var font = NSFont.systemFont(ofSize: fontSize, weight: isBold ? .semibold : .regular)
        if isItalic {
            let descriptor = font.fontDescriptor.withSymbolicTraits(
                font.fontDescriptor.symbolicTraits.union(.italic)
            )
            font = NSFont(descriptor: descriptor, size: fontSize) ?? font
        }
        textView.font = font
        textView.textColor = color
        textView.insertionPointColor = color
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: color,
            .strikethroughStyle: isStrikethrough ? NSUnderlineStyle.single.rawValue : 0
        ]
        textView.strikethroughAllText(isStrikethrough)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var hasTakenFocusOnce = false
        private let text: Binding<String>
        private let onCommit: () -> Void

        init(text: Binding<String>, onCommit: @escaping () -> Void) {
            self.text = text
            self.onCommit = onCommit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // 单行：粘贴带进来的换行压成空格，否则用户看不见却会被提交。
            let flattened = textView.string
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            if flattened != textView.string {
                let selected = textView.selectedRange()
                textView.string = flattened
                textView.setSelectedRange(
                    NSRange(location: min(selected.location, flattened.count), length: 0)
                )
            }
            text.wrappedValue = flattened
        }

        /// 回车即确认：单行输入不插换行。
        func textView(_: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            onCommit()
            return true
        }
    }
}

/// 归零了内边距的 `NSTextView`：文字起点等于视图原点。
final class ScreenshotTextInputTextView: NSTextView {
    var onCommit: (() -> Void)?
    /// 拖动整段文字时的位移（已经换算成画布坐标，y 向下）。
    var onMove: ((CGPoint) -> Void)?

    private var dragOrigin: NSPoint?

    // NSTextView 的指定初始化器必须都接上：`init(frame:)` 内部会调
    // `init(frame:textContainer:)`，少写一个，AppKit 一调就撞上 Swift 生成的
    // 「未实现」thunk 直接崩（线上崩过一次）。
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configureForSingleLineEditing()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureForSingleLineEditing()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureForSingleLineEditing() {
        isRichText = false
        isFieldEditor = false
        drawsBackground = false
        isVerticallyResizable = false
        isHorizontallyResizable = false
        allowsUndo = true
        // 单行、不滚动：它是裸的 NSTextView，没有外层滚动视图，也就没有滚动条。
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.maximumNumberOfLines = 1
        textContainer?.widthTracksTextView = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        focusRingType = .none
    }

    /// 回车即确认：单行输入不插换行。
    override func doCommand(by selector: Selector) {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            onCommit?()
            return
        }
        super.doCommand(by: selector)
    }

    /// 把整段文字的删除线状态同步成参数说的那样（逐字改样式）。
    func strikethroughAllText(_ isStrikethrough: Bool) {
        guard let storage = textStorage else { return }
        let range = NSRange(location: 0, length: storage.length)
        storage.addAttribute(
            .strikethroughStyle,
            value: isStrikethrough ? NSUnderlineStyle.single.rawValue : 0,
            range: range
        )
    }

    /// 拖动整段文字，而不是框选文字：按下照常（定位光标），拖动只上报位移。
    override func mouseDown(with event: NSEvent) {
        dragOrigin = event.locationInWindow
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        guard let origin = dragOrigin else { return }
        let current = event.locationInWindow
        // 窗口坐标 y 向上，画布 y 向下。
        onMove?(CGPoint(x: current.x - origin.x, y: origin.y - current.y))
        dragOrigin = current
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        super.mouseUp(with: event)
    }
}
