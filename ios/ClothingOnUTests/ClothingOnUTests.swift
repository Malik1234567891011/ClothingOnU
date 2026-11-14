import Testing
import UIKit
@testable import ClothingOnU

// MARK: - Helpers

private func solidImage(_ w: Int, _ h: Int, color: UIColor = .gray) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { ctx in
        color.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    }
}

private func tempRoot() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "clothingonu-tests-\(UUID().uuidString)")
}

/// Records requests and returns a tiny JPEG (or a scripted error).
private final class FakeRenderer: Renderer, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [[String: Any]] = []
    var failWith: RenderError?
    var delay: Duration = .zero

    var requests: [[String: Any]] { lock.withLock { _requests } }

    func render(_ request: RenderRequest) async throws -> RenderResult {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        lock.withLock { _requests.append(json) }
        if delay > .zero { try await Task.sleep(for: delay) }
        if let failWith { throw failWith }
        let jpeg = solidImage(30, 40).jpegData(compressionQuality: 0.5)!
        return RenderResult(image: WireImage(jpeg: jpeg), model: "fake", ms: 1)
    }
}

// MARK: - Models

struct HeightTests {
    @Test func roundTripsFeetAndInches() {
        #expect(Height.feetInches(cm: 180) == (5, 11))
        #expect(Height.cm(feet: 5, inches: 11) == 180)
        #expect(Height.format(cm: 183, metric: false) == "6′0″")
        #expect(Height.format(cm: 183, metric: true) == "183 cm")
    }
}

// MARK: - Wire format

struct WireFormatTests {
    private func encode(_ r: RenderRequest) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as! [String: Any]
    }

    private let photo = WirePhoto(role: .front, image: WireImage(jpeg: Data([1, 2, 3])))
    private let profile = WireProfile(heightCm: 180, build: .athletic)

    @Test func avatarMatchesServerSchema() throws {
        let json = try encode(RenderRequest(profile: profile, photos: [photo], kind: .avatar))
        #expect(json["kind"] as? String == "avatar")
        #expect(json["quality"] as? String == "pro")
        let p = try #require((json["photos"] as? [[String: Any]])?.first)
        #expect(p["role"] as? String == "front")
        #expect(p["mimeType"] as? String == "image/jpeg")
        #expect(p["data"] as? String == Data([1, 2, 3]).base64EncodedString())
        let prof = try #require(json["profile"] as? [String: Any])
        #expect(prof["heightCm"] as? Int == 180)
        #expect(prof["build"] as? String == "athletic")
    }

    @Test func tryOnAndViewCarryGarmentsNoteAndAngle() throws {
        let g = WireGarment(slot: .outer, image: WireImage(jpeg: Data([9])))
        let tryOn = try encode(RenderRequest(profile: profile, photos: [photo], kind: .tryOn(base: WireImage(jpeg: Data([7])), garments: [g], note: "hood up")))
        #expect(tryOn["kind"] as? String == "tryon")
        #expect(tryOn["note"] as? String == "hood up")
        #expect((tryOn["garments"] as? [[String: Any]])?.first?["slot"] as? String == "outer")
        #expect((tryOn["base"] as? [String: Any])?["mimeType"] as? String == "image/jpeg")

        let view = try encode(RenderRequest(profile: profile, photos: [photo], kind: .view(.threeQuarter, anchor: WireImage(jpeg: Data([7])), garments: [g], note: nil)))
        #expect(view["kind"] as? String == "view")
        #expect(view["view"] as? String == "threeQuarter")
        #expect(view["note"] == nil)
        #expect(view["anchor"] != nil)
    }
}

// MARK: - Image processing

struct ImageProcessingTests {
    @Test func backdropColorReadsRGBInOrder() {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        solidImage(64, 64, color: UIColor(red: 1, green: 0, blue: 0, alpha: 1)).backdropColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r > 0.9 && g < 0.1 && b < 0.1)
    }

    @Test func resizeCapsLongEdge() {
        let big = solidImage(4000, 3000)
        let out = ImageProcessing.resized(big, longEdge: 1280)
        #expect(out.pixelSize == CGSize(width: 1280, height: 960))
    }

    @Test func uploadJPEGStaysSmall() throws {
        let data = try #require(ImageProcessing.uploadJPEG(solidImage(3000, 4000)))
        #expect(data.count < 400_000)
    }

    @Test func cropUsesUnitRect() {
        let img = solidImage(200, 100)
        let out = ImageProcessing.crop(img, to: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        #expect(out.pixelSize == CGSize(width: 100, height: 50))
    }

    @Test func aspectFitCentres() {
        let r = aspectFitRect(CGSize(width: 300, height: 400), in: CGSize(width: 400, height: 400))
        #expect(r == CGRect(x: 50, y: 0, width: 300, height: 400))
    }
}

