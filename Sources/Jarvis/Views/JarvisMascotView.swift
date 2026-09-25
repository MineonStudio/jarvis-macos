import AppKit
import SwiftUI

struct JarvisMascotView: View {
    @Environment(AppModel.self) private var app

    @State private var gazeOffset: CGSize = .zero
    @State private var isBlinking = false
    @State private var isBreathing = false
    @State private var isTapBouncing = false
    @State private var isPressed = false
    @State private var isDragging = false
    @State private var dragTranslation: CGSize = .zero
    @State private var dragSquash: CGFloat = 0
    @State private var isCelebrating = false

    let diameter: CGFloat
    let pointerDirection: CGSize?

    private var isPointerTracking: Bool {
        pointerDirection != nil
    }

    private var displayedGazeOffset: CGSize {
        guard let pointerDirection else { return gazeOffset }
        return CGSize(
            width: pointerDirection.width * diameter * 0.022,
            height: pointerDirection.height * diameter * 0.016
        )
    }

    private var fillColor: Color {
        app.activeColorScheme == .dark ? .white : .jarvisAccent
    }

    private var maximumDragDistance: CGFloat {
        diameter * 0.65
    }

    private var dragDistance: CGFloat {
        max(hypot(dragTranslation.width, dragTranslation.height), 1)
    }

    private var dragHorizontalRatio: CGFloat {
        abs(dragTranslation.width) / dragDistance
    }

    private var dragVerticalRatio: CGFloat {
        abs(dragTranslation.height) / dragDistance
    }

    private var scaleX: CGFloat {
        let hoverScale: CGFloat = isPointerTracking ? 1.025 : 1
        let bounceScale: CGFloat = isTapBouncing ? 1.035 : 1
        let dragScale = 1 + dragSquash * (dragHorizontalRatio * 0.16 - dragVerticalRatio * 0.10)
        return hoverScale * bounceScale * dragScale
    }

    private var scaleY: CGFloat {
        let hoverScale: CGFloat = isPointerTracking ? 1.025 : 1
        let bounceScale: CGFloat = isTapBouncing ? 1.035 : 1
        let dragScale = 1 + dragSquash * (dragVerticalRatio * 0.16 - dragHorizontalRatio * 0.26)
        return hoverScale * bounceScale * dragScale
    }

    private var accessibilityStatus: String {
        if isDragging {
            return "正在响应拖拽"
        }
        if isPressed {
            return "正在响应点击"
        }
        if isPointerTracking {
            return "正在注视指针"
        }
        return "待命，会眨眼并环视"
    }

    var body: some View {
        ZStack {
            JarvisMascotBodyShape()
                .fill(fillColor, style: FillStyle(eoFill: true))

            JarvisMascotEyesShape()
                .fill(fillColor)
                .scaleEffect(
                    x: isPointerTracking ? 1.06 : 1,
                    y: isBlinking ? 0.08 : (isPointerTracking ? 1.05 : 1)
                )
                .offset(x: displayedGazeOffset.width, y: displayedGazeOffset.height)
                .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.82), value: displayedGazeOffset)
                .animation(.easeInOut(duration: 0.16), value: isBlinking)

