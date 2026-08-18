// BodyBandProfile.swift
//
// **BodyBandProfile**
// The base mesh measured, once, so the deformer only has to scale.
//
// **Responsibilities:**
// - Splitting each region into bands along its bone chain
// - Recording each band's centroid, axis and base circumference
//
// **Why this is precomputed:**
// None of it depends on the user's measurements, so it is derived once per
// gender at load. What remains per frame is a lookup and a multiply per vertex,
// which is what keeps the morph smooth across 13 380 vertices.
//
// **Why band counts are modest:**
// Only 7.6% of the mesh's vertices are in the torso — the head, hands and feet
// hold 71% of them, because a character base mesh puts its detail where
// expression and articulation are. Slicing too finely leaves bands with too few
// points to hull meaningfully.
//
import Foundation
import simd

nonisolated struct BodyBand: Equatable, Sendable {
    let centroid: SIMD3<Float>
    /// Unit vector along the bone chain this band was cut perpendicular to.
    let axis: SIMD3<Float>
    /// The centroid projected onto `axis`. This, not the along-chain distance,
    /// is what the deformer interpolates against.
    ///
    /// The two are not interchangeable, and using the wrong one cost a debug
    /// round: bands are not evenly spaced in height (0.52 → 0.60 is a 0.08 step
    /// where 0.64 → 0.68 is 0.046), so interpolating by chain distance while
    /// looking targets up by height gave vertices in one horizontal slice
    /// different factors. A slice scaled non-uniformly does not have its hull
    /// perimeter multiplied by that factor, and the waist came out 2-4% under.
    let position: Float
    let circumference: Float
    let vertexCount: Int
}

nonisolated enum BodyBandProfile {
    /// Measured on both baked meshes, not guessed. Minimum band occupancy
    /// across the measured regions:
    ///
    /// | bands | male | female |
    /// |---|---|---|
    /// | 24 | 0 | — |
    /// | 12 | 2 | — |
    /// | 10 | 10 | **6** |
    /// | 8 | 16 | 20 |
    ///
    /// Eight, because the female forearm is the binding constraint — it starves
    /// at ten where the male mesh is still comfortable. A one-vertex band hulls
    /// to a circumference of zero, and a six-vertex one under-reads a round
    /// cross-section by about 4.5%.
    ///
    /// Eight bands still separate the torso's landmarks: over the pelvis-to-neck
    /// span they put the waist near band 2, the chest near 4 and the shoulders
    /// near 7.
    static let defaultBandCount = 8

    static func build(
        mesh: BodyBaseMesh,
        map: BodyRegionMap,
        bones: [BodyBone],
        bandsPerRegion: Int
    ) -> [BodyRegion: [BodyBand]] {
        var members: [BodyRegion: [[Int]]] = [:]
        for region in BodyRegion.allCases {
            members[region] = Array(repeating: [], count: bandsPerRegion)
        }
        for index in mesh.positions.indices {
            let slot = min(Int(map.along[index] * Float(bandsPerRegion)), bandsPerRegion - 1)
            members[map.region[index]]?[slot].append(index)
        }

        var profile: [BodyRegion: [BodyBand]] = [:]
        for region in BodyRegion.allCases {
            let axis = regionAxis(region, bones: bones)
            let (right, up) = frame(for: axis)
            profile[region] = (members[region] ?? []).compactMap { indices -> BodyBand? in
                guard !indices.isEmpty else { return nil }
                let centroid = indices.reduce(SIMD3<Float>.zero) { $0 + mesh.positions[$1] }
                    / Float(indices.count)

                // Hull the middle of the band, not all of it. A band is ~7 cm
                // of a tapering limb, and the hull of that whole wedge is wider
                // than the cross-section at its centre — which over-reads the
                // base and leaves the deformed body systematically too thin
                // (measured at 3-5% before this narrowing).
                let ordered = indices.sorted { map.along[$0] < map.along[$1] }
                let keep = max(indices.count / 2, min(indices.count, 8))
                let drop = (ordered.count - keep) / 2
                let core = Array(ordered[drop..<(drop + keep)])

                let flat = core.map { index -> SIMD2<Float> in
                    let offset = mesh.positions[index] - centroid
                    return SIMD2(simd_dot(offset, right), simd_dot(offset, up))
                }
                return BodyBand(
                    centroid: centroid,
                    axis: axis,
                    position: simd_dot(centroid, axis),
                    circumference: ConvexHull.perimeter(of: flat),
                    vertexCount: indices.count
                )
            }
            .sorted { $0.position < $1.position }
        }
        return profile
    }

    /// Mean direction of the bones making up a region, weighted by nothing —
    /// the chain within a region is close to straight, so a plain mean is
    /// enough and avoids inventing a curve the anatomy does not have.
    static func regionAxis(_ region: BodyRegion, bones: [BodyBone]) -> SIMD3<Float> {
        let directions = bones.filter { $0.region == region }
            .map { simd_normalize($0.end - $0.start) }
        guard !directions.isEmpty else { return SIMD3(0, 1, 0) }
        let sum = directions.reduce(SIMD3<Float>.zero, +)
        return simd_length(sum) > 0 ? simd_normalize(sum) : SIMD3(0, 1, 0)
    }

    /// Any two unit vectors spanning the plane perpendicular to `axis`. The
    /// seed only has to avoid being parallel to it; which perpendicular pair
    /// comes out does not matter, because the perimeter of a planar set does
    /// not depend on how the plane is coordinatised.
    static func frame(for axis: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        let seed = abs(axis.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let right = simd_normalize(simd_cross(seed, axis))
        return (right, simd_normalize(simd_cross(axis, right)))
    }
}
