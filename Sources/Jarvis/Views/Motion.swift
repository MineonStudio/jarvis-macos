import SwiftUI

enum JarvisMotion {
    // Keep the motion vocabulary small and physical. The lower response values
    // are reserved for controls; larger surfaces get a softer settle.
    static let buttonPress = Animation.spring(response: 0.16, dampingFraction: 0.78, blendDuration: 0.02)
    static let hover = Animation.spring(response: 0.24, dampingFraction: 0.82, blendDuration: 0.03)
    static let selection = Animation.spring(response: 0.30, dampingFraction: 0.82, blendDuration: 0.04)
    static let content = Animation.spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.03)
    static let feedback = Animation.spring(response: 0.42, dampingFraction: 0.80, blendDuration: 0.03)
    static let pageTransition = Animation.spring(response: 0.38, dampingFraction: 0.86, blendDuration: 0.05)
    static let selectionPillTint = Color.accentColor.opacity(0.82)

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

struct JarvisHoverModifier<HoverShape: Shape>: ViewModifier {
    let shape: HoverShape
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .overlay {
                shape
                    .stroke(
                        Color.accentColor.opacity(isHovered ? 0.16 : 0),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            .scaleEffect(isHovered && !reduceMotion ? scale : 1)
            .zIndex(isHovered ? 1 : 0)
            .animation(
                JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion),
                value: isHovered
            )
            .onHover { isHovered = $0 }
    }
}

struct JarvisHoverHighlightModifier<HoverShape: Shape>: ViewModifier {
    let shape: HoverShape
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(Color.accentColor.opacity(isHovered ? 0.12 : 0))
                    .allowsHitTesting(false)
            }
            .scaleEffect(isHovered && !reduceMotion ? scale : 1)
            .zIndex(isHovered ? 1 : 0)
            .animation(
                JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion),
                value: isHovered
            )
            .onHover { isHovered = $0 }
    }
}

struct JarvisHoverPanelModifier: ViewModifier {
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var isScaled: Bool {
        isHovered && !reduceMotion
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(isScaled ? scale : 1)
            .zIndex(isHovered ? 1 : 0)
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

    func jarvisHoverHighlight(
        in shape: some Shape,
        scale: CGFloat = 1.01
    ) -> some View {
        modifier(JarvisHoverHighlightModifier(shape: shape, scale: scale))
    }

    func jarvisHoverPanelFeedback(
        scale: CGFloat = 1.03
    ) -> some View {
        modifier(JarvisHoverPanelModifier(scale: scale))
    }
}

private struct JarvisSegmentedItemFramePreferenceKey: PreferenceKey {
    static let defaultValue: [AnyHashable: CGRect] = [:]

    static func reduce(
        value: inout [AnyHashable: CGRect],
        nextValue: () -> [AnyHashable: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct JarvisSegmentedControl<Item: Identifiable & Equatable, Label: View>: View {
    let items: [Item]
    @Binding var selection: Item
    private let label: (Item, Bool) -> Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var itemFrames: [AnyHashable: CGRect] = [:]
    @State private var hoveredItemID: AnyHashable?

    init(
        items: [Item],
        selection: Binding<Item>,
        @ViewBuilder label: @escaping (Item, Bool) -> Label
    ) {
        self.items = items
        _selection = selection
        self.label = label
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let selectedFrame = itemFrames[AnyHashable(selection.id)] {
                Capsule()
                    .fill(JarvisMotion.selectionPillTint)
                    .frame(width: selectedFrame.width, height: selectedFrame.height)
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
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: hoveredFrame.width, height: hoveredFrame.height)
                    .offset(x: hoveredFrame.minX, y: hoveredFrame.minY)
                    .allowsHitTesting(false)
                    .animation(
                        JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion),
                        value: hoveredItemID
                    )
            }

            HStack(spacing: 2) {
                ForEach(items) { item in
                    Button {
                        selection = item
                    } label: {
                        label(item, selection == item)
                            .contentShape(Capsule())
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
                    }
                    .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.9))
                    .contentShape(Capsule())
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
            .animation(
                JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
                value: selection
            )
        }
        .coordinateSpace(name: "JarvisSegmentedControl")
        .padding(JarvisMetrics.segmentedControlPadding)
        .jarvisGlass(in: Capsule(), interactive: true)
        .onPreferenceChange(JarvisSegmentedItemFramePreferenceKey.self) { frames in
            itemFrames = frames
        }
    }
}
