import SwiftUI

/// Shown after a screenshot is picked. Cropping is optional but fixes the most common
/// failure we measured: product pages that show several colourways at once.
struct GarmentEditor: View {
    let slot: Slot
    let image: UIImage
    var onDone: (UIImage) -> Void
    var onCancel: () -> Void

    /// Crop rectangle in unit coordinates of the image (origin top-left).
    @State private var crop = CGRect(x: 0, y: 0, width: 1, height: 1)

    private var isCropped: Bool { crop.width < 0.995 || crop.height < 0.995 }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Space.m) {
                Text("Page shows several colours or items? Drag the corners around the one you want.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .pagePadding()

                CropCanvas(image: image, crop: $crop)
                    .padding(.horizontal, Theme.Space.m)

                Button("Use whole screenshot") {
                    withAnimation(.spring(duration: 0.3)) { crop = CGRect(x: 0, y: 0, width: 1, height: 1) }
                }
                .font(.subheadline.weight(.semibold))
                .opacity(isCropped ? 1 : 0)
                .disabled(!isCropped)
            }
            .padding(.vertical, Theme.Space.m)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle(slot.title)
            .navigationBarTitleDisplayMode(.inline)
            .tint(Theme.ink)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", role: .confirm) {
                        onDone(isCropped ? ImageProcessing.crop(image, to: crop) : image)
                    }
                    .accessibilityIdentifier("garment.add")
                }
            }
        }
    }
}

private struct CropCanvas: View {
    let image: UIImage
    @Binding var crop: CGRect

    @State private var dragStart: CGRect?
    private let minSize: CGFloat = 0.08
    private let handle: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let frame = aspectFitRect(image.size, in: geo.size)
            let r = CGRect(x: frame.minX + crop.minX * frame.width, y: frame.minY + crop.minY * frame.height,
                           width: crop.width * frame.width, height: crop.height * frame.height)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)

                // Dim everything outside the crop.
                Path { p in
                    p.addRect(frame)
                    p.addRect(r)
                }
                .fill(.black.opacity(0.5), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                Rectangle()
                    .strokeBorder(.white, lineWidth: 2)
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
                    .contentShape(.rect)
                    .gesture(moveGesture(frame: frame))
                    .accessibilityLabel("Crop area")

                ForEach(Corner.allCases, id: \.self) { corner in
                    let pt = corner.point(in: r)
                    Circle()
                        .fill(.white)
                        .frame(width: 18, height: 18)
                        .shadow(radius: 2)
                        .frame(width: handle * 1.6, height: handle * 1.6)
                        .contentShape(.rect)
                        .position(pt)
                        .gesture(resizeGesture(corner, frame: frame))
                        .accessibilityHidden(true)
                }
            }
        }
    }

    enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
        func point(in r: CGRect) -> CGPoint {
            switch self {
            case .topLeft: CGPoint(x: r.minX, y: r.minY)
            case .topRight: CGPoint(x: r.maxX, y: r.minY)
            case .bottomLeft: CGPoint(x: r.minX, y: r.maxY)
            case .bottomRight: CGPoint(x: r.maxX, y: r.maxY)
            }
        }
    }

    private func moveGesture(frame: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { v in
                let start = dragStart ?? crop
                dragStart = start
                var next = start.offsetBy(dx: v.translation.width / frame.width, dy: v.translation.height / frame.height)
                next.origin.x = min(max(next.minX, 0), 1 - next.width)
                next.origin.y = min(max(next.minY, 0), 1 - next.height)
                crop = next
            }
            .onEnded { _ in dragStart = nil }
    }

    private func resizeGesture(_ corner: Corner, frame: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { v in
                let s = dragStart ?? crop
                dragStart = s
                let dx = v.translation.width / frame.width, dy = v.translation.height / frame.height
                var minX = s.minX, minY = s.minY, maxX = s.maxX, maxY = s.maxY
                switch corner {
                case .topLeft: minX += dx; minY += dy
                case .topRight: maxX += dx; minY += dy
                case .bottomLeft: minX += dx; maxY += dy
                case .bottomRight: maxX += dx; maxY += dy
                }
                minX = min(max(minX, 0), maxX - minSize); maxX = max(min(maxX, 1), minX + minSize)
                minY = min(max(minY, 0), maxY - minSize); maxY = max(min(maxY, 1), minY + minSize)
                crop = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            }
            .onEnded { _ in dragStart = nil }
    }
}
