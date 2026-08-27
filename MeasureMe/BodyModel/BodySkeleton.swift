// BodySkeleton.swift
//
// **BodySkeleton**
// The baked joint positions, and the bone segments the region map is built from.
//
// **Responsibilities:**
// - Decoding BodySkeleton.json into the mesh's normalised space
// - Naming the bone chain each body region is measured along
//
// **Why bones rather than height bands:**
// The mesh is in A-pose, so the upper arm sits 39.6 degrees off vertical. A
// horizontal slice through a bicep cuts an ellipse whose perimeter over-reads
// the arm's circumference by 1/cos(39.6) — about 30%. Slicing perpendicular to
// the bone removes that error. Legs are only 9.3 degrees off, worth 1.3%, so
// they could have used height bands; they use bones anyway so there is one
// mechanism rather than two.
//
import Foundation
import simd

nonisolated enum BodyRegion: CaseIterable, Sendable {
    case torso, neck, head
    case leftUpperArm, rightUpperArm, leftForearm, rightForearm, leftHand, rightHand
    case leftThigh, rightThigh, leftShin, rightShin, leftFoot, rightFoot

    /// Regions with no measurement behind them. They ride along with the body
    /// but are never rescaled — nobody measures the circumference of a head.
    var isMeasured: Bool {
        switch self {
        case .head, .leftHand, .rightHand, .leftFoot, .rightFoot: return false
        default: return true
        }
    }

    /// Everything hanging off a shoulder. In the A-pose these regions cross
    /// most of the body's height, so a band of heights that means one thing for
    /// the torso rarely means the same thing for them.
    var isArmChain: Bool {
        switch self {
        case .leftUpperArm, .rightUpperArm, .leftForearm, .rightForearm,
             .leftHand, .rightHand:
            return true
        default:
            return false
        }
    }
}

nonisolated struct BodyBone: Equatable, Sendable {
    let region: BodyRegion
    let start: SIMD3<Float>
    let end: SIMD3<Float>
}

nonisolated enum BodySkeleton {
    enum LoadError: Error, Equatable {
        case resourceMissing
        case jointMissing(String)
    }

    /// The chain, joint name by joint name. Note `neck` rather than `neck-1`:
    /// `head` and `head-2` also exist, and picking either of those as the
    /// head's root would cut the region off mid-skull.
    private static let chain: [(BodyRegion, String, String)] = [
        (.torso, "pelvis", "spine-4"), (.torso, "spine-4", "spine-3"),
        (.torso, "spine-3", "spine-2"), (.torso, "spine-2", "spine-1"),
        (.torso, "spine-1", "neck"),
        // The neck is its own region, not part of the head.
        //
        // Giving this bone to the TORSO was tried and is worse: the torso then
        // reaches the head joint at 0.914, so its top band covers the jaw and
        // lower skull, whose base circumference has nothing to do with the
        // target the solver interpolates there — edge stretch went from 2.8x to
        // 9.9x and the waist lost its measurement.
        //
        // Leaving it with the HEAD, which is what happened next, made `neckCm`
        // dead: an unmeasured region is never scaled, so a 35 cm neck and a
        // 45 cm neck both rendered at 49.3 cm. On a heavy body that put a fixed
        // thin neck on top of a shoulder girdle scaled up by a third, and the
        // hollow between them read as a shirt collar. A region of its own is
        // the only arrangement where the measurement reaches the mesh and the
        // skull still does not move.
        (.neck, "neck", "head"), (.head, "head", "head-2"),
        (.leftUpperArm, "l-shoulder", "l-elbow"), (.rightUpperArm, "r-shoulder", "r-elbow"),
        (.leftForearm, "l-elbow", "l-hand"), (.rightForearm, "r-elbow", "r-hand"),
        (.leftHand, "l-hand", "l-hand-2"), (.rightHand, "r-hand", "r-hand-2"),
        (.leftThigh, "l-upper-leg", "l-knee"), (.rightThigh, "r-upper-leg", "r-knee"),
        (.leftShin, "l-knee", "l-ankle"), (.rightShin, "r-knee", "r-ankle"),
        (.leftFoot, "l-ankle", "l-foot-2"), (.rightFoot, "r-ankle", "r-foot-2"),
    ]

    private static var cache: [BodyGender: [BodyBone]] = [:]

    static func bones(for gender: BodyGender) throws -> [BodyBone] {
        if let cached = cache[gender] { return cached }

        guard let url = Bundle.main.url(forResource: "BodySkeleton", withExtension: "json") else {
            throw LoadError.resourceMissing
        }
        let all = try JSONDecoder().decode(
            [String: [String: [Float]]].self,
            from: Data(contentsOf: url)
        )
        let key = gender == .male ? "male" : "female"
        guard let joints = all[key] else { throw LoadError.jointMissing(key) }

        func point(_ name: String) throws -> SIMD3<Float> {
            guard let value = joints[name], value.count == 3 else {
                throw LoadError.jointMissing(name)
            }
            return SIMD3(value[0], value[1], value[2])
        }

        let bones = try chain.map {
            BodyBone(region: $0.0, start: try point($0.1), end: try point($0.2))
        }
        cache[gender] = bones
        return bones
    }
}
