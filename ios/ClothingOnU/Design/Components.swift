import SwiftUI

// MARK: - Buttons

/// The one primary call to action per screen: a solid ink capsule.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(Theme.canvas)
            .background(Theme.ink.opacity(isEnabled ? 1 : 0.25), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(Theme.ink)
            .background(Theme.hairline.opacity(configuration.isPressed ? 1 : 0.6), in: .capsule)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { .init() }
}

// MARK: - Progress

/// Onboarding progress: short segments, the current one filled.
struct StepIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? Theme.ink : Theme.hairline)
                    .frame(height: 4)
            }
        }
        .animation(.easeInOut, value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

// MARK: - Rendering feedback

/// A soft light band sweeping down over an image while it's being rendered. Reads as
/// "scanning you" rather than a generic spinner, and keeps the person visible.
struct ScanOverlay: View {
    var active: Bool
    @State private var phase: CGFloat = -0.3

    var body: some View {
        GeometryReader { geo in
            if active {
                ZStack {
                    Color.black.opacity(0.12)
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.10), .white.opacity(0.28), .white.opacity(0.10), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: geo.size.height * 0.18)
                    .overlay(alignment: .center) {
                        // A crisp scan line through the middle of the soft band.
                        Rectangle().fill(.white.opacity(0.7)).frame(height: 1.5)
                            .shadow(color: .white.opacity(0.8), radius: 6)
                    }
                    .offset(y: phase * geo.size.height)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .onAppear {
                    phase = -0.3
                    withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { phase = 1.05 }
                }
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.4), value: active)
    }
}

/// Progress copy that changes as a render goes on, with an honest elapsed estimate.
struct RenderStatus: View {
    let startedAt: Date
    let messages: [String]
    let typicalSeconds: Double

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 0.5)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            let index = min(messages.count - 1, Int(elapsed / (typicalSeconds / Double(messages.count))))
            let fraction = min(0.95, elapsed / typicalSeconds)
            VStack(spacing: Theme.Space.s) {
                Text(messages[max(0, index)])
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.opacity)
                    .animation(.easeInOut, value: index)
                ProgressView(value: fraction)
                    .tint(Theme.ink)
                    .frame(maxWidth: 180)
                Text(elapsed > typicalSeconds * 1.6 ? "Taking longer than usual…" : "About \(max(1, Int(typicalSeconds - elapsed))) s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Misc

/// A rounded-rect image thumbnail with a hairline border.
struct Thumb: View {
    let image: UIImage
    var size: CGFloat = 56

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: Theme.Radius.s))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.hairline))
    }
}

extension View {
    /// Standard horizontal page padding.
    func pagePadding() -> some View { padding(.horizontal, Theme.Space.l) }
}
