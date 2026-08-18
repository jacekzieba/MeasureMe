// BodyRegionMap.swift
//
// **BodyRegionMap**
// Which part of the body each vertex belongs to, and where along it.
//
// **Responsibilities:**
// - Assigning every vertex to its nearest bone
// - Recording how far along that bone the vertex sits, as 0...1
//
// **Why nearest-bone rather than a height band:**
// At chest height a horizontal band contains the torso and both upper arms, so
// height alone cannot tell them apart and a chest measurement would end up
// scaling the arms. Distance to the bone segment separates them the way the
// anatomy does.
//
import Foundation
import simd

nonisolated struct BodyRegionMap: Sendable {
    let region: [BodyRegion]
    /// 0 at the start of the region's bone chain, 1 at its end.
    ///
    /// Measured across the **whole chain**, not the single nearest bone. The
    /// torso runs pelvis → spine-4 → spine-3 → spine-2 → spine-1 → neck, so a
    /// per-bone parameter would give a vertex halfway up the pelvis bone and one
    /// halfway up the spine-2 bone the same 0.5 despite sitting at completely
    /// different heights — and the two would land in the same band, mixing the
    /// waist measurement with the hips.
    let along: [Float]

    /// The second-nearest region, and its share of the blend.
    ///
    /// Without this the mesh tears. A vertex in the armpit sits a hair from the
    /// torso/arm boundary, and the two regions scale about different centroids
    /// along different axes, so neighbouring vertices land far apart — measured
    /// at 14.5x edge stretch before blending was added. Weighting the two
    /// nearest bones by inverse square distance, the way skinning does, makes
    /// the transition continuous.
    let secondary: [BodyRegion]
    let secondaryAlong: [Float]
    /// The secondary region's weight, 0...0.5.
    let blend: [Float]

    static func build(mesh: BodyBaseMesh, bones: [BodyBone]) -> BodyRegionMap {
        // Where each bone starts within its region's chain, and how long the
        // whole chain is. `bones` is already in chain order per region.
        var offsets: [Int: Float] = [:]
        var totals: [BodyRegion: Float] = [:]
        for (index, bone) in bones.enumerated() {
            let length = simd_distance(bone.start, bone.end)
            offsets[index] = totals[bone.region, default: 0]
            totals[bone.region] = totals[bone.region, default: 0] + length
        }

        var regions = [BodyRegion](repeating: .torso, count: mesh.positions.count)
        var alongs = [Float](repeating: 0, count: mesh.positions.count)
        var secondRegions = [BodyRegion](repeating: .torso, count: mesh.positions.count)
        var secondAlongs = [Float](repeating: 0, count: mesh.positions.count)
        var blends = [Float](repeating: 0, count: mesh.positions.count)

        for (index, point) in mesh.positions.enumerated() {
            // Best and second-best over *regions*, not bones: two bones of the
            // same region are not a boundary and must not blend against
            // each other.
            var best = (distance: Float.greatestFiniteMagnitude, region: BodyRegion.torso, along: Float(0))
            var second = best

            for (boneIndex, bone) in bones.enumerated() {
                let axis = bone.end - bone.start
                let lengthSquared = simd_length_squared(axis)
                // A zero-length bone would divide by zero; clamping to 0 turns
                // it into a plain point-to-point distance instead.
                let t = lengthSquared > 0
                    ? min(max(simd_dot(point - bone.start, axis) / lengthSquared, 0), 1)
                    : 0
                let distance = simd_distance(point, bone.start + axis * t)
                let total = totals[bone.region] ?? 0
                let reached = offsets[boneIndex]! + t * lengthSquared.squareRoot()
                let candidate = (distance, bone.region, total > 0 ? min(reached / total, 1) : 0)

                if distance < best.distance {
                    if bone.region != best.region { second = best }
                    best = candidate
                } else if bone.region != best.region && distance < second.distance {
                    second = candidate
                }
            }

            regions[index] = best.region
            alongs[index] = best.along
            secondRegions[index] = second.region
            secondAlongs[index] = second.along

            // Blend only where the two regions genuinely compete. Inverse-square
            // weighting was tried first and is far too broad: at the waist the
            // spine sits 0.1 away and the thigh 0.3, which still handed the
            // thigh 10% of the vote in the middle of the belly and dragged the
            // waist 10% under its measurement.
            //
            // Ramping on the ratio instead, nothing blends until the second
            // region is within about 1.4x the distance of the first — which is
            // the armpit and the crotch, and nowhere else.
            let ratio = second.distance < .greatestFiniteMagnitude && second.distance > 0
                ? best.distance / second.distance
                : 0
            let t = min(max((ratio - 0.7) / 0.3, 0), 1)
            blends[index] = 0.5 * t * t * (3 - 2 * t)
        }

        return BodyRegionMap(
            region: regions, along: alongs,
            secondary: secondRegions, secondaryAlong: secondAlongs,
            blend: blends
        )
    }
}
