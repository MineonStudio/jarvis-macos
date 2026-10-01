import SwiftUI

enum JarvisMotion {
    // Keep the motion vocabulary small and physical. The lower response values
    // are reserved for controls; larger surfaces get a softer settle.
    static let buttonPress = Animation.spring(response: 0.16, dampingFraction: 0.78, blendDuration: 0.02)
    static let hover = Animation.spring(response: 0.24, dampingFraction: 0.82, blendDuration: 0.03)
    static let selection = Animation.spring(response: 0.30, dampingFraction: 0.82, blendDuration: 0.04)
    static let sidebarSelection = Animation.easeOut(duration: 0.18)
    static let content = Animation.spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.03)
    static let accordion = Animation.easeInOut(duration: 0.22)
    static let feedback = Animation.spring(response: 0.42, dampingFraction: 0.80, blendDuration: 0.03)
    @MainActor
    static var selectionPillTint: Color {
        Color.jarvisAccent.opacity(0.82)
    }

    static let hoverPillTint = Color.primary.opacity(0.10)

    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    static func contentTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .identity
            : .opacity.combined(with: .scale(scale: 0.985, anchor: .center))
    }
}

struct JarvisPressButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.98
    var pressedOpacity: Double = 0.78

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .scaleEffect(
                reduceMotion
                    ? 1
                    : (configuration.isPressed ? pressedScale : 1)
            )
            .animation(
                JarvisMotion.animation(JarvisMotion.buttonPress, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

/// The icon-button treatment used by the chat toolbar and shared by all
/// module toolbars. The button itself owns the 32-point hit target; callers
/// only provide the icon, tint, action, and hover feedback shape.
struct JarvisToolbarIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(
                width: JarvisToolbarMetrics.controlSize,
                height: JarvisToolbarMetrics.controlSize
            )
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.76 : 1)
            .scaleEffect(
                reduceMotion
                    ? 1
                    : (configuration.isPressed ? 0.94 : 1)
            )
            .animation(
                JarvisMotion.animation(JarvisMotion.buttonPress, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

/// 工具栏上的图标按钮。
///
/// 截图、剪贴板、会议和网页四个模块原本各写一份同样的私有 helper，四处已经开始
/// 分叉——网页那份漏了无障碍标签，读屏软件只会念出图标名。
struct JarvisToolbarIconButton: View {
    let systemName: String
    let help: String
    var tint: Color = .secondary
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: JarvisToolbarMetrics.iconSize, weight: .medium))
                .foregroundStyle(tint)
        }
        .buttonStyle(JarvisToolbarIconButtonStyle())
        .opacity(isEnabled ? 1 : 0.38)
        .disabled(!isEnabled)
        .accessibilityLabel(help)
        .jarvisHoverFeedback(in: Circle(), scale: 1.06)
    }
}

struct JarvisHoverModifier<HoverShape: Shape>: ViewModifier {
    let shape: HoverShape
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(isHovered ? JarvisMotion.hoverPillTint : .clear)
                    .allowsHitTesting(false)
            }
            .scaleEffect(isHovered && !reduceMotion ? scale : 1)
            .zIndex(isHovered && scale != 1 ? 1 : 0)
            .animation(
                JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion),
                value: isHovered
            )
            .onHover { isHovered = $0 }
    }
}

extension View {
    func jarvisHoverFeedback(
        in shape: some Shape,
        scale: CGFloat = 1.01
    ) -> some View {
        modifier(JarvisHoverModifier(shape: shape, scale: scale))
    }
}

private struct JarvisSegmentedItemFramePreferenceKey: PreferenceKey {
    nonisolated(unsafe) static let defaultValue: [AnyHashable: CGRect] = [:]

