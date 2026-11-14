import Foundation
import Observation

/// Anything that can render. `RenderAPI` in the app; a fake in tests and previews.
protocol Renderer: Sendable {
    func render(_ request: RenderRequest) async throws -> RenderResult
}

extension RenderAPI: Renderer {}

/// Orchestrates renders on top of the Library: building the avatar, trying an outfit on,
/// and filling in the other angles of a look. Owns all in-flight state the UI shows.
///
/// Rules that keep money and data safe:
///  - Angle jobs are keyed by look, so switching looks never mixes up spinners or results,
///    and a finished render is always saved to its own look, even if the user moved on.
///  - `generation` is bumped by `startOver()`; results from before a reset are discarded.
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
    private(set) var currentLookID: Look.ID?
    private(set) var angleJobs: [Look.ID: [ViewAngle: Job]] = [:]

    let library: Library
    private let renderer: any Renderer
    /// Render ¾/side/back as soon as the front lands, so turning around is (usually) instant.
    /// Costs 3 more renders per look (~$0.43) but waiting on a tap felt broken.
    let autoRenderAngles: Bool
    private var tasks: [Task<Void, Never>] = []
    private var generation = 0

    /// Pro renders take ~20-25 s; used for progress copy, not for timeouts.
    static let typicalSeconds: Double = 24
    /// Stay under Vercel's 4.5 MB request cap with room for JSON overhead.
    static let requestBudgetBytes = 3_800_000

    init(library: Library, renderer: any Renderer, autoRenderAngles: Bool = true) {
        self.library = library
        self.renderer = renderer
        self.autoRenderAngles = autoRenderAngles
    }

    var currentLook: Look? { currentLookID.flatMap(library.look) }

    func show(look id: Look.ID?) { currentLookID = id }

    /// Cancel everything in flight and wipe the library.
    func startOver() {
        generation += 1
        tasks.forEach { $0.cancel() }
        tasks = []
        angleJobs = [:]
        avatarJob = .idle
        tryOnJob = .idle
        currentLookID = nil
        library.reset()
    }

    // MARK: Payload helpers

    private var wireProfile: WireProfile? {
        library.profile.map { WireProfile(heightCm: $0.heightCm, build: $0.build) }
    }

    /// Reference photos re-encoded for upload (stored copies are higher quality than we send).
    private func wirePhotos(roles: [PhotoRole]) -> [WirePhoto] {
        roles.compactMap { role in
            guard let name = library.photos[role], let data = library.uploadJPEG(.photos, name) else { return nil }
            return WirePhoto(role: role, image: WireImage(jpeg: data))
        }
    }

    private func wireGarments(_ garments: [Garment]) -> [WireGarment] {
        garments.compactMap { g in
            library.uploadJPEG(.garments, g.file).map { WireGarment(slot: g.slot, image: WireImage(jpeg: $0)) }
        }
    }

    /// Drop the least important reference photos until the request fits the server's body limit.
    static func fitPhotos(_ photos: [WirePhoto], fixedBytes: Int, budget: Int = requestBudgetBytes) -> [WirePhoto] {
        var kept = photos
        func size(_ p: [WirePhoto]) -> Int { fixedBytes + p.reduce(0) { $0 + $1.image.data.utf8.count } }
        for role in [PhotoRole.back, .side, .face] where size(kept) > budget {
            kept.removeAll { $0.role == role }
        }
        return kept
    }

    private static func bytes(_ images: [WireImage]) -> Int { images.reduce(0) { $0 + $1.data.utf8.count } }

    private nonisolated static func normalise(_ error: Error) -> RenderError {
        (error as? RenderError) ?? .server("Something went wrong. Please try again.")
    }

    private nonisolated static func decode(_ result: RenderResult) throws -> Data {
        guard let data = result.image.decoded else { throw RenderError.server("The image couldn't be read.") }
        return data
    }

    // MARK: Avatar

    func buildAvatar() async {
        guard let profile = wireProfile, !avatarJob.isWorking else { return }
        let gen = generation
        avatarJob = .working(startedAt: .now)
        do {
            let photos = Self.fitPhotos(wirePhotos(roles: [.front, .face, .side, .back]), fixedBytes: 0)
            let data = try Self.decode(try await renderer.render(RenderRequest(profile: profile, photos: photos, kind: .avatar)))
            guard gen == generation else { return }
            try library.setAvatar(jpeg: data)
            currentLookID = nil
            avatarJob = .idle
        } catch {
            guard gen == generation else { return }
            avatarJob = error is CancellationError ? .idle : .failed(Self.normalise(error))
        }
    }

    // MARK: Try-on

    var canTryOn: Bool { !library.outfit.isEmpty && library.avatarFile != nil && !tryOnJob.isWorking }

    /// Starts a try-on owned by the Studio, so it survives the view that started it and is
    /// cancelled by `startOver()`.
    func startTryOn() {
        tasks.append(Task { await tryOn() })
    }

    func tryOn() async {
        guard canTryOn, let profile = wireProfile, let avatar = library.avatarFile,
              let base = library.uploadJPEG(.avatar, avatar) else { return }
        let gen = generation
        let garments = library.orderedOutfit
        let note = library.note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        // Snapshot the garment bytes now; the tray is locked while this runs, but be defensive.
        let wireGarments = wireGarments(garments)
        let baseImage = WireImage(jpeg: base)
        tryOnJob = .working(startedAt: .now)
        do {
            let photos = Self.fitPhotos(wirePhotos(roles: [.front, .face]), fixedBytes: Self.bytes([baseImage] + wireGarments.map(\.image)))
            let req = RenderRequest(profile: profile, photos: photos, kind: .tryOn(base: baseImage, garments: wireGarments, note: note))
            let data = try Self.decode(try await renderer.render(req))
            guard gen == generation else { return }
            let look = try library.addLook(garments: garments, note: note, front: data)
            show(look: look.id)
            tryOnJob = .idle
            // Anchored on the front we just made, so they can't start any earlier than this.
            if autoRenderAngles { renderMissingAngles() }
        } catch {
            guard gen == generation else { return }
            tryOnJob = error is CancellationError ? .idle : .failed(Self.normalise(error))
        }
    }

    func dismissTryOnError() { if case .failed = tryOnJob { tryOnJob = .idle } }

    // MARK: Angles

    /// The angles the turnaround viewer steps through, in rotation order.
    static let turnaround: [ViewAngle] = [.front, .threeQuarter, .side, .back]

    func angleState(_ angle: ViewAngle, for look: Look) -> Job {
        look.images[angle] != nil ? .idle : (angleJobs[look.id]?[angle] ?? .idle)
    }

    var hasMissingAngles: Bool {
        guard let look = currentLook else { return false }
        return Self.turnaround.contains { look.images[$0] == nil }
    }

    /// Render every missing angle of the current look, in parallel. Each angle is anchored on
    /// the front render so the outfit stays consistent around the turn. Safe to call repeatedly:
    /// angles already rendering are skipped.
    func renderMissingAngles() {
        guard let look = currentLook, let profile = wireProfile,
              let frontName = look.images[.front], let anchor = library.uploadJPEG(.looks, frontName) else { return }
        let lookID = look.id
        let missing = Self.turnaround.filter { look.images[$0] == nil && !(angleJobs[lookID]?[$0]?.isWorking ?? false) }
        guard !missing.isEmpty else { return }

        let anchorImage = WireImage(jpeg: anchor)
        let garments = wireGarments(look.garments)
        guard !garments.isEmpty else {
            for angle in missing { angleJobs[lookID, default: [:]][angle] = .failed(.server("This look's items are no longer available.")) }
            return
        }
        let photos = Self.fitPhotos(wirePhotos(roles: [.front, .face, .side, .back]),
                                    fixedBytes: Self.bytes([anchorImage] + garments.map(\.image)))
        let renderer = self.renderer
        let gen = generation
        for angle in missing { angleJobs[lookID, default: [:]][angle] = .working(startedAt: .now) }

        let task = Task { [weak self] in
            await withTaskGroup(of: (ViewAngle, Result<Data, RenderError>).self) { group in
                for angle in missing {
                    let req = RenderRequest(profile: profile, photos: photos,
                                            kind: .view(angle, anchor: anchorImage, garments: garments, note: look.note))
                    group.addTask {
                        do { return (angle, .success(try Self.decode(try await renderer.render(req)))) }
                        catch { return (angle, .failure(Self.normalise(error))) }
                    }
                }
                for await (angle, result) in group {
                    guard let self, gen == self.generation else { continue }
                    switch result {
                    case .success(let data):
                        // Saved even if the user moved to another look: it's paid for, and it's
                        // keyed to its own look.
                        do {
                            try self.library.addAngle(angle, jpeg: data, to: lookID)
                            self.angleJobs[lookID]?[angle] = nil
                        } catch {
                            self.angleJobs[lookID]?[angle] = .failed(.server("Couldn't save that view."))
                        }
                    case .failure(let e):
                        self.angleJobs[lookID]?[angle] = .failed(e)
                    }
                }
            }
        }
        tasks.removeAll { $0.isCancelled }
        tasks.append(task)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