            Image(systemName: "sparkles")
                .font(.system(size: diameter * 0.085, weight: .medium))
                .foregroundStyle(fillColor)
                .offset(x: diameter * 0.38, y: -diameter * 0.34)
                .scaleEffect(isCelebrating ? 1 : 0.25)
                .rotationEffect(.degrees(isCelebrating ? 0 : -35))
                .opacity(isCelebrating ? 1 : 0)
                .animation(.spring(response: 0.24, dampingFraction: 0.56), value: isCelebrating)
                .accessibilityHidden(true)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(x: scaleX, y: scaleY * (isBreathing ? 1.012 : 1))
        .rotationEffect(.degrees((pointerDirection?.width ?? 0) * 2.5))
        .rotation3DEffect(
            .degrees((pointerDirection?.height ?? 0) * -3.5),
            axis: (x: 1, y: 0, z: 0)
        )
        .offset(x: dragTranslation.width * 0.12, y: dragTranslation.height * 0.12)
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: isPointerTracking)
        .animation(.interactiveSpring(response: 0.14, dampingFraction: 0.84), value: pointerDirection?.width)
        .animation(.interactiveSpring(response: 0.14, dampingFraction: 0.84), value: pointerDirection?.height)
        .task {
            await gazeLoop()
        }
        .task {
            await blinkLoop()
        }
        .task {
            await breathingLoop()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jarvis 机器人")
        .accessibilityValue(accessibilityStatus)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("在首页窗口移动指针可注视跟随，点击会弹跳，按住可拖拽")
        .contentShape(Rectangle())
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

    private func updateDrag(_ translation: CGSize) {
        isPressed = true
        dragTranslation = translation
        let distance = hypot(translation.width, translation.height)
        guard distance > 4 else { return }

        isDragging = true
        isTapBouncing = false
        isCelebrating = false
        let normalizedDistance = min(distance / maximumDragDistance, 1)
        let horizontal = min(max(translation.width / maximumDragDistance, -1), 1)
        let vertical = min(max(translation.height / maximumDragDistance, -1), 1)

        withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.82, blendDuration: 0.01)) {
            dragSquash = normalizedDistance
            gazeOffset = CGSize(width: horizontal * diameter * 0.02, height: vertical * diameter * 0.016)
        }
    }

    private func finishDrag() {
        let wasDragging = isDragging
        isPressed = false
        isDragging = false
        dragTranslation = .zero

        withAnimation(.spring(response: 0.32, dampingFraction: 0.56, blendDuration: 0.03)) {
            dragSquash = 0
            if !isPointerTracking {
                gazeOffset = .zero
            }
        }

        if !wasDragging {
            triggerTapBounce()
        }
    }

    private func triggerTapBounce() {
        withAnimation(.spring(response: 0.18, dampingFraction: 0.46, blendDuration: 0.02)) {
            isTapBouncing = true
            isCelebrating = true
        }

        Task {
            guard await pause(for: 0.14) else { return }
            withAnimation(.spring(response: 0.20, dampingFraction: 0.52, blendDuration: 0.02)) {
                isTapBouncing = false
            }
            guard await pause(for: 0.20) else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                isCelebrating = false
            }
        }
    }

    private func gazeLoop() async {
        while !Task.isCancelled {
            guard await pause(for: Double.random(in: 0.55 ... 1.45)) else { return }
            guard !isDragging, !isPointerTracking else { continue }

            withAnimation(.spring(response: 0.24, dampingFraction: 0.72, blendDuration: 0.02)) {
                gazeOffset = CGSize(
                    width: CGFloat.random(in: -diameter * 0.025 ... diameter * 0.025),
                    height: CGFloat.random(in: -diameter * 0.018 ... diameter * 0.018)
                )
            }
        }
    }

    private func blinkLoop() async {
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

    private func breathingLoop() async {
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: 1.25)) {
                isBreathing = true
            }
            guard await pause(for: 1.25) else { return }

            withAnimation(.easeInOut(duration: 1.25)) {
                isBreathing = false
            }
            guard await pause(for: 1.25) else { return }
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

private struct JarvisMascotBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        JarvisMascotVector.fittedPath(JarvisMascotVector.bodyPath, in: rect)
    }
}

private struct JarvisMascotEyesShape: Shape {
    func path(in rect: CGRect) -> Path {
        JarvisMascotVector.fittedPath(JarvisMascotVector.eyesPath, in: rect)
    }
}

