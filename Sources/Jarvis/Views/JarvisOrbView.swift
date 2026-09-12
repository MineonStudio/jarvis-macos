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

struct JarvisOrbView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var gazeOffset: CGSize = .zero
    @State private var isBlinking = false
    @State private var isTapBouncing = false
    @State private var dragSquash: CGFloat = 0
    @State private var isDragging = false

    private let orbDiameter: CGFloat
    private let maximumDragDistance: CGFloat

    init(diameter: CGFloat = 276) {
        orbDiameter = diameter
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
            .task {
                await gazeLoop()
            }
            .task {
                await blinkLoop()
            }
            .frame(maxWidth: .infinity)
            .frame(height: orbDiameter + 54)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("JARVIS 动态小球")
            .accessibilityValue("空闲，会眨眼并四处观察")
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
        gazeOffset
    }

    private var eyeCloseAmount: CGFloat {
        isBlinking ? 0.08 : 1
    }

    private var bounceX: CGFloat {
        if isTapBouncing {
            return 1.10
        }
        return 1
    }

    private var bounceY: CGFloat {
        if isTapBouncing {
            return 0.90
        }
        return 1
    }

    private var scaleX: CGFloat {
        bounceX * (1 + dragSquash * 0.10)
    }

    private var scaleY: CGFloat {
        bounceY * (1 - dragSquash * 0.42)
    }

    private func updateDrag(_ translation: CGSize) {
        let distance = hypot(translation.width, translation.height)
        guard distance > 4 else { return }

        isDragging = true
        isTapBouncing = false
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
        guard !reduceMotion else { return }

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
            guard await pause(for: Double.random(in: 1.8 ... 4.2)) else { return }

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
