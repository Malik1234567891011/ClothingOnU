import Foundation
import Observation
import UIKit

/// Everything the app remembers, on device only: profile, reference photos, the avatar,
/// the outfit being assembled, and saved looks. Images are JPEG files; the index is one
/// small JSON file written atomically.
@MainActor
@Observable
final class Library {
    private(set) var profile: Profile?
    private(set) var photos: [PhotoRole: String] = [:]
    private(set) var avatarFile: String?
    /// Set when the user accepts their model at the end of onboarding.
    private(set) var onboardingDone = false
    private(set) var looks: [Look] = []
    private(set) var outfit: [Slot: Garment] = [:]
    var note: String = "" { didSet { if note != oldValue { save() } } }

    let root: URL
    private let fm = FileManager.default
    private let cache = NSCache<NSString, UIImage>()

    private struct Snapshot: Codable {
        var profile: Profile?
        var photos: [PhotoRole: String]
        var avatarFile: String?
        var onboardingDone: Bool?
        var looks: [Look]
        var outfit: [Slot: Garment]
        var note: String
    }

    init(root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "ClothingOnU", directoryHint: .isDirectory)
        self.root = base
        for dir in Folder.allCases {
            try? fm.createDirectory(at: base.appending(path: dir.rawValue, directoryHint: .isDirectory), withIntermediateDirectories: true)
        }
        // Personal photos stay in the (encrypted) device backup so a new phone keeps them,
        // and are protected at rest like the rest of the user's data.
        try? fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: base.path)
        load()
    }

    enum Folder: String, CaseIterable { case photos, avatar, garments, looks }

    // MARK: Derived state

    var hasCompletedOnboarding: Bool { onboardingDone && profile != nil && avatarFile != nil }

    func finishOnboarding() {
        onboardingDone = true
        save()
    }

    /// Go back to onboarding to retake photos (keeps looks).
    func reopenOnboarding() {
        onboardingDone = false
        save()
    }
    var avatar: UIImage? { avatarFile.flatMap { image(.avatar, $0) } }
    var orderedOutfit: [Garment] { Slot.allCases.compactMap { outfit[$0] } }

    // MARK: Profile & photos

    func setProfile(_ p: Profile) {
        profile = p
        save()
    }

    func setPhoto(_ image: UIImage, for role: PhotoRole) throws {
        let name = try write(image, to: .photos, longEdge: ImageProcessing.uploadLongEdge, replacing: photos[role])
        photos[role] = name
        save()
    }

    func removePhoto(_ role: PhotoRole) {
        if let old = photos.removeValue(forKey: role) { delete(.photos, old) }
        save()
    }

    func photo(_ role: PhotoRole) -> UIImage? { photos[role].flatMap { image(.photos, $0) } }

    func setAvatar(jpeg: Data) throws {
        let name = UUID().uuidString + ".jpg"
        try jpeg.write(to: url(.avatar, name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        if let old = avatarFile { delete(.avatar, old) }
        avatarFile = name
        save()
    }

    // MARK: Outfit

    func setGarment(_ image: UIImage, slot: Slot) throws {
        let name = try write(image, to: .garments, longEdge: ImageProcessing.uploadLongEdge, replacing: nil)
        let old = outfit[slot]
        outfit[slot] = Garment(id: UUID(), slot: slot, file: name)
        if let old, !isReferencedByLook(old.file) { delete(.garments, old.file) }
        save()
    }

    func removeGarment(_ slot: Slot) {
        guard let old = outfit.removeValue(forKey: slot) else { return }
        if !isReferencedByLook(old.file) { delete(.garments, old.file) }
        save()
    }

    func clearOutfit() {
        for slot in Array(outfit.keys) { removeGarment(slot) }
        note = ""
    }

    /// Re-dress the fitting room in a saved look's garments (for tweaking it).
    func restoreOutfit(from look: Look) {
        let incoming = Set(look.garments.map(\.file))
        for g in outfit.values where !incoming.contains(g.file) && !isReferencedByLook(g.file) {
            delete(.garments, g.file)
        }
        outfit = Dictionary(uniqueKeysWithValues: look.garments.map { ($0.slot, $0) })
        note = look.note ?? ""
        save()
    }

    func garmentImage(_ g: Garment) -> UIImage? { image(.garments, g.file) }

    // MARK: Looks

    @discardableResult
    func addLook(garments: [Garment], note: String?, front: Data) throws -> Look {
        let garments = garments.filter { fm.fileExists(atPath: url(.garments, $0.file).path) }
        let name = UUID().uuidString + ".jpg"
        try front.write(to: url(.looks, name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let look = Look(id: UUID(), createdAt: .now, garments: garments, note: note, images: [.front: name])
        looks.insert(look, at: 0)
        save()
        return look
    }

    func addAngle(_ angle: ViewAngle, jpeg: Data, to lookID: Look.ID) throws {
        guard let i = looks.firstIndex(where: { $0.id == lookID }) else { return }
        let name = UUID().uuidString + ".jpg"
        try jpeg.write(to: url(.looks, name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        if let old = looks[i].images[angle] { delete(.looks, old) }
        looks[i].images[angle] = name
        save()
    }

    func deleteLook(_ id: Look.ID) {
        guard let i = looks.firstIndex(where: { $0.id == id }) else { return }
        let look = looks.remove(at: i)
        look.images.values.forEach { delete(.looks, $0) }
        for g in look.garments where outfit[g.slot]?.file != g.file && !isReferencedByLook(g.file) {
            delete(.garments, g.file)
        }
        save()
    }

    func look(_ id: Look.ID) -> Look? { looks.first { $0.id == id } }
    func lookImage(_ look: Look, _ angle: ViewAngle) -> UIImage? { look.images[angle].flatMap { image(.looks, $0) } }
    func lookURL(_ look: Look, _ angle: ViewAngle) -> URL? { look.images[angle].map { url(.looks, $0) } }

    /// Wipes everything (used by "Start over" and tests).
    func reset() {
        for dir in Folder.allCases {
            let u = root.appending(path: dir.rawValue)
            try? fm.removeItem(at: u)
            try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        }
        cache.removeAllObjects()
        profile = nil; photos = [:]; avatarFile = nil; onboardingDone = false; looks = []; outfit = [:]; note = ""
        save()
    }

    // MARK: Upload payloads

    func jpegData(_ folder: Folder, _ name: String) -> Data? { try? Data(contentsOf: url(folder, name)) }

    /// Re-encoded for upload; rendered images come back at 2K and are too big to send as-is.
    func uploadJPEG(_ folder: Folder, _ name: String) -> Data? {
        guard let img = image(folder, name) else { return nil }
        return ImageProcessing.uploadJPEG(img)
    }

    // MARK: Files

    func url(_ folder: Folder, _ name: String) -> URL { root.appending(path: folder.rawValue).appending(path: name) }

    func image(_ folder: Folder, _ name: String) -> UIImage? {
        let key = "\(folder.rawValue)/\(name)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let data = try? Data(contentsOf: url(folder, name)), let img = UIImage(data: data) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    private func write(_ image: UIImage, to folder: Folder, longEdge: CGFloat, replacing old: String?) throws -> String {
        let resized = ImageProcessing.resized(image, longEdge: longEdge)
        guard let data = resized.jpegData(compressionQuality: 0.9) else { throw CocoaError(.fileWriteUnknown) }
        let name = UUID().uuidString + ".jpg"
        try data.write(to: url(folder, name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        if let old { delete(folder, old) }
        return name
    }

    private func delete(_ folder: Folder, _ name: String) {
        cache.removeObject(forKey: "\(folder.rawValue)/\(name)" as NSString)
        try? fm.removeItem(at: url(folder, name))
    }

    private func isReferencedByLook(_ file: String) -> Bool {
        looks.contains { $0.garments.contains { $0.file == file } }
    }

    private var indexURL: URL { root.appending(path: "library.json") }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let s: Snapshot
        do {
            s = try JSONDecoder().decode(Snapshot.self, from: data)
        } catch {
            // Never silently start empty and overwrite the user's data: keep a copy for recovery.
            let backup = root.appending(path: "library.unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? fm.copyItem(at: indexURL, to: backup)
            return
        }
        profile = s.profile; photos = s.photos; avatarFile = s.avatarFile; onboardingDone = s.onboardingDone ?? false
        looks = s.looks; outfit = s.outfit; note = s.note
    }

    private func save() {
        let s = Snapshot(profile: profile, photos: photos, avatarFile: avatarFile, onboardingDone: onboardingDone, looks: looks, outfit: outfit, note: note)
        do {
            let data = try JSONEncoder().encode(s)
            try data.write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            assertionFailure("Library save failed: \(error)")
        }
    }
}
