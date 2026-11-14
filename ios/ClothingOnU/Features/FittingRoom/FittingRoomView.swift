import SwiftUI

/// The main screen. You, full-bleed; pins on your body; one panel at the bottom.
struct FittingRoomView: View {
    @Environment(Library.self) private var library
    @Environment(Studio.self) private var studio

    @State private var angle: ViewAngle = .front
    @State private var anchors: BodyVision.Anchors = .fallback
    @State private var backdrop: Color = Theme.studio

    // Adding a garment: pick a source, then crop.
    @State private var pendingSlot: Slot?
    @State private var showSource = false
    @State private var editing: EditingGarment?
    @State private var showLooks = false
    @State private var confirmReset = false

    struct EditingGarment: Identifiable {
        let id = UUID()
        let slot: Slot
        let image: UIImage
    }

    var body: some View {
        ZStack {
            backdrop.ignoresSafeArea()
            // The stage lives between the top bar and the panel (safe-area insets), so the
            // whole body, feet included, is always visible and pins are never covered.
            Stage(angle: $angle, anchors: anchors, onPin: add)
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: Theme.Space.s) {
            VStack(spacing: Theme.Space.s) {
                if case .working(let startedAt) = studio.tryOnJob {
                    RenderStatus(startedAt: startedAt, messages: Self.tryOnMessages, typicalSeconds: Studio.typicalSeconds)
                        .padding(Theme.Space.m)
                        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.l))
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                OutfitPanel(angle: $angle, onAdd: add, onTryOn: tryOn)
            }
            .padding(.bottom, Theme.Space.xs)
        }
        .animation(.spring(duration: 0.4), value: studio.tryOnJob.isWorking)
        .imageSource(isPresented: $showSource, title: pendingSlot.map { "Add \($0.title.lowercased())" } ?? "Add item") { image in
            if let slot = pendingSlot { editing = EditingGarment(slot: slot, image: image) }
        }
        .sheet(item: $editing) { item in
            GarmentEditor(slot: item.slot, image: item.image) { cropped in
                try? library.setGarment(cropped, slot: item.slot)
                editing = nil
            } onCancel: {
                editing = nil
            }
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showLooks) {
            LooksSheet().presentationDetents([.medium, .large])
        }
        .alert("Couldn't try that on", isPresented: tryOnErrorBinding, presenting: studio.tryOnJob.error) { error in
            if error.isRetryable { Button("Try again", action: tryOn) }
            Button("OK", role: .cancel) { studio.dismissTryOnError() }
        } message: { error in
            Text(error.localizedDescription)
        }
        .confirmationDialog("Start over?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Delete my photos, model and looks", role: .destructive) {
                studio.startOver()
            }
        } message: {
            Text("This removes everything from this phone. It can't be undone.")
        }
        .task(id: library.avatarFile) {
            guard let avatar = library.avatar else { return }
            // Match the render's own studio backdrop so the photo bleeds into the screen.
            backdrop = Color(uiColor: avatar.backdropColor)
            anchors = await BodyVision.anchors(in: avatar)
        }
        .onChange(of: studio.currentLookID) { angle = .front }
        .sensoryFeedback(.success, trigger: studio.currentLookID) { _, new in new != nil }
    }

    private static let tryOnMessages = [
        "Reading the garments",
        "Fitting them to your shape",
        "Getting the drape right",
        "Final touches",
    ]

    private var topBar: some View {
        HStack {
            Text("OnU")
                .font(Theme.display(.title2))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 6)
            Spacer()
            GlassEffectContainer(spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    if studio.currentLook != nil {
                        Button {
                            studio.show(look: nil)
                        } label: {
                            Image(systemName: "person.crop.rectangle").frame(width: 24, height: 24)
                        }
                        .accessibilityLabel("Show my model")
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                    }
                    if let look = studio.currentLook, let url = library.lookURL(look, angle) ?? library.lookURL(look, .front) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up").frame(width: 24, height: 24)
                        }
                        .accessibilityLabel("Share or save this look")
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                    }
                    Button { showLooks = true } label: {
                        Image(systemName: "square.stack").frame(width: 24, height: 24)
                    }
                    .accessibilityLabel("Your looks")
                    .accessibilityIdentifier("looks.button")
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)

                    Menu {
                        Button("Retake my photos", systemImage: "camera") { library.reopenOnboarding() }
                        Button("Clear outfit", systemImage: "xmark.circle") { library.clearOutfit(); studio.show(look: nil) }
                            .disabled(library.outfit.isEmpty)
                        Divider()
                        Button("Start over", systemImage: "trash", role: .destructive) { confirmReset = true }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 24, height: 24)
                    }
                    .accessibilityLabel("More")
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                }
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.top, Theme.Space.xs)
    }

    private var tryOnErrorBinding: Binding<Bool> {
        Binding(get: { studio.tryOnJob.error != nil }, set: { if !$0 { studio.dismissTryOnError() } })
    }

    private func add(_ slot: Slot) {
        pendingSlot = slot
        showSource = true
    }

    private func tryOn() {
        studio.dismissTryOnError()
        studio.startTryOn()
    }
}
