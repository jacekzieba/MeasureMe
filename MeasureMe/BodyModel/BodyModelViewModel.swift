// BodyModelViewModel.swift
//
// **BodyModelViewModel**
// Screen state for the 3D body model.
//
// **Responsibilities:**
// - Finding which dates have a complete snapshot behind them
// - Resolving the chosen dates into solved, validated bodies
// - Exposing the interpolated body for the current morph position
//
// Anchor dates are collapsed to one per ±14-day window: two dates inside the
// same window describe the same body state, so offering both as A and B would
// promise a comparison that has no content.
//
import Combine
import Foundation
import SwiftUI

/// One row of the before/after list under the mannequin.
///
/// Carries a localization key rather than a `MetricKind` because paired
/// measurements reach the model already averaged across left and right —
/// naming a side would assert something the model never saw.
nonisolated struct BodyMetricChange: Equatable, Identifiable, Sendable {
    let id: String
    /// Localization key for the row's label.
    let titleKey: String
    let oldValue: Double
    let newValue: Double
    let unitCategory: MetricKind.UnitCategory

    var difference: Double { newValue - oldValue }
}

@MainActor
final class BodyModelViewModel: ObservableObject {

    struct Resolved: Equatable {
        let snapshot: BodySnapshot
        let parameters: BodyMeshParameters
        let validation: BodyValidationResult
    }

    enum BodyModelState: Equatable {
        case needsProfile
        case missingMetrics([MetricKind])
        case single(Resolved)
        case comparison(older: Resolved, newer: Resolved)
    }

    @Published private(set) var state: BodyModelState = .needsProfile
    @Published var morphProgress: Double = 1
    @Published private(set) var metricChanges: [BodyMetricChange] = []

    /// Body for the current morph position, or nil when there is nothing to show.
    var currentParameters: BodyMeshParameters? {
        switch state {
        case .needsProfile, .missingMetrics:
            return nil
        case let .single(resolved):
            return resolved.parameters
        case let .comparison(older, newer):
            return BodyMeshParameters.interpolated(
                from: older.parameters, to: newer.parameters, t: morphProgress
            )
        }
    }

    /// Validation to display — the newer body in a comparison.
    var displayedValidation: BodyValidationResult? {
        switch state {
        case .needsProfile, .missingMetrics: return nil
        case let .single(resolved): return resolved.validation
        case let .comparison(_, newer): return newer.validation
        }
    }

    /// Dates that have a complete snapshot, newest first, one per window.
    nonisolated static func availableAnchorDates(
        samples: [MetricSample],
        gender: BodyGender,
        fallbackHeightCm: Double
    ) -> [Date] {
        let candidates = Set(samples.map(\.date)).sorted(by: >)
        var accepted: [Date] = []
        let window = Double(BodySnapshotBuilder.windowDays) * 86_400

        for candidate in candidates {
            guard !accepted.contains(where: { abs($0.timeIntervalSince(candidate)) <= window }) else { continue }
            let result = BodySnapshotBuilder.build(
                samples: samples, anchorDate: candidate,
                gender: gender, age: 0, fallbackHeightCm: fallbackHeightCm
            )
            if case .success = result { accepted.append(candidate) }
        }
        return accepted
    }

