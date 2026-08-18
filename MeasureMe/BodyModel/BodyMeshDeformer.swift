// BodyMeshDeformer.swift
//
// **BodyMeshDeformer**
// Applies the solver's circumferences to the base mesh.
//
// **Responsibilities:**
// - Turning each band's target circumference into a radial scale factor
// - Scaling every vertex about its band's centroid, feathered between bands
// - Leaving the head, hands and feet at their baked proportions
//
// **Why the offset is split along and around the bone:**
// Only the component perpendicular to the bone is scaled. Scaling the whole
// offset would make a thicker waist a longer one as well, and would drag the
// shoulders upward as the chest grew.
//
// **Why this satisfies the round-trip criterion by construction:**
// Scaling a planar set radially about a fixed centre by `s` multiplies every
// pairwise distance by `s`, so its convex hull perimeter — the tape-measure
// reading — is multiplied by exactly `s`. With `s = target / base` the band
// measures `target`. The only residual comes from feathering `s` between
// bands, which is what the 1% tolerance absorbs.
//
import Foundation
import simd

nonisolated enum BodyMeshDeformer {
    static func deform(
        mesh: BodyBaseMesh,
        map: BodyRegionMap,
        profile: [BodyRegion: [BodyBand]],
        parameters: BodyMeshParameters
    ) -> [SIMD3<Float>] {
        let stature = Float(parameters.heightCm / 100)
        let factors = scaleFactors(parameters: parameters, profile: profile)

        /// Where one region alone would put this vertex. Returns nil when the
        /// region carries no measurement, so the caller can fall back.
        ///
        /// Interpolates on the vertex's own projection onto the region axis, so
        /// every vertex in a cross-section perpendicular to that axis gets the
        /// same factor and the same centre. That is what makes the section a
        /// uniform planar scaling, and so its tape reading exactly `factor`
        /// times the base.
        func placed(_ base: SIMD3<Float>, in region: BodyRegion) -> SIMD3<Float>? {
            guard region.isMeasured,
                  let bands = profile[region], bands.count > 1,
                  let regionFactors = factors[region]
            else { return nil }

            let axis = bands[0].axis
            let u = simd_dot(base, axis)

            var lower = 0
            while lower < bands.count - 2 && bands[lower + 1].position < u { lower += 1 }
            let span = bands[lower + 1].position - bands[lower].position
            let step = span > 0 ? min(max((u - bands[lower].position) / span, 0), 1) : 0

            let centroid = bands[lower].centroid
                + (bands[lower + 1].centroid - bands[lower].centroid) * step
            let factor = regionFactors[lower]
                + (regionFactors[lower + 1] - regionFactors[lower]) * step

            let offset = base - centroid
            let alongAxis = simd_dot(offset, axis) * axis
            return centroid + alongAxis + (offset - alongAxis) * factor
        }

        return mesh.positions.indices.map { index in
            let base = mesh.positions[index]
            let region = map.region[index]

            // An unmeasured region never moves at all: the head, hands and feet
            // ride the stature scale and nothing else.
            guard region.isMeasured else { return base * stature }

            let primary = placed(base, in: region) ?? base
            let weight = map.blend[index]
            // Below this the second region contributes nothing visible, and
            // skipping it keeps the interior of every region exact.
            guard weight > 0.001 else { return primary * stature }

            // Where the neighbour is unmeasured, `placed` yields the vertex
            // untouched, so blending feathers this region's factor down toward
            // 1 as it approaches the neck, wrist or ankle. Doing it on the
            // measured side only is what keeps the transition continuous
            // without moving the head: without it a torso vertex at the neck
            // scaled by 1.53 sat against a head vertex at 1.0 and stretched
            // their shared edge 4.5x.
            let other = placed(base, in: map.secondary[index]) ?? base
            return (primary + (other - primary) * weight) * stature
        }
    }

    /// One `target / base` factor per band. Unmeasured regions never reach here.
    static func scaleFactors(
        parameters: BodyMeshParameters,
        profile: [BodyRegion: [BodyBand]]
    ) -> [BodyRegion: [Float]] {
        var result: [BodyRegion: [Float]] = [:]
        for (region, bands) in profile where region.isMeasured {
            let stack = solverStack(for: region, parameters: parameters)
            result[region] = bands.map { band in
                let heightCm = Double(band.centroid.y) * parameters.heightCm
                let target = Float(sample(stack, atHeightCm: heightCm) / parameters.heightCm)
                // A band whose base measures zero cannot be scaled into
                // anything meaningful; leaving it at 1 is the honest fallback.
                return band.circumference > 0 ? target / band.circumference : 1
            }
        }
        return result
    }

    private static func solverStack(
        for region: BodyRegion, parameters: BodyMeshParameters
    ) -> [BodyCrossSection] {
        switch region {
        case .leftUpperArm, .rightUpperArm, .leftForearm, .rightForearm: return parameters.arm
        case .leftThigh, .rightThigh, .leftShin, .rightShin:             return parameters.leg
        default:                                                        return parameters.torso
        }
    }

    /// Linear interpolation through a solver stack, clamped at both ends.
    /// The stacks are ordered bottom to top.
    static func sample(_ stack: [BodyCrossSection], atHeightCm height: Double) -> Double {
        guard let first = stack.first, let last = stack.last else { return 0 }
        if height <= first.y { return first.circumferenceCm }
        if height >= last.y { return last.circumferenceCm }
        for index in 0..<(stack.count - 1) where height <= stack[index + 1].y {
            let low = stack[index], high = stack[index + 1]
            let span = high.y - low.y
            let t = span > 0 ? (height - low.y) / span : 0
            return low.circumferenceCm + (high.circumferenceCm - low.circumferenceCm) * t
        }
        return last.circumferenceCm
    }

    /// The tape-measure reading of a rendered body, in the horizontal plane —
    /// which is how a waist is actually measured. Used by the tests: this is
    /// how the acceptance criterion is checked against the output rather than
    /// against the intent.
    static func circumference(
        of positions: [SIMD3<Float>],
        map: BodyRegionMap,
        region: BodyRegion,
        atHeight height: Float,
        halfBand: Float = 0.012
    ) -> Float {
        let members = positions.indices.filter {
            map.region[$0] == region && abs(positions[$0].y - height) < halfBand
        }
        guard members.count > 2 else { return 0 }
        let centroid = members.reduce(SIMD3<Float>.zero) { $0 + positions[$1] } / Float(members.count)
        return ConvexHull.perimeter(of: members.map {
            SIMD2(positions[$0].x - centroid.x, positions[$0].z - centroid.z)
        })
    }

    /// Smooth per-vertex normals for a deformed position array. The baked
    /// normals describe the base surface and stop matching once it moves.
    static func normals(for positions: [SIMD3<Float>], indices: [Int32]) -> [SIMD3<Float>] {
        var accumulated = [SIMD3<Float>](repeating: .zero, count: positions.count)
        var triangle = 0
        while triangle + 2 < indices.count {
            let i0 = Int(indices[triangle])
            let i1 = Int(indices[triangle + 1])
            let i2 = Int(indices[triangle + 2])
            let faceNormal = cross(positions[i1] - positions[i0], positions[i2] - positions[i0])
            accumulated[i0] += faceNormal
            accumulated[i1] += faceNormal
            accumulated[i2] += faceNormal
            triangle += 3
        }
        return accumulated.map { normal in
            let length = simd_length(normal)
            // A vertex touched only by degenerate triangles would normalise to
            // NaN; fall back to a sane unit vector instead.
            return length > 0 ? normal / length : SIMD3<Float>(0, 1, 0)
        }
    }
}
