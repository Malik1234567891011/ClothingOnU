import Foundation

// MARK: - Body

/// How the user describes their build. Raw values are the server's wire values.
enum Build: String, Codable, CaseIterable, Identifiable, Sendable {
    case slim, lean, average, athletic, muscular, broad, curvy, plus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slim: "Slim"
        case .lean: "Lean"
        case .average: "Average"
        case .athletic: "Athletic"
        case .muscular: "Very muscular"
        case .broad: "Broad"
        case .curvy: "Curvy"
        case .plus: "Plus size"
        }
    }

    var detail: String {
        switch self {
        case .slim: "Narrow frame, little bulk"
        case .lean: "Light, some definition"
        case .average: "Somewhere in the middle"
        case .athletic: "Toned, sporty"
        case .muscular: "Lots of muscle mass"
        case .broad: "Wide, solid frame"
        case .curvy: "Defined waist, fuller hips"
        case .plus: "Fuller figure"
        }
    }
}

struct Profile: Codable, Equatable, Sendable {
    var heightCm: Int
    var build: Build
    var prefersMetric: Bool

    static let `default` = Profile(heightCm: 175, build: .average, prefersMetric: Locale.current.measurementSystem == .metric)

    var heightText: String { Height.format(cm: heightCm, metric: prefersMetric) }
}

enum Height {
    static let rangeCm = 120...220

    static func feetInches(cm: Int) -> (feet: Int, inches: Int) {
        let total = Int((Double(cm) / 2.54).rounded())
        return (total / 12, total % 12)
    }

    static func cm(feet: Int, inches: Int) -> Int {
        Int((Double(feet * 12 + inches) * 2.54).rounded())
    }

    static func format(cm: Int, metric: Bool) -> String {
        if metric { return "\(cm) cm" }
        let (f, i) = feetInches(cm: cm)
        return "\(f)′\(i)″"
    }
}

// MARK: - Reference photos

enum PhotoRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case front, face, side, back

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front: "Front"
        case .face: "Face"
        case .side: "Side"
        case .back: "Back"
        }
    }

    var instruction: String {
        switch self {
        case .front: "Stand straight, arms slightly away from your body, whole body in frame."
        case .face: "A clear, well-lit selfie. No sunglasses or mask."
        case .side: "Turn 90° to your right so the camera sees your left side."
        case .back: "Face away from the camera, arms relaxed."
        }
    }

    var symbol: String {
        switch self {
        case .front: "figure.stand"
        case .face: "person.crop.circle"
        case .side: "figure.walk"
        case .back: "figure.stand.dress"
        }
    }

    /// Front is the only hard requirement; face and side improve likeness and angle views a lot.
    var requirement: Requirement {
        switch self {
        case .front: .required
        case .face, .side: .recommended
        case .back: .optional
        }
    }

    enum Requirement { case required, recommended, optional }

    /// Whether the whole body (head to feet) should be visible.
    var isFullBody: Bool { self != .face }
}

// MARK: - Garments

/// Where a garment goes. Order is the order pins and tray items are shown in.
enum Slot: String, Codable, CaseIterable, Identifiable, Sendable {
    case head, outer, top, bottom, shoes, accessory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .head: "Head"
        case .outer: "Jacket"
        case .top: "Top"
        case .bottom: "Bottoms"
        case .shoes: "Shoes"
        case .accessory: "Extras"
        }
    }

    var examples: String {
        switch self {
        case .head: "Caps, beanies, hats, glasses"
        case .outer: "Jackets, coats, hoodies, overshirts"
        case .top: "Tees, shirts, sweaters, dresses"
        case .bottom: "Jeans, trousers, shorts, skirts"
        case .shoes: "Sneakers, boots, heels"
        case .accessory: "Bags, watches, jewellery, belts"
        }
    }

    var symbol: String {
        switch self {
        case .head: "hat.cap"
        case .outer: "jacket"
        case .top: "tshirt"
        case .bottom: "figure.walk"
        case .shoes: "shoe"
        case .accessory: "handbag"
        }
    }

    /// Quick styling suggestions shown as chips when this slot is filled.
    var suggestions: [String] {
        switch self {
        case .head: ["Worn backwards", "Pulled low"]
        case .outer: ["Unzipped", "Zipped up", "Hood up", "Sleeves rolled"]
        case .top: ["Tucked in", "Untucked", "Sleeves rolled"]
        case .bottom: ["Cuffed at the ankle", "Belted"]
        case .shoes: ["Laces loose"]
        case .accessory: []
        }
    }
}

struct Garment: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var slot: Slot
    /// File name inside the garments folder (JPEG, already cropped).
    var file: String
}

// MARK: - Looks

enum ViewAngle: String, Codable, CaseIterable, Identifiable, Sendable {
    case front, threeQuarter, side, back

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front: "Front"
        case .threeQuarter: "¾"
        case .side: "Side"
        case .back: "Back"
        }
    }
}

/// A finished try-on: the garments used and one rendered image per angle.
struct Look: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var createdAt: Date
    var garments: [Garment]
    var note: String?
    /// ViewAngle -> file name in the looks folder. `.front` always exists.
    var images: [ViewAngle: String]
}
