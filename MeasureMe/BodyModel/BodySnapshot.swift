// BodySnapshot.swift
//
// **BodySnapshot**
// One complete body state, assembled from measurement samples.
//
// **Responsibilities:**
// - Holding the 13 values the mesh solver needs, in metric units
// - Recording which span of dates the values were drawn from
//
// All circumferences are already averaged across left and right, so the
// solver never sees asymmetry.
//
import Foundation

nonisolated struct BodySnapshot: Equatable, Hashable, Sendable {
    let gender: BodyGender
    let age: Int
    let heightCm: Double
    let weightKg: Double
    let bodyFatPercent: Double
    let neckCm: Double
    let shouldersCm: Double
    let chestCm: Double
    /// Only populated for `.female`; `chestCm` carries the equivalent for men.
    let bustCm: Double?
    let waistCm: Double
    let hipsCm: Double
    let bicepCm: Double
    let forearmCm: Double
    let thighCm: Double
    let calfCm: Double
    /// The date the user picked. Values may come from up to 14 days either side.
    let anchorDate: Date
    /// Oldest and newest sample dates actually used, for honest labelling.
    let sourceDateRange: ClosedRange<Date>
}
