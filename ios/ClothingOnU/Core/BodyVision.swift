import CoreGraphics
import UIKit
import Vision

/// On-device body analysis with Vision. Nothing here touches the network.
enum BodyVision {
    /// A problem with a reference photo, phrased for the user.
    enum Issue: Equatable, Sendable {
        case noPerson
        case multiplePeople
        case headCutOff
        case feetCutOff
        case noFace
        case multipleFaces
        case tooSmall

        var message: String {
            switch self {
            case .noPerson: "We couldn't find a person in this photo."
            case .multiplePeople: "There's more than one person. Use a photo of just you."
            case .headCutOff: "Your head is cut off. Step back so your whole body fits."
            case .feetCutOff: "Your feet are cut off. Step back or tilt the phone down a little."
            case .noFace: "We can't see your face clearly. Try better light, no mask or sunglasses."
            case .multipleFaces: "There's more than one face. Use a selfie of just you."
            case .tooSmall: "You're very small in the frame. Move a bit closer."
            }
        }

        /// Blocking issues make the photo useless; others are warnings the user may override.
        var isBlocking: Bool { self == .noPerson || self == .multiplePeople || self == .multipleFaces }
    }

    /// Normalised (0...1, origin top-left) points on the body, used to place garment pins.
    struct Anchors: Equatable, Sendable {
        var head: CGPoint
        var chest: CGPoint
        var shoulder: CGPoint
        var hips: CGPoint
        var knees: CGPoint
        var feet: CGPoint
        var wrist: CGPoint

        func point(for slot: Slot) -> CGPoint {
            switch slot {
            case .head: head
            case .outer: shoulder
            case .top: chest
            case .bottom: knees
            case .shoes: feet
            case .accessory: wrist
            }
        }

        /// Where pins go when Vision finds no body (the avatar is framed consistently, so
        /// proportions of a standing adult in our studio framing are a good fallback).
        static let fallback = Anchors(
            head: CGPoint(x: 0.5, y: 0.10), chest: CGPoint(x: 0.5, y: 0.30), shoulder: CGPoint(x: 0.38, y: 0.22),
            hips: CGPoint(x: 0.5, y: 0.50), knees: CGPoint(x: 0.5, y: 0.68), feet: CGPoint(x: 0.5, y: 0.92),
            wrist: CGPoint(x: 0.36, y: 0.52)
        )
    }

    // MARK: Photo checks

    static func check(_ image: UIImage, role: PhotoRole) async -> [Issue] {
        guard let cg = ImageProcessing.resized(image, longEdge: 1024).cgImage else { return [.noPerson] }
        return await Task.detached(priority: .userInitiated) {
            role.isFullBody ? checkBody(cg) : checkFace(cg)
        }.value
    }

    private static let minConfidence: Float = 0.3

    private static func checkBody(_ cg: CGImage) -> [Issue] {
        let request = VNDetectHumanBodyPoseRequest()
        try? VNImageRequestHandler(cgImage: cg, orientation: .up).perform([request])
        let bodies = request.results ?? []
        guard !bodies.isEmpty else { return [.noPerson] }
        // Ignore tiny background people; count bodies whose torso is reasonably large.
        let significant = bodies.filter { bodyHeight($0) > 0.25 }
        if significant.count > 1 { return [.multiplePeople] }
        guard let body = significant.first ?? bodies.first,
              let points = try? body.recognizedPoints(.all) else { return [.noPerson] }

        func seen(_ names: [VNHumanBodyPoseObservation.JointName]) -> Bool {
            names.contains { (points[$0]?.confidence ?? 0) > minConfidence }
        }
        var issues: [Issue] = []
        if !seen([.nose, .leftEye, .rightEye, .leftEar, .rightEar, .neck]) { issues.append(.headCutOff) }
        if !seen([.leftAnkle, .rightAnkle]) { issues.append(.feetCutOff) }
        if issues.isEmpty, bodyHeight(body) < 0.35 { issues.append(.tooSmall) }
        return issues
    }

    /// Vertical extent of the detected joints, in normalised image units.
    private static func bodyHeight(_ body: VNHumanBodyPoseObservation) -> CGFloat {
        guard let pts = try? body.recognizedPoints(.all).values.filter({ $0.confidence > minConfidence }), !pts.isEmpty else { return 0 }
        let ys = pts.map(\.location.y)
        return (ys.max() ?? 0) - (ys.min() ?? 0)
    }

    private static func checkFace(_ cg: CGImage) -> [Issue] {
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cgImage: cg, orientation: .up).perform([request])
        let faces = (request.results ?? []).filter { $0.boundingBox.width > 0.08 }
        if faces.isEmpty { return [.noFace] }
        if faces.count > 1 { return [.multipleFaces] }
        return []
    }

    // MARK: Anchors

    static func anchors(in image: UIImage) async -> Anchors {
        guard let cg = ImageProcessing.resized(image, longEdge: 1024).cgImage else { return .fallback }
        return await Task.detached(priority: .userInitiated) { anchors(cg) ?? .fallback }.value
    }

    private static func anchors(_ cg: CGImage) -> Anchors? {
        let request = VNDetectHumanBodyPoseRequest()
        try? VNImageRequestHandler(cgImage: cg, orientation: .up).perform([request])
        guard let body = request.results?.max(by: { bodyHeight($0) < bodyHeight($1) }),
              let pts = try? body.recognizedPoints(.all) else { return nil }

        // Vision uses a bottom-left origin; flip to top-left.
        func p(_ j: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let r = pts[j], r.confidence > minConfidence else { return nil }
            return CGPoint(x: r.location.x, y: 1 - r.location.y)
        }
        func mid(_ a: CGPoint?, _ b: CGPoint?) -> CGPoint? {
            switch (a, b) {
            case let (a?, b?): CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            case let (a?, nil): a
            case let (nil, b?): b
            default: nil
            }
        }

        guard let neck = p(.neck) ?? mid(p(.leftShoulder), p(.rightShoulder)),
              let hips = p(.root) ?? mid(p(.leftHip), p(.rightHip)) else { return nil }
        let nose = p(.nose) ?? CGPoint(x: neck.x, y: neck.y - (hips.y - neck.y) * 0.35)
        // The head pin sits on the crown: as far above the nose as the nose is above the neck.
        let head = CGPoint(x: nose.x, y: max(0.02, nose.y - (neck.y - nose.y) * 0.9))
        let chest = CGPoint(x: neck.x, y: neck.y + (hips.y - neck.y) * 0.35)
        // Image-left shoulder is the person's right shoulder.
        let shoulder = p(.rightShoulder) ?? CGPoint(x: neck.x - 0.1, y: neck.y)
        let knees = mid(p(.leftKnee), p(.rightKnee)) ?? CGPoint(x: hips.x, y: hips.y + 0.2)
        let feet = mid(p(.leftAnkle), p(.rightAnkle)) ?? CGPoint(x: hips.x, y: min(0.95, knees.y + 0.22))
        let wrist = p(.rightWrist) ?? p(.leftWrist) ?? CGPoint(x: shoulder.x - 0.02, y: hips.y)

        return Anchors(head: head, chest: chest, shoulder: shoulder, hips: hips,
                       knees: CGPoint(x: knees.x, y: (hips.y + knees.y) / 2 + 0.04), // mid-thigh reads as "trousers"
                       feet: CGPoint(x: feet.x, y: min(0.97, feet.y + 0.02)), wrist: wrist)
    }
}
