import SwiftUI

struct JarvisOrbMark: View {
    @Environment(\.colorScheme) private var colorScheme

    let diameter: CGFloat

    init(diameter: CGFloat = 24) {
        self.diameter = diameter
    }

    private var orbColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var eyeColor: Color {
        colorScheme == .dark ? .black : .white
    }

    var body: some View {
        Circle()
            .fill(orbColor)
            .overlay {
                HStack(spacing: diameter * 0.174) {
                    Capsule()
                        .fill(eyeColor)
                        .frame(width: diameter * 0.152, height: diameter * 0.319)
                    Capsule()
                        .fill(eyeColor)
                        .frame(width: diameter * 0.152, height: diameter * 0.319)
                }
                .offset(y: -diameter * 0.138)
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.16),
                radius: diameter * 0.08,
                y: diameter * 0.043
            )
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}

enum JarvisOrbMood: Equatable, Sendable {
    case idle
    case listening
    case thinking
    case working
    case speaking
    case trouble

    static func from(
        isSending: Bool,
        progress: String,
        isListening: Bool,
        isSpeaking: Bool,
        lastAssistantText: String
    ) -> Self {
        if isSending {
            if progress.contains("额度") || progress.contains("重试") || progress.contains("失败") {
                return .trouble
            }
            if progress.hasPrefix("已完成") || progress.hasPrefix("已取消") {
                return .working
            }
            return .thinking
        }
        if lastAssistantText.hasPrefix("Hermes 对话失败")
            || lastAssistantText.contains("额度已用完")
        {
            return isListening ? .listening : .trouble
        }
        if isSpeaking {
            return .speaking
        }
        if isListening {
            return .listening
        }
        return .idle
    }
}

