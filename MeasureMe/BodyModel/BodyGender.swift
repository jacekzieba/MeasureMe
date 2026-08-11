// BodyGender.swift
//
// **BodyGender**
// The two body shapes the mannequin can take.
//
// **Responsibilities:**
// - Naming the resolved gender the anthropometric tables are defined for
// - Refusing to represent an unresolved one
//
// **Why this is not just `Gender`:**
// `Gender` carries a third case, `.notSpecified`, which has no meaningful
// silhouette — there is no neutral set of landmark positions that is honest
// rather than invented. The spec makes gender a precondition of the feature,
// so this type makes the precondition structural: code holding a `BodyGender`
// cannot be holding an unresolved one, and the conversion is the single place
// the screen's "complete your profile" gate is decided.
//
import Foundation

nonisolated enum BodyGender: String, CaseIterable, Sendable {
    case male
    case female

    /// Returns nil when the profile has no resolved gender.
    init?(_ gender: Gender) {
        switch gender {
        case .male:         self = .male
        case .female:       self = .female
        case .notSpecified: return nil
        }
    }
}
