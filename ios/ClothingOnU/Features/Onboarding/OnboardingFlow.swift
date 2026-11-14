import SwiftUI

/// Four screens, by design (completion falls off after ~5): demo → body → photos → meet your model.
struct OnboardingFlow: View {
    @Environment(Library.self) private var library

    enum Step: Int, CaseIterable { case demo, body, photos, avatar }

    @State private var step: Step = .demo
    @State private var draft: Profile = .default

    var body: some View {
        VStack(spacing: 0) {
            if step != .demo {
                header
                    .padding(.top, Theme.Space.s)
                    .transition(.opacity)
            }
            ZStack {
                switch step {
                case .demo:
                    DemoPage { go(.body) }
                case .body:
                    BodyPage(profile: $draft) {
                        library.setProfile(draft)
                        go(.photos)
                    }
                case .photos:
                    PhotosPage { go(.avatar) }
                case .avatar:
                    AvatarPage(onRetakePhotos: { go(.photos) })
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .onAppear(perform: resume)
    }

    private var header: some View {
        HStack(spacing: Theme.Space.m) {
            Button {
                if let prev = Step(rawValue: step.rawValue - 1) { go(prev) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Back")
            StepIndicator(count: Step.allCases.count - 1, current: step.rawValue - 1)
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, Theme.Space.s)
    }

    private func go(_ next: Step) {
        withAnimation(.spring(duration: 0.45)) { step = next }
    }

    /// Returning users (e.g. "Retake photos" from the fitting room) skip what they've done.
    private func resume() {
        if let p = library.profile { draft = p }
        if library.avatarFile != nil, library.profile != nil {
            step = .photos
        } else if library.profile != nil, !library.photos.isEmpty {
            step = .photos
        }
    }
}
