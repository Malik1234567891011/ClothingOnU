import Foundation

// Wire format for POST /api/render. Mirrors server/lib/types.ts; keep the two in sync.

struct WireImage: Codable, Sendable {
    var mimeType: String
    var data: String

    init(jpeg: Data) {
        mimeType = "image/jpeg"
        data = jpeg.base64EncodedString()
    }

    var decoded: Data? { Data(base64Encoded: data) }
}

struct WirePhoto: Encodable, Sendable {
    var role: PhotoRole
    var image: WireImage

    enum CodingKeys: String, CodingKey { case role, mimeType, data }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        try c.encode(image.mimeType, forKey: .mimeType)
        try c.encode(image.data, forKey: .data)
    }
}

struct WireGarment: Encodable, Sendable {
    var slot: Slot
    var image: WireImage

    enum CodingKeys: String, CodingKey { case slot, mimeType, data }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(slot, forKey: .slot)
        try c.encode(image.mimeType, forKey: .mimeType)
        try c.encode(image.data, forKey: .data)
    }
}

struct WireProfile: Encodable, Sendable {
    var heightCm: Int
    var build: Build
}

enum RenderKind: Sendable {
    case avatar
    case tryOn(base: WireImage, garments: [WireGarment], note: String?)
    case view(ViewAngle, anchor: WireImage, garments: [WireGarment], note: String?)
}

struct RenderRequest: Encodable, Sendable {
    var profile: WireProfile
    var photos: [WirePhoto]
    var kind: RenderKind
    var quality: String = "pro"

    enum CodingKeys: String, CodingKey { case kind, profile, photos, quality, base, anchor, garments, note, view }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(profile, forKey: .profile)
        try c.encode(photos, forKey: .photos)
        try c.encode(quality, forKey: .quality)
        switch kind {
        case .avatar:
            try c.encode("avatar", forKey: .kind)
        case let .tryOn(base, garments, note):
            try c.encode("tryon", forKey: .kind)
            try c.encode(base, forKey: .base)
            try c.encode(garments, forKey: .garments)
            try c.encodeIfPresent(note, forKey: .note)
        case let .view(angle, anchor, garments, note):
            try c.encode("view", forKey: .kind)
            try c.encode(angle.rawValue, forKey: .view)
            try c.encode(anchor, forKey: .anchor)
            try c.encode(garments, forKey: .garments)
            try c.encodeIfPresent(note, forKey: .note)
        }
    }
}

struct RenderResult: Decodable, Sendable {
    var image: WireImage
    var model: String
    var ms: Int
}

private struct ErrorEnvelope: Decodable {
    struct Body: Decodable { var code: String; var message: String }
    var error: Body
}

/// Failures the UI knows how to explain.
enum RenderError: LocalizedError, Equatable, Sendable {
    case offline
    case timedOut
    case blocked(String)
    case busy
    case server(String)
    case misconfigured(String)

    var errorDescription: String? {
        switch self {
        case .offline: "You're offline. Check your connection and try again."
        case .timedOut: "That took too long. Try again; it usually works the second time."
        case .blocked(let m): m
        case .busy: "The try-on engine is busy right now. Give it a few seconds."
        case .server(let m): m
        case .misconfigured(let m): m
        }
    }

    var isRetryable: Bool {
        switch self {
        case .offline, .timedOut, .busy, .server: true
        case .blocked, .misconfigured: false
        }
    }
}

/// Talks to the ClothingOnU server. Stateless; safe to share.
struct RenderAPI: Sendable {
    var baseURL: URL
    var token: String
    var session: URLSession

    static let live: RenderAPI = {
        let info = Bundle.main.infoDictionary ?? [:]
        let base = (info["APIBaseURL"] as? String).flatMap(URL.init(string:)) ?? URL(string: "https://clothingonu.vercel.app")!
        let config = URLSessionConfiguration.default
        // A pro render takes ~20-25 s; the server may retry once and then fall back.
        config.timeoutIntervalForRequest = 200
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = false
        return RenderAPI(baseURL: base, token: info["AppToken"] as? String ?? "", session: URLSession(configuration: config))
    }()

    func render(_ request: RenderRequest) async throws -> RenderResult {
        var req = URLRequest(url: baseURL.appending(path: "api/render"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if !token.isEmpty { req.setValue(token, forHTTPHeaderField: "x-app-token") }
        req.httpBody = try JSONEncoder().encode(request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dataNotAllowed:
                throw RenderError.offline
            case .timedOut:
                throw RenderError.timedOut
            case .cancelled:
                throw CancellationError()
            default:
                throw RenderError.server(error.localizedDescription)
            }
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 200 {
            do { return try JSONDecoder().decode(RenderResult.self, from: data) } catch {
                throw RenderError.server("The server sent something unexpected.")
            }
        }
        let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
        let message = envelope?.error.message ?? "Something went wrong (\(status))."
        switch (status, envelope?.error.code) {
        case (_, "blocked"): throw RenderError.blocked(message)
        case (429, _), (_, "rate_limited"): throw RenderError.busy
        case (401, _): throw RenderError.misconfigured("This build of the app isn't authorised to use the server.")
        case (504, _): throw RenderError.timedOut
        default: throw RenderError.server(message)
        }
    }
}
