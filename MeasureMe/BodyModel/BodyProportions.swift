// BodyProportions.swift
//
// **BodyProportions**
// Anthropometric constants the measurements cannot supply.
//
// **Responsibilities:**
// - Vertical landmark positions as fractions of stature, per gender
// - Cross-section aspect ratios (depth over width) and shape exponents
//
// **Why these exist:**
// The app records circumferences but no segment lengths — nothing says where
// the waist sits on the torso or how long the femur is. These tables supply
// that from population statistics, seeded from the Drillis-Contini stature
// fractions and refined by the volume round-trip test.
//
import Foundation

nonisolated enum BodyLandmark: CaseIterable, Sendable {
    case ankle, knee, crotch, hip, waist, chest, shoulder, neck, crown
}

nonisolated enum BodyProportions {
    /// How far up the body a landmark sits, as a fraction of total height.
    static func heightFraction(_ landmark: BodyLandmark, gender: BodyGender) -> Double {
        switch (landmark, gender) {
        case (.ankle, _):        return 0.039
        case (.knee, _):         return 0.285
        case (.crotch, .male):   return 0.485
        case (.crotch, .female): return 0.480
        case (.hip, .male):      return 0.530
        case (.hip, .female):    return 0.535
        case (.waist, .male):    return 0.630
        case (.waist, .female):  return 0.645
        case (.chest, .male):    return 0.720
        case (.chest, .female):  return 0.715
        case (.shoulder, _):     return 0.818
        case (.neck, _):         return 0.870
        case (.crown, _):        return 1.000
        }
    }

    /// Depth over width at a landmark. Below 1 means wider than deep.
    static func aspectRatio(_ landmark: BodyLandmark, gender: BodyGender) -> Double {
        switch (landmark, gender) {
        case (.neck, _), (.crown, _):  return 1.00
        case (.shoulder, _):           return 0.55
        case (.chest, .male):          return 0.72
        case (.chest, .female):        return 0.78
        case (.waist, .male):          return 0.75
        case (.waist, .female):        return 0.72
        case (.hip, _):                return 0.72
        case (.crotch, _):             return 0.80
        case (.knee, _), (.ankle, _):  return 1.00
        }
    }

    /// Shape exponent — how boxy the outline is. 2 is an ellipse; higher
    /// approaches a rectangle. Note the direction at a *fixed* circumference:
    /// a boxier outline encloses LESS area than an ellipse of the same
    /// perimeter, so raising an exponent here lowers that level's contribution
    /// to body volume.
    static func exponent(_ landmark: BodyLandmark) -> Double {
        switch landmark {
        case .neck, .crown, .knee, .ankle: return 2.0
        case .hip:                         return 2.2
        case .waist:                       return 2.3
        case .crotch:                      return 2.2
        case .chest, .shoulder:            return 2.6
        }
    }

    /// How far the torso/leg split may be nudged from the population norm when
    /// reconciling the model's volume against logged weight. ±6%.
    static let torsoShareRange: ClosedRange<Double> = 0.94...1.06
}