// MARK: - Library

@MainActor
struct LibraryTests {
    @Test func persistsAcrossInstances() throws {
        let root = tempRoot()
        let a = Library(root: root)
        a.setProfile(Profile(heightCm: 170, build: .curvy, prefersMetric: true))
        try a.setPhoto(solidImage(600, 1200), for: .front)
        try a.setGarment(solidImage(300, 300), slot: .top)
        a.note = "tucked in"
        try a.setAvatar(jpeg: solidImage(30, 40).jpegData(compressionQuality: 0.5)!)
        a.finishOnboarding()

        let b = Library(root: root)
        #expect(b.profile?.build == .curvy)
        #expect(b.photo(.front) != nil)
        #expect(b.outfit[.top] != nil)
        #expect(b.note == "tucked in")
        #expect(b.hasCompletedOnboarding)
    }

    @Test func photosAreDownscaledOnSave() throws {
        let lib = Library(root: tempRoot())
        try lib.setPhoto(solidImage(3000, 4000), for: .front)
        let saved = try #require(lib.photo(.front))
        #expect(max(saved.pixelSize.width, saved.pixelSize.height) <= ImageProcessing.uploadLongEdge)
    }

    @Test func garmentFilesSurviveWhileALookUsesThem() throws {
        let lib = Library(root: tempRoot())
        try lib.setGarment(solidImage(100, 100), slot: .top)
        let g = try #require(lib.outfit[.top])
        let look = try lib.addLook(garments: [g], note: nil, front: Data([1]))
        lib.removeGarment(.top)
        #expect(lib.garmentImage(g) != nil, "the look still shows its garment")
        lib.deleteLook(look.id)
        #expect(lib.garmentImage(g) == nil, "unreferenced garment files are cleaned up")
    }

    @Test func resetClearsEverything() throws {
        let lib = Library(root: tempRoot())
        lib.setProfile(.default)
        try lib.setPhoto(solidImage(100, 200), for: .front)
        lib.reset()
        #expect(lib.profile == nil)
        #expect(lib.photos.isEmpty)
        #expect(!lib.hasCompletedOnboarding)
    }
}

// MARK: - Studio

@MainActor
struct StudioTests {
    private func readyLibrary() throws -> Library {
        let lib = Library(root: tempRoot())
        lib.setProfile(Profile(heightCm: 180, build: .athletic, prefersMetric: false))
        try lib.setPhoto(solidImage(600, 1200), for: .front)
        try lib.setPhoto(solidImage(600, 600), for: .face)
        try lib.setPhoto(solidImage(600, 1200), for: .side)
        return lib
    }

    @Test func avatarThenTryOnThenAngles() async throws {
        let lib = try readyLibrary()
        let fake = FakeRenderer()
        let studio = Studio(library: lib, renderer: fake)

        await studio.buildAvatar()
        #expect(lib.avatar != nil)
        #expect(fake.requests.last?["kind"] as? String == "avatar")
        #expect((fake.requests.last?["photos"] as? [Any])?.count == 3)

        try lib.setGarment(solidImage(200, 200), slot: .outer)
        try lib.setGarment(solidImage(200, 200), slot: .bottom)
        lib.note = "  leave it unzipped "
        #expect(studio.canTryOn)
        await studio.tryOn()

        let req = try #require(fake.requests.last)
        #expect(req["kind"] as? String == "tryon")
        #expect(req["note"] as? String == "leave it unzipped")
        #expect((req["garments"] as? [[String: Any]])?.map { $0["slot"] as? String } == ["outer", "bottom"])
        // Try-on only needs identity references; side/back are for angle views.
        #expect((req["photos"] as? [[String: Any]])?.map { $0["role"] as? String } == ["front", "face"])

        let look = try #require(studio.currentLook)
        #expect(look.images[.front] != nil)
        #expect(studio.hasMissingAngles)

        studio.renderMissingAngles()
        for _ in 0..<200 where studio.hasMissingAngles { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!studio.hasMissingAngles)
        let views = fake.requests.filter { $0["kind"] as? String == "view" }.compactMap { $0["view"] as? String }
        #expect(Set(views) == ["threeQuarter", "side", "back"])
        #expect(lib.looks.count == 1)
    }

