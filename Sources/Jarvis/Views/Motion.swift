import SwiftUI

enum JarvisMotion {
    static let buttonPress = Animation.easeOut(duration: 0.12)
    static let hover = Animation.easeOut(duration: 0.16)
    static let selection = Animation.easeInOut(duration: 0.2)
    static let pageTransition = Animation.easeInOut(duration: 0.24)

    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
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

struct JarvisHoverPanelModifier: ViewModifier {
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var isScaled: Bool {
        isHovered && !reduceMotion
    }

    func body(content: Content) -> some View {
        content
            .background {
                Color.clear
                    .jarvisGlass(cornerRadius: 13, interactive: false)
                    .scaleEffect(isScaled ? scale : 1)
            }
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
                    .fill(Color.accentColor.opacity(0.82))
                    .frame(width: selectedFrame.width, height: selectedFrame.height)
                    .offset(x: selectedFrame.minX, y: selectedFrame.minY)
                    .allowsHitTesting(false)
                    .animation(
                        JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
                        value: selection
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
                }
            }
        }
        .coordinateSpace(name: "JarvisSegmentedControl")
        .padding(JarvisMetrics.segmentedControlPadding)
        .jarvisGlass(in: Capsule(), interactive: true)
        .onPreferenceChange(JarvisSegmentedItemFramePreferenceKey.self) { frames in
            itemFrames = frames
        }
    }
}
