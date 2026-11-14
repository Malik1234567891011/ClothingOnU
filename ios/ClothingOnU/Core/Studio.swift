import Foundation
import Observation

/// Anything that can render. `RenderAPI` in the app; a fake in tests and previews.
protocol Renderer: Sendable {
    func render(_ request: RenderRequest) async throws -> RenderResult
}

extension RenderAPI: Renderer {}

/// Orchestrates renders on top of the Library: building the avatar, trying an outfit on,
/// and filling in the other angles of a look. Owns all in-flight state the UI shows.
@MainActor
@Observable
final class Studio {
    enum Job: Equatable {
        case idle
        case working(startedAt: Date)
        case failed(RenderError)

        var isWorking: Bool { if case .working = self { true } else { false } }
        var error: RenderError? { if case .failed(let e) = self { e } else { nil } }
    }

    private(set) var avatarJob: Job = .idle
    private(set) var tryOnJob: Job = .idle
    /// The look currently shown in the fitting room (nil = show the avatar).
    var currentLookID: Look.ID?
    private(set) var angleJobs: [ViewAngle: Job] = [:]

    let library: Library
    private let renderer: any Renderer
    private var angleTask: Task<Void, Never>?

    /// Pro renders take ~20-25 s; used for progress copy, not for timeouts.
    static let typicalSeconds: Double = 24

    init(library: Library, renderer: any Renderer) {
        self.library = library
        self.renderer = renderer
    }

    var currentLook: Look? { currentLookID.flatMap(library.look) }

    // MARK: Payload helpers

    private var wireProfile: WireProfile? {
        library.profile.map { WireProfile(heightCm: $0.heightCm, build: $0.build) }
    }

    /// Reference photos for the request. Face/front carry identity; side/back help angle views.
    private func wirePhotos(roles: [PhotoRole]) -> [WirePhoto] {
        roles.compactMap { role in
            guard let name = library.photos[role], let data = library.jpegData(.photos, name) else { return nil }
            return WirePhoto(role: role, image: WireImage(jpeg: data))
        }
    }

    private func wireGarments(_ garments: [Garment]) -> [WireGarment] {
        garments.compactMap { g in
            library.jpegData(.garments, g.file).map { WireGarment(slot: g.slot, image: WireImage(jpeg: $0)) }
        }
    }

    private nonisolated static func normalise(_ error: Error) -> RenderError {
        (error as? RenderError) ?? .server("Something went wrong. Please try again.")
    }

    private static func decode(_ result: RenderResult) throws -> Data {
        guard let data = result.image.decoded else { throw RenderError.server("The image couldn't be read.") }
        return data
    }

    // MARK: Avatar

    func buildAvatar() async {
        guard let profile = wireProfile, !avatarJob.isWorking else { return }
        avatarJob = .working(startedAt: .now)
        do {
            let req = RenderRequest(profile: profile, photos: wirePhotos(roles: [.front, .face, .side, .back]), kind: .avatar)
            let data = try Self.decode(try await renderer.render(req))
            try library.setAvatar(jpeg: data)
            currentLookID = nil
            avatarJob = .idle
        } catch is CancellationError {
            avatarJob = .idle
        } catch {
            avatarJob = .failed(Self.normalise(error))
        }
    }

    // MARK: Try-on

    var canTryOn: Bool { !library.outfit.isEmpty && library.avatarFile != nil && !tryOnJob.isWorking }

    func tryOn() async {
        guard canTryOn, let profile = wireProfile, let avatar = library.avatarFile,
              let base = library.uploadJPEG(.avatar, avatar) else { return }
        let garments = library.orderedOutfit
        let note = library.note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        cancelAngles()
        tryOnJob = .working(startedAt: .now)
        do {
            let req = RenderRequest(
                profile: profile,
                photos: wirePhotos(roles: [.front, .face]),
                kind: .tryOn(base: WireImage(jpeg: base), garments: wireGarments(garments), note: note)
            )
            let data = try Self.decode(try await renderer.render(req))
            let look = try library.addLook(garments: garments, note: note, front: data)
            currentLookID = look.id
            tryOnJob = .idle
        } catch is CancellationError {
            tryOnJob = .idle
        } catch {
            tryOnJob = .failed(Self.normalise(error))
        }
    }

    func dismissTryOnError() { if case .failed = tryOnJob { tryOnJob = .idle } }

    // MARK: Angles

    /// The angles the turnaround viewer steps through, in rotation order.
    static let turnaround: [ViewAngle] = [.front, .threeQuarter, .side, .back]

    func angleState(_ angle: ViewAngle, for look: Look) -> Job {
        if look.images[angle] != nil { return .idle }
        return look.id == currentLookID ? (angleJobs[angle] ?? .idle) : .idle
    }

    var hasMissingAngles: Bool {
        guard let look = currentLook else { return false }
        return Self.turnaround.contains { look.images[$0] == nil }
    }

    var isRenderingAngles: Bool { angleJobs.values.contains { $0.isWorking } }

    /// Render every missing angle of the current look, in parallel. Each angle is anchored on
    /// the front render so the outfit stays consistent around the turn.
    func renderMissingAngles() {
        guard let look = currentLook, let profile = wireProfile,
              let frontName = look.images[.front], let anchor = library.uploadJPEG(.looks, frontName) else { return }
        let missing = Self.turnaround.filter { look.images[$0] == nil && !(angleJobs[$0]?.isWorking ?? false) }
        guard !missing.isEmpty else { return }

        let photos = wirePhotos(roles: [.front, .face, .side, .back])
        let garments = wireGarments(look.garments)
        let lookID = look.id
        let renderer = self.renderer
        for angle in missing { angleJobs[angle] = .working(startedAt: .now) }

        angleTask = Task { [weak self] in
            await withTaskGroup(of: (ViewAngle, Result<Data, RenderError>).self) { group in
                for angle in missing {
                    let req = RenderRequest(profile: profile, photos: photos,
                                            kind: .view(angle, anchor: WireImage(jpeg: anchor), garments: garments, note: look.note))
                    group.addTask {
                        do {
                            let result = try await renderer.render(req)
                            guard let data = result.image.decoded else { return (angle, .failure(.server("The image couldn't be read."))) }
                            return (angle, .success(data))
                        } catch {
                            return (angle, .failure(Self.normalise(error)))
                        }
                    }
                }
                for await (angle, result) in group {
                    guard let self, !Task.isCancelled else { continue }
                    switch result {
                    case .success(let data):
                        do {
                            try self.library.addAngle(angle, jpeg: data, to: lookID)
                            self.angleJobs[angle] = nil
                        } catch {
                            self.angleJobs[angle] = .failed(.server("Couldn't save that view."))
                        }
                    case .failure(let e):
                        self.angleJobs[angle] = .failed(e)
                    }
                }
            }
        }
    }

    func cancelAngles() {
        angleTask?.cancel()
        angleTask = nil
        angleJobs = [:]
    }

    func show(look id: Look.ID?) {
        if id != currentLookID { cancelAngles() }
        currentLookID = id
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
