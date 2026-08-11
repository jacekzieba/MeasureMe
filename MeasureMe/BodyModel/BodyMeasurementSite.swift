// BodyMeasurementSite.swift
//
// **BodyMeasurementSite**
// A place on the body the validator can point at.
//
// **Why this is not `MetricKind`:**
// The model averages left and right before it ever sees a measurement, so it
// cannot know which side is off. Naming `MetricKind.leftThigh` would tell the
// user to re-measure one specific leg on evidence that does not exist.
//
import Foundation

nonisolated enum BodyMeasurementSite: String, CaseIterable, Sendable {
    case neck, shoulders, chest, waist, hips, thigh, calf, bicep, forearm

    /// Localization key for the site's user-facing name.
    var localizationKey: String { "bodyModel.site.\(rawValue)" }
}
