import SwiftUI
import DragNDropCore

// MARK: - Animation Constants

enum AnimationPresets {
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let snappy = Animation.snappy(duration: 0.2)
    static let smooth = Animation.easeInOut(duration: 0.3)
    static let quick = Animation.easeOut(duration: 0.15)
    static let slow = Animation.easeInOut(duration: 0.5)

    static let bouncy = Animation.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0)
    static let gentle = Animation.interpolatingSpring(stiffness: 100, damping: 15)
}

// MARK: - Animated Appearance Modifier

struct AnimatedAppearance: ViewModifier {
    let delay: Double
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 10)
            .onAppear {
                withAnimation(AnimationPresets.spring.delay(delay)) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func animatedAppearance(delay: Double = 0) -> some View {
        modifier(AnimatedAppearance(delay: delay))
    }
}

// MARK: - Staggered List Appearance

struct StaggeredListModifier<Item: Identifiable>: ViewModifier {
    let items: [Item]
    let baseDelay: Double

    func body(content: Content) -> some View {
        content
    }
}

// MARK: - Pulse Animation

struct PulseModifier: ViewModifier {
    @State private var isPulsing = false
    let duration: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.05 : 1.0)
            .opacity(isPulsing ? 0.8 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

extension View {
    func pulse(duration: Double = 1.0) -> some View {
        modifier(PulseModifier(duration: duration))
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.3),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(45))
                .offset(x: phase * 400 - 200)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Glass Background

struct GlassBackground: View {
    var cornerRadius: CGFloat = 12
    var opacity: Double = 0.1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.3),
                                .white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Animated Progress Ring

struct AnimatedProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat
    let gradientColors: [Color]

    @State private var animatedProgress: Double = 0
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)

            // Progress ring
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: gradientColors,
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90 + rotation))

            // Progress text
            Text("\(Int(animatedProgress * 100))%")
                .font(.system(.caption, design: .rounded))
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .onAppear {
            withAnimation(AnimationPresets.spring) {
                animatedProgress = progress / 100
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(AnimationPresets.spring) {
                animatedProgress = newValue / 100
            }
        }
    }
}

// MARK: - Confetti View

struct ConfettiPiece: Identifiable {
    let id = UUID()
    var color: Color
    var position: CGPoint
    var rotation: Double
    var scale: Double
}

struct ConfettiView: View {
    @State private var pieces: [ConfettiPiece] = []
    @State private var isAnimating = false

    let colors: [Color] = [.red, .blue, .green, .yellow, .purple, .orange, .pink]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(pieces) { piece in
                    Circle()
                        .fill(piece.color)
                        .frame(width: 8, height: 8)
                        .scaleEffect(isAnimating ? 0 : piece.scale)
                        .position(piece.position)
                        .rotationEffect(.degrees(piece.rotation))
                }
            }
        }
        .onAppear {
            createPieces()
            animate()
        }
    }

    private func createPieces() {
        for _ in 0..<50 {
            pieces.append(ConfettiPiece(
                color: colors.randomElement()!,
                position: CGPoint(
                    x: CGFloat.random(in: 0...300),
                    y: CGFloat.random(in: -50...0)
                ),
                rotation: Double.random(in: 0...360),
                scale: Double.random(in: 0.5...1.5)
            ))
        }
    }

    private func animate() {
        for i in pieces.indices {
            withAnimation(.easeOut(duration: 2.0).delay(Double(i) * 0.02)) {
                pieces[i].position.y += 400
                pieces[i].rotation += Double.random(in: 180...720)
            }
        }

        withAnimation(.easeOut(duration: 2.0)) {
            isAnimating = true
        }
    }
}

// MARK: - Success Checkmark

struct AnimatedCheckmark: View {
    @State private var trimEnd: CGFloat = 0
    @State private var scale: CGFloat = 0.8
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .scaleEffect(scale)

            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(color)
                .scaleEffect(scale)
        }
        .onAppear {
            withAnimation(AnimationPresets.bouncy) {
                scale = 1.0
            }
        }
    }
}

// MARK: - Upload Arrow Animation

struct AnimatedUploadArrow: View {
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1

    var body: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.blue)
            .offset(y: offset)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                    offset = -5
                    opacity = 0.6
                }
            }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var dotAnimations: [Bool] = [false, false, false]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .offset(y: dotAnimations[index] ? -3 : 0)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever()
                            .delay(Double(index) * 0.15),
                        value: dotAnimations[index]
                    )
            }
        }
        .onAppear {
            for i in 0..<3 {
                dotAnimations[i] = true
            }
        }
    }
}

// MARK: - Glow Effect

struct GlowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.5), radius: radius)
            .shadow(color: color.opacity(0.3), radius: radius * 2)
    }
}