struct JarvisOrbView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let mood: JarvisOrbMood
    let pulse: Int

    @State private var gazeOffset: CGSize = .zero
    @State private var isBlinking = false
    @State private var isTapBouncing = false
    @State private var isNodding = false
    @State private var dragSquash: CGFloat = 0
    @State private var isDragging = false
    @State private var breath: CGFloat = 0

    private let orbDiameter: CGFloat
    private let maximumDragDistance: CGFloat

    init(diameter: CGFloat = 276, mood: JarvisOrbMood = .idle, pulse: Int = 0) {
        orbDiameter = diameter
        self.mood = mood
        self.pulse = pulse
        maximumDragDistance = diameter * 0.65
    }

    private var orbColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var eyeColor: Color {
        colorScheme == .dark ? .black : .white
    }

    var body: some View {
        Circle()
            .fill(orbColor)
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.10), lineWidth: 1)
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.16),
                radius: 22,
                y: 12
            )
            .overlay {
                HStack(spacing: orbDiameter * 0.174) {
                    JarvisOrbEye(
                        eyeColor: eyeColor,
                        closeAmount: eyeCloseAmount,
                        width: orbDiameter * 0.152,
                        height: orbDiameter * 0.319
                    )
                    JarvisOrbEye(
                        eyeColor: eyeColor,
                        closeAmount: eyeCloseAmount,
                        width: orbDiameter * 0.152,
                        height: orbDiameter * 0.319
                    )
                }
                .offset(x: displayedGaze.width, y: -orbDiameter * 0.138 + displayedGaze.height)
                .animation(
                    JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
                    value: displayedGaze
                )
            }
            .frame(width: orbDiameter, height: orbDiameter)
            .scaleEffect(x: scaleX, y: scaleY)
            .task(id: mood) {
                await gazeLoop()
            }
            .task(id: mood) {
                await blinkLoop()
            }
            .task(id: mood) {
                await applyMoodMotion()
            }
            .onChange(of: mood) { _, newMood in
                if newMood == .speaking {
                    triggerNod()
                }
            }
            .onChange(of: pulse) { _, _ in
                triggerNod()
            }
            .frame(maxWidth: .infinity)
            .frame(height: orbDiameter + 54)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("JARVIS 动态小球")
            .accessibilityValue(accessibilityMood)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("点击或拖拽触发 Q 弹动画")
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateDrag(value.translation)
                    }
                    .onEnded { _ in
                        finishDrag()
                    }
            )
    }

    private var displayedGaze: CGSize {
        mood == .idle ? gazeOffset : moodGaze
    }

    private var moodGaze: CGSize {
        switch mood {
        case .idle:
            .zero
        case .listening:
            CGSize(width: 0, height: orbDiameter * 0.048)
        case .thinking:
            CGSize(width: -orbDiameter * 0.042, height: -orbDiameter * 0.028)
        case .working:
            CGSize(width: 0, height: orbDiameter * 0.02)
        case .speaking:
            CGSize(width: 0, height: orbDiameter * 0.05)
        case .trouble:
            CGSize(width: orbDiameter * 0.048, height: orbDiameter * 0.012)
        }
    }

    private var eyeCloseAmount: CGFloat {
        if isBlinking {
            return mood == .trouble ? 0.12 : 0.08
        }
        return mood == .trouble ? 0.55 : 1
    }

    private var bounceX: CGFloat {
        if isTapBouncing {
            return 1.10
        }
        if isNodding {
            return 1.05
        }
        return 1
    }

    private var bounceY: CGFloat {
        if isTapBouncing {
            return 0.90
        }
        if isNodding {
            return 0.94
        }
        return 1
    }

    private var troubleFlattenX: CGFloat {
        mood == .trouble ? 1.04 : 1
    }

    private var troubleFlattenY: CGFloat {
        mood == .trouble ? 0.94 : 1
    }

    private var scaleX: CGFloat {
        bounceX * (1 + dragSquash * 0.10) * (1 + breath * 0.03) * troubleFlattenX
    }

    private var scaleY: CGFloat {
        bounceY * (1 - dragSquash * 0.42) * (1 + breath * 0.03) * troubleFlattenY
    }

    private var accessibilityMood: String {
        switch mood {
        case .idle: "空闲，会眨眼并四处观察"
        case .listening: "正在听你输入"
        case .thinking: "正在思考"
        case .working: "正在调用工具"
        case .speaking: "正在回复"
        case .trouble: "遇到问题"
        }
    }

    private func applyMoodMotion() async {
        if mood == .thinking, !reduceMotion, !isDragging {
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                breath = 1
            }
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                breath = 0
            }
        }
    }

    private func triggerNod() {
        guard !reduceMotion, !isDragging else { return }
        withAnimation(.spring(response: 0.16, dampingFraction: 0.52, blendDuration: 0.02)) {
            isNodding = true
        }
        Task {
            guard await pause(for: 0.14) else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.64, blendDuration: 0.03)) {
                isNodding = false
            }
        }
    }

    private func updateDrag(_ translation: CGSize) {
        let distance = hypot(translation.width, translation.height)
        guard distance > 4 else { return }

        isDragging = true
        isTapBouncing = false
        isNodding = false
        breath = 0
        let normalizedDistance = min(distance / maximumDragDistance, 1)

        if reduceMotion {
            dragSquash = normalizedDistance
        } else {
            withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.82, blendDuration: 0.01)) {
                dragSquash = normalizedDistance
            }
        }
    }

    private func finishDrag() {
        guard isDragging else {
            triggerTapBounce()
            return
        }

        isDragging = false
        withAnimation(
            JarvisMotion.animation(
                .spring(response: 0.32, dampingFraction: 0.56, blendDuration: 0.03),
                reduceMotion: reduceMotion
            )
        ) {
            dragSquash = 0
        }
        Task {
            await applyMoodMotion()
        }
    }

    private func triggerTapBounce() {
        guard !reduceMotion else { return }

        withAnimation(.spring(response: 0.18, dampingFraction: 0.46, blendDuration: 0.02)) {
            isTapBouncing = true
        }

        Task {
            guard await pause(for: 0.16) else { return }
            withAnimation(.spring(response: 0.24, dampingFraction: 0.62, blendDuration: 0.03)) {
                isTapBouncing = false
            }
        }
    }

    private func gazeLoop() async {
        guard !reduceMotion, mood == .idle else { return }

        while !Task.isCancelled {
            guard await pause(for: Double.random(in: 0.55 ... 1.45)) else { return }
            guard !isDragging else { continue }

            withAnimation(.spring(response: 0.24, dampingFraction: 0.72, blendDuration: 0.02)) {
                gazeOffset = CGSize(
                    width: CGFloat.random(in: -orbDiameter * 0.05 ... orbDiameter * 0.05),
                    height: CGFloat.random(in: -orbDiameter * 0.03 ... orbDiameter * 0.03)
                )
            }
        }
    }

    private func blinkLoop() async {
        guard !reduceMotion else { return }

        while !Task.isCancelled {
            let interval = switch mood {
            case .idle: Double.random(in: 1.8 ... 4.2)
            case .listening: Double.random(in: 3.4 ... 6.0)
            case .thinking: Double.random(in: 2.6 ... 5.0)
            case .working: Double.random(in: 1.2 ... 2.4)
            case .speaking: Double.random(in: 1.6 ... 2.8)
            case .trouble: Double.random(in: 3.2 ... 5.5)
            }
            guard await pause(for: interval) else { return }

            withAnimation(.easeInOut(duration: 0.08)) {
                isBlinking = true
            }

            guard await pause(for: 0.12) else { return }
            withAnimation(.easeInOut(duration: 0.12)) {
                isBlinking = false
            }
        }
    }

    private func pause(for seconds: Double) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

private struct JarvisOrbEye: View {
    let eyeColor: Color
    let closeAmount: CGFloat
    var width: CGFloat = 42
    var height: CGFloat = 88

    var body: some View {
        Capsule()
            .fill(eyeColor)
            .frame(width: width, height: height)
            .scaleEffect(y: closeAmount)
            .animation(.easeInOut(duration: 0.10), value: closeAmount)
    }
}