    func load(samples: [MetricSample], gender: BodyGender?, age: Int, fallbackHeightCm: Double) {
        guard let gender else {
            state = .needsProfile
            metricChanges = []
            return
        }

        let dates = Self.availableAnchorDates(
            samples: samples, gender: gender, fallbackHeightCm: fallbackHeightCm
        )

        guard let newest = dates.first else {
            // Report what the most recent attempt was missing.
            let probe = samples.map(\.date).max() ?? Date()
            let result = BodySnapshotBuilder.build(
                samples: samples, anchorDate: probe,
                gender: gender, age: age, fallbackHeightCm: fallbackHeightCm
            )
            if case let .missing(kinds) = result {
                state = .missingMetrics(kinds)
            } else {
                state = .missingMetrics(BodySnapshotBuilder.requiredKinds(for: gender))
            }
            metricChanges = []
            return
        }

        guard let newer = resolve(samples: samples, at: newest, gender: gender, age: age, fallbackHeightCm: fallbackHeightCm) else {
            state = .missingMetrics(BodySnapshotBuilder.requiredKinds(for: gender))
            metricChanges = []
            return
        }

        guard dates.count > 1,
              let oldest = dates.last,
              let older = resolve(samples: samples, at: oldest, gender: gender, age: age, fallbackHeightCm: fallbackHeightCm)
        else {
            state = .single(newer)
            metricChanges = []
            morphProgress = 1
            return
        }

        state = .comparison(older: older, newer: newer)
        metricChanges = Self.changes(from: older.snapshot, to: newer.snapshot)
        morphProgress = 1
    }

    /// Re-resolves both sides after the user picks different dates.
    func select(olderDate: Date, newerDate: Date, samples: [MetricSample], gender: BodyGender, age: Int, fallbackHeightCm: Double) {
        guard let older = resolve(samples: samples, at: olderDate, gender: gender, age: age, fallbackHeightCm: fallbackHeightCm),
              let newer = resolve(samples: samples, at: newerDate, gender: gender, age: age, fallbackHeightCm: fallbackHeightCm)
        else { return }

        state = .comparison(older: older, newer: newer)
        metricChanges = Self.changes(from: older.snapshot, to: newer.snapshot)
        morphProgress = 1
    }

    private func resolve(
        samples: [MetricSample], at date: Date,
        gender: BodyGender, age: Int, fallbackHeightCm: Double
    ) -> Resolved? {
        let result = BodySnapshotBuilder.build(
            samples: samples, anchorDate: date,
            gender: gender, age: age, fallbackHeightCm: fallbackHeightCm
        )
        guard case let .success(snapshot) = result else { return nil }
        let reconciled = BodyVolumeValidator.reconcile(snapshot: snapshot)
        return Resolved(
            snapshot: snapshot,
            parameters: reconciled.parameters,
            validation: reconciled.validation
        )
    }

    /// Per-metric deltas for the before/after list. Paired sites (bicep,
    /// forearm, thigh, calf) are already left/right averages by the time they
    /// reach the snapshot, so rows are labelled with neutral body-part names
    /// rather than a `MetricKind` that would claim a side.
    nonisolated private static func changes(from older: BodySnapshot, to newer: BodySnapshot) -> [BodyMetricChange] {
        let rows: [(titleKey: String, old: Double, new: Double, unitCategory: MetricKind.UnitCategory)] = [
            ("metric.weight", older.weightKg, newer.weightKg, .weight),
            ("metric.bodyfat", older.bodyFatPercent, newer.bodyFatPercent, .percent),
            ("metric.neck", older.neckCm, newer.neckCm, .length),
            ("metric.shoulders", older.shouldersCm, newer.shouldersCm, .length),
            ("metric.chest", older.chestCm, newer.chestCm, .length),
            ("metric.waist", older.waistCm, newer.waistCm, .length),
            ("metric.hips", older.hipsCm, newer.hipsCm, .length),
            (BodyMeasurementSite.bicep.localizationKey, older.bicepCm, newer.bicepCm, .length),
            (BodyMeasurementSite.forearm.localizationKey, older.forearmCm, newer.forearmCm, .length),
            (BodyMeasurementSite.thigh.localizationKey, older.thighCm, newer.thighCm, .length),
            (BodyMeasurementSite.calf.localizationKey, older.calfCm, newer.calfCm, .length)
        ]

        return rows.map { row in
            BodyMetricChange(
                id: row.titleKey,
                titleKey: row.titleKey,
                oldValue: row.old,
                newValue: row.new,
                unitCategory: row.unitCategory
            )
        }
    }
}

/// Shorthand so call sites read `viewModel.state` without the nested name.
typealias BodyModelState = BodyModelViewModel.BodyModelState
