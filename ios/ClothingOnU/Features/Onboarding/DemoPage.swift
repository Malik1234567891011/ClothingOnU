import SwiftUI

/// First screen: show, don't tell. A looping demo of a (fictional, AI-generated) person
/// getting dressed from two product screenshots, then turning around.
struct DemoPage: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DemoAnimation()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(.rect(cornerRadius: Theme.Radius.l))
                .padding(.horizontal, Theme.Space.m)
                .padding(.top, Theme.Space.s)

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("See it on you\nbefore you buy it.")
                    .font(Theme.display())
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Screenshot anything from any store. We'll show it on your body, from every angle.")
                    .font(.body)
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pagePadding()
            .padding(.top, Theme.Space.l)

            Button("Get started", action: onContinue)
                .buttonStyle(.primary)
                .pagePadding()
                .padding(.vertical, Theme.Space.l)
                .accessibilityIdentifier("onboarding.start")
        }
    }
}

private struct DemoAnimation: View {
    enum Phase: CaseIterable { case base, scan, cards, reveal, look, back }

    @State private var phase: Phase = .base
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.studio
                photo("DemoBase")
                photo("DemoLook")
                    .mask(alignment: .top) {
                        Rectangle().frame(height: revealed ? geo.size.height : 0)
                    }
                photo("DemoBack").opacity(phase == .back ? 1 : 0)
                ScanOverlay(active: phase == .scan)

                // Two "screenshots" fly in from the bottom corners and land on the body.
                garmentCard("DemoGarmentTop", label: "Top", geo: geo, from: CGPoint(x: 0.82, y: 1.1), to: CGPoint(x: 0.5, y: 0.32))
                garmentCard("DemoGarmentBottom", label: "Jeans", geo: geo, from: CGPoint(x: 0.18, y: 1.1), to: CGPoint(x: 0.5, y: 0.66))

                VStack {
                    Spacer()
                    caption
                        .padding(.bottom, Theme.Space.m)
                }
            }
        }
        .task { await loop() }
        .accessibilityElement()
        .accessibilityLabel("Demo: a person in a plain outfit is dressed in a striped sweater and jeans from two shop screenshots, then shown from the back.")
    }

    private var revealed: Bool { phase == .reveal || phase == .look || phase == .back }

    private func photo(_ name: String) -> some View {
        Image(name).resizable().scaledToFill()
    }

    @ViewBuilder
    private func garmentCard(_ name: String, label: String, geo: GeometryProxy, from: CGPoint, to: CGPoint) -> some View {
        let flying = phase == .cards
        let visible = phase == .cards || phase == .scan
        let p = flying ? to : from
        Image(name)
            .resizable()
            .scaledToFill()
            .frame(width: 72, height: 92)
            .clipShape(.rect(cornerRadius: Theme.Radius.s))
            .overlay(alignment: .bottomLeading) {
                Text(label)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: .capsule)
                    .padding(4)
            }
            .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
            .scaleEffect(flying ? 0.6 : 1)
            .opacity(visible ? (flying ? 0 : 1) : 0)
            .position(x: p.x * geo.size.width, y: p.y * geo.size.height)
    }

    private var caption: some View {
        let text: String = switch phase {
        case .base, .scan: "Your photos → your model"
        case .cards: "Add screenshots"
        case .reveal, .look: "On you, in seconds"
        case .back: "From every angle"
        }
        return Text(text)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .contentTransition(.opacity)
            .animation(.easeInOut, value: text)
    }

    private func loop() async {
        if reduceMotion {
            phase = .look
            return
        }
        let timeline: [(Phase, Double, Animation)] = [
            (.base, 1.0, .easeInOut(duration: 0.4)),
            (.scan, 1.6, .easeInOut(duration: 0.3)),
            (.cards, 1.1, .spring(duration: 0.9, bounce: 0.15)),
            (.reveal, 1.4, .easeInOut(duration: 1.1)),
            (.look, 1.6, .easeInOut(duration: 0.3)),
            (.back, 2.0, .easeInOut(duration: 0.8)),
        ]
        while !Task.isCancelled {
            for (p, hold, anim) in timeline {
                withAnimation(anim) { phase = p }
                try? await Task.sleep(for: .seconds(hold))
                if Task.isCancelled { return }
            }
            // Reset to the start without animating the reveal backwards.
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { phase = .base }
        }
    }
}