enum JarvisMascotVector {
    private static let bodyPathData = """
    M 469.50,161.00 Q 481,157 491.50,157.00 Q 502,157 512.50,160.50 Q 523,164 527.50,167.00 Q
    532,170 538.00,176.00 Q 544,182 549.50,193.00 Q 555,204 556.00,209.00 Q 557,214 557.00,222.50 Q
    557,231 554.50,240.00 Q 552,249 548.00,256.00 Q 544,263 538.50,268.50 Q 533,274 526.50,277.50 Q
    520,281 518.50,283.00 Q 517,285 517.00,290.00 Q 517,295 520.00,303.00 Q 523,311 528.00,315.50 Q
    533,320 539.00,322.00 Q 545,324 558.50,324.50 Q 572,325 587.00,327.00 Q 602,329 625.50,335.50 Q
    649,342 669.00,352.00 Q 689,362 704.00,373.50 Q 719,385 729.50,396.50 Q 740,408 748.00,420.00 Q
    756,432 763.50,448.00 Q 771,464 777.50,486.50 Q 784,509 795.50,521.00 Q 807,533 815.00,545.00 Q
    823,557 829.50,573.50 Q 836,590 838.00,600.50 Q 840,611 840.00,629.00 Q 840,647 835.00,667.00 Q
    830,687 825.50,696.50 Q 821,706 815.00,715.00 Q 809,724 795.50,737.50 Q 782,751 766.50,760.00 Q
    751,769 744.00,771.00 Q 737,773 725.00,778.50 Q 713,784 694.50,798.00 Q 676,812 657.50,822.00 Q
    639,832 617.50,839.50 Q 596,847 570.50,851.50 Q 545,856 509.50,856.00 Q 474,856 462.00,854.50 Q
    450,853 431.00,848.50 Q 412,844 398.50,839.00 Q 385,834 374.00,828.50 Q 363,823 353.50,817.00 Q
    344,811 331.50,800.50 Q 319,790 311.50,785.00 Q 304,780 280.00,770.50 Q 256,761 243.00,751.50 Q
    230,742 225.00,737.00 Q 220,732 212.50,722.00 Q 205,712 197.00,694.00 Q 189,676 186.00,660.50 Q
    183,645 183.50,626.50 Q 184,608 186.00,598.50 Q 188,589 191.50,579.50 Q 195,570 204.50,554.00 Q
    214,538 225.00,527.00 Q 236,516 238.50,510.50 Q 241,505 245.00,488.00 Q 249,471 254.50,458.00 Q
    260,445 268.50,431.00 Q 277,417 283.00,409.50 Q 289,402 298.00,393.00 Q 307,384 316.50,376.50 Q
    326,369 346.50,357.50 Q 367,346 385.50,339.50 Q 404,333 426.50,329.00 Q 449,325 452.00,324.00 Q
    455,323 460.00,319.00 Q 465,315 468.00,308.00 Q 471,301 471.00,294.00 Q 471,287 470.00,285.50 Q
    469,284 467.50,284.00 Q 466,284 457.50,279.00 Q 449,274 443.00,267.50 Q 437,261 432.50,252.00 Q
    428,243 426.50,231.50 Q 425,220 427.50,208.50 Q 430,197 436.00,187.50 Q 442,178 450.00,171.50 Q
    458,165 469.50,161.00 Z M 304.00,574.50 Q 303,589 306.00,607.50 Q 309,626 314.50,639.00 Q
    320,652 330.00,664.50 Q 340,677 349.50,684.00 Q 359,691 364.00,693.50 Q 369,696 381.50,700.00 Q
    394,704 410.00,706.00 Q 426,708 504.00,707.50 Q 582,707 599.00,705.50 Q 616,704 632.00,700.50 Q
    648,697 660.50,691.50 Q 673,686 680.50,680.50 Q 688,675 697.50,663.50 Q 707,652 712.50,639.50 Q
    718,627 721.00,612.00 Q 724,597 724.00,582.00 Q 724,567 720.50,549.00 Q 717,531 711.50,518.00 Q
    706,505 699.50,495.50 Q 693,486 686.50,479.50 Q 680,473 673.00,468.00 Q 666,463 649.50,456.00 Q
    633,449 617.50,446.00 Q 602,443 590.50,442.00 Q 579,441 536.00,441.50 Q 493,442 471.50,444.00 Q
    450,446 429.00,449.50 Q 408,453 393.00,457.50 Q 378,462 364.50,469.50 Q 351,477 339.50,489.00 Q
    328,501 321.50,513.00 Q 315,525 310.00,542.50 Q 305,560 304.00,574.50 Z
    """
    private static let eyesPathData = """
    M 595.50,516.00 Q 602,515 609.00,517.50 Q 616,520 620.50,524.50 Q 625,529 629.00,536.00 Q
    633,543 636.00,555.00 Q 639,567 639.00,578.50 Q 639,590 636.50,600.50 Q 634,611 629.00,620.00 Q
    624,629 618.00,634.00 Q 612,639 603.50,640.50 Q 595,642 586.50,638.00 Q 578,634 572.00,625.50 Q
    566,617 562.50,604.50 Q 559,592 559.00,580.00 Q 559,568 561.50,557.00 Q 564,546 569.50,536.50 Q
    575,527 582.00,522.00 Q 589,517 595.50,516.00 Z M 425.50,518.50 Q 434,517 441.00,520.00 Q
    448,523 452.00,527.00 Q 456,531 460.00,538.00 Q 464,545 467.00,556.50 Q 470,568 470.00,580.50 Q
    470,593 467.50,603.50 Q 465,614 460.00,623.00 Q 455,632 448.50,637.00 Q 442,642 439.00,643.00 Q
    436,644 430.00,644.00 Q 424,644 418.50,641.50 Q 413,639 408.00,634.00 Q 403,629 399.50,622.50 Q
    396,616 393.50,607.00 Q 391,598 390.50,585.00 Q 390,572 393.00,559.00 Q 396,546 401.00,537.50 Q
    406,529 411.50,524.50 Q 417,520 425.50,518.50 Z
    """
    static let bodyPath = parse(bodyPathData)
    static let eyesPath = parse(eyesPathData)
    private static let sourceBounds = bodyPath.boundingRect

