import SwiftUI

/// Builds the user's base model and asks them to confirm it looks like them.
struct AvatarPage: View {
    @Environment(Library.self) private var library
    @Environment(Studio.self) private var studio
    var onRetakePhotos: () -> Void

    /// The avatar file we started this page with, so "Try again" can tell a fresh result from an old one.
    @State private var initialAvatar: String?
    @State private var started = false

    private static let messages = [
        "Reading your proportions",
        "Matching your face",
        "Dressing you in basics",
        "Setting up the studio",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Theme.studio
                if let avatar = shownAvatar {
                    Image(uiImage: avatar).resizable().scaledToFit()
                        .transition(.opacity)
                } else if let front = library.photo(.front) {
                    Image(uiImage: front).resizable().scaledToFit()
                        .blur(radius: studio.avatarJob.isWorking ? 2 : 0)
                }
                ScanOverlay(active: studio.avatarJob.isWorking)
            }
            .clipShape(.rect(cornerRadius: Theme.Radius.l))
            .padding(.horizontal, Theme.Space.m)
            .padding(.top, Theme.Space.s)
            .animation(.easeInOut(duration: 0.6), value: shownAvatar != nil)

            footer
                .pagePadding()
                .padding(.vertical, Theme.Space.l)
                .frame(minHeight: 200)
        }
        .onAppear {
            initialAvatar = library.avatarFile
            if library.avatarFile == nil, !started {
                started = true
                Task { await studio.buildAvatar() }
            }
        }
    }

    private var shownAvatar: UIImage? { studio.avatarJob.isWorking ? nil : library.avatar }

    @ViewBuilder private var footer: some View {
        switch studio.avatarJob {
        case .working(let startedAt):
            VStack(spacing: Theme.Space.m) {
                Text("Making your model").font(Theme.display(.title2))
                RenderStatus(startedAt: startedAt, messages: Self.messages, typicalSeconds: Studio.typicalSeconds)
            }
        case .failed(let error):
            VStack(spacing: Theme.Space.m) {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await studio.buildAvatar() } }
                    .buttonStyle(.primary)
                Button("Change photos", action: onRetakePhotos)
                    .buttonStyle(.secondary)
            }
        case .idle:
            if library.avatar != nil {
                VStack(spacing: Theme.Space.m) {
                    VStack(spacing: 4) {
                        Text("Is this you?").font(Theme.display(.title))
                        Text("This is the model every outfit is tried on. It should look like you, at your real size.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryInk)
                            .multilineTextAlignment(.center)
                    }
                    Button("Looks like me") { library.finishOnboarding() }
                        .buttonStyle(.primary)
                        .accessibilityIdentifier("avatar.accept")
                    HStack(spacing: Theme.Space.s) {
                        Button("Try again") { Task { await studio.buildAvatar() } }
                            .buttonStyle(.secondary)
                        Button("Change photos", action: onRetakePhotos)
                            .buttonStyle(.secondary)
                    }
                }
                .sensoryFeedback(.success, trigger: library.avatarFile)
            } else {
                Button("Create my model") { Task { await studio.buildAvatar() } }
                    .buttonStyle(.primary)
            }
        }
    }
}
