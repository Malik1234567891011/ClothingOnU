import SwiftUI

/// The hero: the user's photo (or the current look), garment pins on the body, drag-to-turn
/// between angles, and press-and-hold to compare against the plain model.
struct Stage: View {
    @Environment(Library.self) private var library
    @Environment(Studio.self) private var studio

    @Binding var angle: ViewAngle
    var anchors: BodyVision.Anchors
    var onPin: (Slot) -> Void

    @State private var comparing = false
    @State private var dragStartIndex: Int?

    private var look: Look? { studio.currentLook }
    private var showsPins: Bool { angle == .front && !studio.tryOnJob.isWorking && !comparing }

    var body: some View {
        GeometryReader { geo in
            let base = displayedImage
            let frame = base.map { aspectFitRect($0.size, in: geo.size) } ?? CGRect(origin: .zero, size: geo.size)
            ZStack(alignment: .topLeading) {
                if let base {
                    Image(uiImage: base)
                        .resizable()
                        .scaledToFit()
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .id(imageIdentity)
                        .transition(.opacity)
                }
                ScanOverlay(active: studio.tryOnJob.isWorking || angleIsRendering)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)

                if showsPins {
                    PinsLayer(frame: frame, container: geo.size, anchors: anchors, outfit: library.outfit, onPin: onPin)
                        .transition(.opacity)
                }
                overlayBadge(in: frame)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(.rect)
            .gesture(turnGesture, including: look == nil ? .subviews : .all)
            .simultaneousGesture(compareGesture)
            .animation(.easeInOut(duration: 0.35), value: imageIdentity)
            .animation(.easeInOut(duration: 0.25), value: showsPins)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: What to show

    private var angleIsRendering: Bool {
        guard let look else { return false }
        return angle != .front && look.images[angle] == nil && studio.angleState(angle, for: look).isWorking
    }

    /// Identity used to cross-fade between images.
    private var imageIdentity: String {
        if comparing || look == nil { return "avatar-\(library.avatarFile ?? "")" }
        let file = look?.images[angle] ?? look?.images[.front] ?? ""
        return "look-\(file)"
    }

    private var displayedImage: UIImage? {
        if comparing { return library.avatar }
        guard let look else { return library.avatar }
        return library.lookImage(look, angle) ?? library.lookImage(look, .front) ?? library.avatar
    }

    @ViewBuilder
    private func overlayBadge(in frame: CGRect) -> some View {
        let text: String? = {
            if comparing { return "Before" }
            if let look, angle != .front, look.images[angle] == nil {
                if case .failed(let e) = studio.angleState(angle, for: look) { return e.localizedDescription }
                return "Turning you around…"
            }
            return nil
        }()
        if let text {
            Text(text)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .frame(maxWidth: frame.width - 32)
                .position(x: frame.midX, y: frame.minY + 36)
                .transition(.opacity)
        }
    }

    // MARK: Gestures

    /// Horizontal drag steps through the turnaround; ~70 pt per angle feels like turning a figure.
    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard look != nil, abs(value.translation.width) > abs(value.translation.height) else { return }
                let order = Studio.turnaround
                let start = dragStartIndex ?? order.firstIndex(of: angle) ?? 0
                if dragStartIndex == nil {
                    dragStartIndex = start
                    if studio.hasMissingAngles { studio.renderMissingAngles() }
                }
                let next = min(max(start + Int((-value.translation.width / 70).rounded()), 0), order.count - 1)
                if order[next] != angle { angle = order[next] }
            }
            .onEnded { _ in dragStartIndex = nil }
    }

    private var compareGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.25, maximumDistance: 20)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second(true, _) = value, look != nil, !comparing { comparing = true }
            }
            .onEnded { _ in comparing = false }
    }
}

/// Fit `size` inside `container`, centred.
func aspectFitRect(_ size: CGSize, in container: CGSize) -> CGRect {
    guard size.width > 0, size.height > 0 else { return CGRect(origin: .zero, size: container) }
    let scale = min(container.width / size.width, container.height / size.height)
    let w = size.width * scale, h = size.height * scale
    return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
}

// MARK: - Pins

/// Fashion-callout style pins: a dot on the body, a hairline leader, and a chip at the edge.
/// Chips alternate sides so they never cover the person.
private struct PinsLayer: View {
    let frame: CGRect
    let container: CGSize
    let anchors: BodyVision.Anchors
    let outfit: [Slot: Garment]
    let onPin: (Slot) -> Void

    @Environment(Library.self) private var library

    private static let leftSlots: [Slot] = [.head, .outer, .accessory]
    private static let rightSlots: [Slot] = [.top, .bottom, .shoes]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                for slot in Slot.allCases {
                    let (dot, chip) = positions(slot)
                    var path = Path()
                    path.move(to: dot)
                    path.addLine(to: chip)
                    ctx.stroke(path, with: .color(.white.opacity(0.85)), lineWidth: 1)
                    ctx.fill(Path(ellipseIn: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)), with: .color(.white))
                    ctx.stroke(Path(ellipseIn: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)), with: .color(.black.opacity(0.25)), lineWidth: 1)
                }
            }
            .allowsHitTesting(false)

            ForEach(Slot.allCases) { slot in
                let (_, chip) = positions(slot)
                PinChip(slot: slot, image: outfit[slot].flatMap(library.garmentImage), leading: Self.leftSlots.contains(slot)) {
                    onPin(slot)
                }
                .position(chip)
            }
        }
        .frame(width: container.width, height: container.height)
    }

    /// Dot on the body and chip position, in container coordinates.
    private func positions(_ slot: Slot) -> (CGPoint, CGPoint) {
        let p = anchors.point(for: slot)
        let dot = CGPoint(x: frame.minX + p.x * frame.width, y: frame.minY + p.y * frame.height)
        let left = Self.leftSlots.contains(slot)
        let margin: CGFloat = 50
        let x = left ? margin : container.width - margin
        // Clamp so chips stay on screen and clear of the top bar / bottom panel.
        let y = min(max(dot.y, 70), container.height - 40)
        return (dot, CGPoint(x: x, y: y))
    }
}

private struct PinChip: View {
    let slot: Slot
    let image: UIImage?
    let leading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(.circle)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .overlay(Circle().strokeBorder(.white.opacity(image == nil ? 0 : 0.9), lineWidth: 2))
                Text(slot.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(image == nil ? "Add \(slot.title.lowercased())" : "Change \(slot.title.lowercased())")
        .accessibilityIdentifier("pin.\(slot.rawValue)")
    }
}
