import SwiftUI

@main
struct ClothingOnUApp: App {
    @State private var library: Library
    @State private var studio: Studio

    init() {
        let library = Library()
        #if DEBUG
        DebugHooks.apply(to: library)
        #endif
        _library = State(initialValue: library)
        _studio = State(initialValue: Studio(library: library, renderer: RenderAPI.live))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(studio)
                .tint(Theme.ink)
        }
    }
}

struct RootView: View {
    @Environment(Library.self) private var library

    var body: some View {
        ZStack {
            if library.hasCompletedOnboarding {
                FittingRoomView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                OnboardingFlow()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: library.hasCompletedOnboarding)
    }
}

#if DEBUG
/// Simulator conveniences, never compiled into release builds.
///  - `-resetLibrary YES` wipes local data on launch.
///  - env `CLOTHINGONU_SEED=<dir>` with front.jpg [face.jpg side.jpg back.jpg] and
///    optional profile.json ({"heightCm":180,"build":"athletic"}) pre-fills onboarding up to the avatar step.
enum DebugHooks {
    @MainActor
    static func apply(to library: Library) {
        if UserDefaults.standard.bool(forKey: "resetLibrary") { library.reset() }
        guard let dir = ProcessInfo.processInfo.environment["CLOTHINGONU_SEED"], library.profile == nil else { return }
        let base = URL(fileURLWithPath: dir)
        struct Seed: Decodable { var heightCm: Int; var build: Build }
        let seed = (try? Data(contentsOf: base.appending(path: "profile.json"))).flatMap { try? JSONDecoder().decode(Seed.self, from: $0) }
        library.setProfile(Profile(heightCm: seed?.heightCm ?? 178, build: seed?.build ?? .average, prefersMetric: false))
        for role in PhotoRole.allCases {
            if let data = try? Data(contentsOf: base.appending(path: "\(role.rawValue).jpg")),
               let img = ImageProcessing.downsampled(data, longEdge: 2048) {
                try? library.setPhoto(img, for: role)
            }
        }
    }
}
#endif
