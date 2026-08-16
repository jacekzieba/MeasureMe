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

        for (index, point) in mesh.positions.enumerated() {
            var bestDistance = Float.greatestFiniteMagnitude
            for (boneIndex, bone) in bones.enumerated() {
                let axis = bone.end - bone.start
                let lengthSquared = simd_length_squared(axis)
                // A zero-length bone would divide by zero; clamping to 0 turns
                // it into a plain point-to-point distance instead.
                let t = lengthSquared > 0
                    ? min(max(simd_dot(point - bone.start, axis) / lengthSquared, 0), 1)
                    : 0
                let distance = simd_distance(point, bone.start + axis * t)
                if distance < bestDistance {
                    bestDistance = distance
                    regions[index] = bone.region
                    let total = totals[bone.region] ?? 0
                    let reached = offsets[boneIndex]! + t * lengthSquared.squareRoot()
                    alongs[index] = total > 0 ? min(reached / total, 1) : 0
                }
            }
        }
        return BodyRegionMap(region: regions, along: alongs)
    }
}