    @Test func failuresSurfaceAsTypedErrors() async throws {
        let lib = try readyLibrary()
        let fake = FakeRenderer()
        let studio = Studio(library: lib, renderer: fake)
        await studio.buildAvatar()
        try lib.setGarment(solidImage(200, 200), slot: .top)

        fake.failWith = .blocked("Blocked by safety filter.")
        await studio.tryOn()
        #expect(studio.tryOnJob.error == .blocked("Blocked by safety filter."))
        #expect(lib.looks.isEmpty)
        #expect(studio.tryOnJob.error?.isRetryable == false)
    }

    @Test func noTryOnWithoutGarments() async throws {
        let lib = try readyLibrary()
        let fake = FakeRenderer()
        let studio = Studio(library: lib, renderer: fake)
        await studio.buildAvatar()
        #expect(!studio.canTryOn)
        await studio.tryOn()
        #expect(fake.requests.count == 1) // just the avatar
    }
}

@MainActor
struct StudioSafetyTests {
    @Test func oversizedRequestsDropLeastImportantPhotosFirst() {
        let big = WireImage(jpeg: Data(count: 900_000)) // ~1.2 MB base64 each
        let photos = [PhotoRole.front, .face, .side, .back].map { WirePhoto(role: $0, image: big) }
        let kept = Studio.fitPhotos(photos, fixedBytes: 1_000_000, budget: 3_800_000)
        #expect(kept.map(\.role) == [.front, .face])
        #expect(Studio.fitPhotos(photos, fixedBytes: 0, budget: 10_000_000).count == 4)
    }

    @Test func startOverDiscardsAnInFlightTryOn() async throws {
        let lib = Library(root: tempRoot())
        lib.setProfile(.default)
        try lib.setPhoto(solidImage(600, 1200), for: .front)
        let fake = FakeRenderer()
        let studio = Studio(library: lib, renderer: fake)
        await studio.buildAvatar()
        try lib.setGarment(solidImage(200, 200), slot: .top)

        fake.delay = .milliseconds(200)
        studio.startTryOn()
        try await Task.sleep(for: .milliseconds(50))
        #expect(studio.tryOnJob.isWorking)
        studio.startOver()
        try await Task.sleep(for: .milliseconds(400))
        #expect(lib.looks.isEmpty, "a render from before the reset must not land in the new library")
        #expect(lib.profile == nil)
        #expect(!studio.tryOnJob.isWorking)
    }
}

@MainActor
struct PersistenceFormatTests {
    @Test func enumKeyedDictionariesEncodeAsObjects() throws {
        let root = tempRoot()
        let lib = Library(root: root)
        try lib.setPhoto(solidImage(100, 200), for: .front)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appending(path: "library.json"))) as? [String: Any]
        #expect(json?["photos"] is [String: Any])
    }

    @Test func unreadableIndexIsBackedUpNotLost() throws {
        let root = tempRoot()
        _ = Library(root: root)
        try Data("{not json".utf8).write(to: root.appending(path: "library.json"))
        let lib = Library(root: root)
        #expect(lib.profile == nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(files.contains { $0.hasPrefix("library.unreadable-") })
    }
}

// MARK: - Vision

struct BodyVisionTests {
    @Test func blankImageHasNoPerson() async {
        // nil means Vision can't run here (body pose is unavailable in the Simulator).
        let issues = await BodyVision.check(solidImage(600, 1200), role: .front)
        #expect(issues == nil || issues == [.noPerson])
    }

    @Test func blankImageHasNoFace() async {
        let issues = await BodyVision.check(solidImage(600, 600), role: .face)
        #expect(issues == nil || issues == [.noFace])
    }

    @Test func anchorsFallBackWhenNoBody() async {
        let a = await BodyVision.anchors(in: solidImage(300, 400))
        #expect(a == .fallback)
    }
}