    static func reduce(
        value: inout [AnyHashable: CGRect],
        nextValue: () -> [AnyHashable: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// 通用分段控件：一层胶囊容器 + 一枚跟着选中项走的胶囊。
///
/// 容器高度是内容撑出来的（选项 + `segmentedControlPadding` ×2），所以"四边等宽"
/// 按构造成立：内边距既是上下留白，也是左右留白，选中胶囊与容器同心。别的分段容器
/// 若容器高度是写死的，去 `JarvisSegmentedMetrics.padding(containerHeight:itemHeight:)`
/// 取内边距，别再手写一个数。
struct JarvisSegmentedControl<Item: Identifiable & Equatable, Label: View>: View {
    let items: [Item]
    @Binding var selection: Item
    private let label: (Item, Bool) -> Label
    /// 选项框，坐标系在内边距之内。外面要对齐色块时用。
    private let onItemFrames: (([AnyHashable: CGRect]) -> Void)?
    /// 选中胶囊的填充。不传就用当前强调色。
    private let selectionStyle: ((Item) -> AnyShapeStyle)?
    /// 拉满父视图宽度，选项均分。
    private let expands: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var itemFrames: [AnyHashable: CGRect] = [:]
    @State private var hoveredItemID: AnyHashable?

    init(
        items: [Item],
        selection: Binding<Item>,
        expands: Bool = false,
        onItemFrames: (([AnyHashable: CGRect]) -> Void)? = nil,
        selectionStyle: ((Item) -> AnyShapeStyle)? = nil,
        @ViewBuilder label: @escaping (Item, Bool) -> Label
    ) {
        self.items = items
        _selection = selection
        self.expands = expands
        self.onItemFrames = onItemFrames
        self.selectionStyle = selectionStyle
        self.label = label
    }

    var body: some View {
        segmentRow
            .frame(maxWidth: expands ? .infinity : nil)
            .animation(
                JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
                value: selection
            )
            .background(alignment: .topLeading) {
                // 强调色自己把整段涂上。这里只画主题那条跟着走的选中胶囊。
                if selectionStyle == nil, let selectedFrame = itemFrames[AnyHashable(selection.id)] {
                    Color.clear
                        .frame(width: selectedFrame.width, height: selectedFrame.height)
                        .background(JarvisMotion.selectionPillTint, in: Capsule())
                        .offset(x: selectedFrame.minX, y: selectedFrame.minY)
                        .allowsHitTesting(false)
                        .animation(
                            JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
                            value: selection
                        )
                }

                if let hoveredItemID,
                   hoveredItemID != AnyHashable(selection.id),
                   let hoveredFrame = itemFrames[hoveredItemID]
                {
                    Capsule()
                        .fill(JarvisMotion.hoverPillTint)
                        .frame(width: hoveredFrame.width, height: hoveredFrame.height)
                        .offset(x: hoveredFrame.minX, y: hoveredFrame.minY)
                        .allowsHitTesting(false)
                        .animation(
                            JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion),
                            value: hoveredItemID
                        )
                }
            }
            .coordinateSpace(name: "JarvisSegmentedControl")
            .padding(JarvisMetrics.segmentedControlPadding)
            .frame(maxWidth: expands ? .infinity : nil)
            .jarvisGlass(in: Capsule(), interactive: true)
            .onPreferenceChange(JarvisSegmentedItemFramePreferenceKey.self) { frames in
                guard itemFrames != frames else { return }
                itemFrames = frames
                onItemFrames?(frames)
            }
    }

    @ViewBuilder
    private var segmentRow: some View {
        if expands {
            JarvisEqualWidthHStack(spacing: JarvisMetrics.segmentedItemSpacing) {
                ForEach(items) { item in
                    segmentButton(item)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: JarvisMetrics.segmentedItemSpacing) {
                ForEach(items) { item in
                    segmentButton(item)
                }
            }
        }
    }

    private func segmentButton(_ item: Item) -> some View {
        Button {
            selection = item
        } label: {
            label(item, selection == item)
                .contentShape(Capsule())
        }
        .buttonStyle(JarvisSegmentButtonStyle(expands: expands))
        .frame(maxWidth: expands ? .infinity : nil)
        .contentShape(Capsule())
        // 量按钮本身。选中项的标签可能是空的，量标签会得到零宽。
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: JarvisSegmentedItemFramePreferenceKey.self,
                    value: [
                        AnyHashable(item.id): proxy.frame(
                            in: .named("JarvisSegmentedControl")
                        )
                    ]
                )
            }
        }
        .onHover { isHovered in
            let itemID = AnyHashable(item.id)
            if isHovered {
                hoveredItemID = itemID
            } else if hoveredItemID == itemID {
                hoveredItemID = nil
            }
        }
    }
}

/// 拉满时每个选项同一宽度。空标签的理想宽度是 0，普通 HStack 会把它挤没。
private struct JarvisEqualWidthHStack: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        let spacingWidth = spacing * CGFloat(max(subviews.count - 1, 0))
        let width = proposal.width ?? (
            subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +) + spacingWidth
        )
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard !subviews.isEmpty else { return }
        let spacingWidth = spacing * CGFloat(subviews.count - 1)
        let itemWidth = max(0, (bounds.width - spacingWidth) / CGFloat(subviews.count))
        var x = bounds.minX
        for subview in subviews {
            subview.place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: itemWidth, height: nil)
            )
            x += itemWidth + spacing
        }
    }
}

/// 分段按钮。拉满时标签跟着按钮一样宽，选中色才铺得满整段。
private struct JarvisSegmentButtonStyle: ButtonStyle {
    var expands: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: expands ? .infinity : nil)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(
                reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1)
            )
            .animation(
                JarvisMotion.animation(JarvisMotion.buttonPress, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}
