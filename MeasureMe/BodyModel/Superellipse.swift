// Superellipse.swift
//
// **Superellipse**
// Cross-section geometry for the 3D body model.
//
// **Responsibilities:**
// - Analytic area of a superellipse
// - Numeric perimeter by arc-length integration
// - Fitting a shape to a measured circumference
//
// **Why the perimeter is numeric but the area is not:**
// The area of |x/a|^n + |z/b|^n = 1 has a closed form in gamma functions.
// The perimeter does not, so it is integrated. Because the perimeter scales
// linearly with the semi-axes, fitting a shape to a measured circumference
// needs one integration of the unit shape and a multiply — never a solve.
//
import Foundation

nonisolated struct Superellipse: Equatable, Sendable {
    /// Semi-axis along x (half the body width at this level), in cm.
    let semiAxisA: Double
    /// Semi-axis along z (half the body depth at this level), in cm.
    let semiAxisB: Double
    /// Shape exponent. 2 is an ellipse; higher values approach a rectangle.
    let exponent: Double

    /// Number of integration steps for the perimeter. 2048 keeps the circle
    /// case within 1e-6 of 2*pi*r, which is well inside the 0.5 mm invariant
    /// the solver relies on.
    private static let integrationSteps = 2048

    /// Closed-form area: 4ab * Γ(1+1/n)² / Γ(1+2/n).
    var area: Double {
        4 * semiAxisA * semiAxisB * pow(tgamma(1 + 1 / exponent), 2) / tgamma(1 + 2 / exponent)
    }

    /// Arc length of the full outline, integrated over one revolution.
    var perimeter: Double {
        let steps = Self.integrationSteps
        let dt = (2 * Double.pi) / Double(steps)
        var total = 0.0
        var previous = point(at: 0)
        for step in 1...steps {
            let current = point(at: Double(step) * dt)
            total += hypot(current.x - previous.x, current.z - previous.z)
            previous = current
        }
        return total
    }

    /// Parametric point on the outline. The `sign * pow(abs())` form keeps the
    /// parametrisation valid in all four quadrants for non-integer exponents.
    private func point(at t: Double) -> (x: Double, z: Double) {
        let cosT = cos(t)
        let sinT = sin(t)
        let power = 2 / exponent
        return (
            x: semiAxisA * (cosT < 0 ? -1 : 1) * pow(abs(cosT), power),
            z: semiAxisB * (sinT < 0 ? -1 : 1) * pow(abs(sinT), power)
        )
    }

    /// Builds the shape whose perimeter equals `circumference`.
    /// - Parameters:
    ///   - circumference: Measured circumference in cm.
    ///   - aspectRatio: `semiAxisB / semiAxisA` — depth over width.
    ///   - exponent: Shape exponent.
    static func fitting(circumference: Double, aspectRatio: Double, exponent: Double) -> Superellipse {
        let unit = Superellipse(semiAxisA: 1, semiAxisB: aspectRatio, exponent: exponent)
        let scale = circumference / unit.perimeter
        return Superellipse(
            semiAxisA: scale,
            semiAxisB: aspectRatio * scale,
            exponent: exponent
        )
    }
}
