// ConvexHull.swift
//
// **ConvexHull**
// The perimeter a tape measure would read around a cross-section.
//
// **Why the hull and not the surface outline:**
// A tape pulled taut around a waist spans the small of the back rather than
// sinking into it. The hull's perimeter is therefore the measurement itself,
// not an approximation of it; following the true outline would over-read.
//
// **Why this matters beyond accuracy:**
// Scaling a planar set radially about a fixed centre by `s` multiplies every
// pairwise distance by `s`, so the hull perimeter is multiplied by exactly `s`.
// That is what lets the deformer hit a target circumference by construction
// rather than by iteration.
//
// Monotone chain (Andrew's), O(n log n).
//
import Foundation
import simd

nonisolated enum ConvexHull {
    static func perimeter(of points: [SIMD2<Float>]) -> Float {
        let hull = hull(of: points)
        guard hull.count > 1 else { return 0 }
        // Two points are a degenerate hull: out and back, so twice the span.
        return hull.indices.reduce(0) { total, index in
            total + simd_distance(hull[index], hull[(index + 1) % hull.count])
        }
    }

    static func hull(of points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        guard points.count > 2 else { return points }
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }

        func cross(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }

        func chain(_ input: [SIMD2<Float>]) -> [SIMD2<Float>] {
            var result: [SIMD2<Float>] = []
            for point in input {
                while result.count >= 2,
                      cross(result[result.count - 2], result[result.count - 1], point) <= 0 {
                    result.removeLast()
                }
                result.append(point)
            }
            // The last point starts the opposite chain, so it is dropped here
            // to avoid counting it twice.
            if !result.isEmpty { result.removeLast() }
            return result
        }

        return chain(sorted) + chain(sorted.reversed())
    }
}