extension View {
    func glow(color: Color, radius: CGFloat = 10) -> some View {
        modifier(GlowModifier(color: color, radius: radius))
    }
}

// MARK: - Shake Effect

struct ShakeModifier: ViewModifier {
    @State private var shakeOffset: CGFloat = 0
    let trigger: Bool

    func body(content: Content) -> some View {
        content
            .offset(x: shakeOffset)
            .onChange(of: trigger) { _, _ in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.2)) {
                    shakeOffset = 10
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.2)) {
                        shakeOffset = -8
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                        shakeOffset = 0
                    }
                }
            }
    }
}

extension View {
    func shake(trigger: Bool) -> some View {
        modifier(ShakeModifier(trigger: trigger))
    }
}

// MARK: - Number Animation

struct AnimatedNumber: View {
    let value: Int

    @State private var displayedValue: Int = 0

    var body: some View {
        Text("\(displayedValue)")
            .monospacedDigit()
            .onAppear {
                animateTo(value)
            }
            .onChange(of: value) { _, newValue in
                animateTo(newValue)
            }
    }

    private func animateTo(_ target: Int) {
        let steps = 20
        let duration = 0.3
        let stepDuration = duration / Double(steps)
        let difference = target - displayedValue
        let stepSize = difference / steps

        for step in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(step)) {
                if step == steps {
                    displayedValue = target
                } else {
                    displayedValue += stepSize
                }
            }
        }
    }
}

// MARK: - Success Toast

struct SuccessToast: View {
    let message: String
    let onDismiss: () -> Void
    @State private var isVisible = false
    @State private var progress: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 12) {
            AnimatedCheckmark(color: .green)
                .frame(width: 32, height: 32)

            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            GlassBackground(cornerRadius: 16)
        )
        .overlay(
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 16)
                    .trim(from: 0, to: progress)
                    .stroke(Color.green.opacity(0.5), lineWidth: 2)
                    .animation(.linear(duration: 4), value: progress)
            }
        )
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : -50)
        .onAppear {
            withAnimation(AnimationPresets.bouncy) {
                isVisible = true
            }
            withAnimation(.linear(duration: 4).delay(0.5)) {
                progress = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                dismiss()
            }
        }
    }

    private func dismiss() {
        withAnimation(AnimationPresets.snappy) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}

// MARK: - Loading Dots

struct LoadingDots: View {
    @State private var animatingDots: [Bool] = [false, false, false]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animatingDots[index] ? 1.0 : 0.5)
                    .opacity(animatingDots[index] ? 1.0 : 0.3)
            }
        }
        .onAppear {
            for i in 0..<3 {
                withAnimation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15)) {
                    animatingDots[i] = true
                }
            }
        }
    }
}

// MARK: - Animated Counter

struct AnimatedCounter: View {
    let value: Int
    let font: Font
    let color: Color

    @State private var displayedValue: Int = 0

    var body: some View {
        Text("\(displayedValue)")
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
            .contentTransition(.numericText())
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    displayedValue = value
                }
            }
            .onChange(of: value) { _, newValue in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    displayedValue = newValue
                }
            }
    }
}

// MARK: - Breathing Circle

struct BreathingCircle: View {
    let color: Color
    let size: CGFloat
    @State private var isBreathing = false

    var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: size, height: size)
            .scaleEffect(isBreathing ? 1.1 : 0.9)
            .opacity(isBreathing ? 1.0 : 0.7)
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
    }
}

// MARK: - Slide In Modifier

struct SlideInModifier: ViewModifier {
    let edge: Edge
    let delay: Double
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(x: xOffset, y: yOffset)
            .onAppear {
                withAnimation(AnimationPresets.spring.delay(delay)) {
                    isVisible = true
                }
            }
    }

    private var xOffset: CGFloat {
        guard !isVisible else { return 0 }
        switch edge {
        case .leading: return -30
        case .trailing: return 30
        default: return 0
        }
    }

    private var yOffset: CGFloat {
        guard !isVisible else { return 0 }
        switch edge {
        case .top: return -30
        case .bottom: return 30
        default: return 0
        }
    }
}

extension View {
    func slideIn(from edge: Edge, delay: Double = 0) -> some View {
        modifier(SlideInModifier(edge: edge, delay: delay))
    }
}

// MARK: - Previews

#Preview("Animation Components") {
    VStack(spacing: 30) {
        AnimatedProgressRing(
            progress: 75,
            lineWidth: 6,
            gradientColors: [.blue, .purple]
        )
        .frame(width: 60, height: 60)

        AnimatedCheckmark(color: .green)
            .frame(width: 50, height: 50)

        AnimatedUploadArrow()

        TypingIndicator()

        Text("Glowing Text")
            .font(.headline)
            .glow(color: .blue)

        GlassBackground()
            .frame(width: 200, height: 100)
    }
    .padding()
}