    static func fittedPath(_ path: Path, in rect: CGRect) -> Path {
        let inset = min(rect.width, rect.height) * 0.045
        let availableRect = rect.insetBy(dx: inset, dy: inset)
        let scale = min(availableRect.width / sourceBounds.width, availableRect.height / sourceBounds.height)
        let transform = CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: availableRect.midX - sourceBounds.midX * scale,
            ty: availableRect.midY - sourceBounds.midY * scale
        )
        return path.applying(transform)
    }

    static func makeMenuBarImage(sourceSize: CGFloat = 1024) -> NSImage {
        let size = NSSize(width: sourceSize, height: sourceSize)
        let image = NSImage(size: size)
        image.lockFocusFlipped(true)
        defer { image.unlockFocus() }

        NSColor.white.setFill()
        let bounds = CGRect(origin: .zero, size: size)
        let body = NSBezierPath(cgPath: fittedPath(bodyPath, in: bounds).cgPath)
        body.windingRule = .evenOdd
        body.fill()

        NSBezierPath(cgPath: fittedPath(eyesPath, in: bounds).cgPath).fill()
        return image
    }

    private static func parse(_ pathData: String) -> Path {
        let tokens = pathData
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
        var path = Path()
        var index = 0

        while index < tokens.count {
            let command = tokens[index]
            index += 1

            switch command {
            case "M":
                guard let point = readPoint(from: tokens, at: &index) else { return path }
                path.move(to: point)
            case "Q":
                guard
                    let control = readPoint(from: tokens, at: &index),
                    let endpoint = readPoint(from: tokens, at: &index)
                else {
                    return path
                }
                path.addQuadCurve(to: endpoint, control: control)
            case "Z":
                path.closeSubpath()
            default:
                return path
            }
        }

        return path
    }

    private static func readPoint(from tokens: [Substring], at index: inout Int) -> CGPoint? {
        guard index + 1 < tokens.count,
              let x = Double(tokens[index]),
              let y = Double(tokens[index + 1])
        else {
            return nil
        }
        index += 2
        return CGPoint(x: x, y: y)
    }
}
