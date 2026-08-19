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

    struct Resolved: Equatable, Sendable {
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
    /// Dates with a complete snapshot behind them, newest first.
    @Published private(set) var availableDates: [Date] = []

    /// Half-width, in days, of the window that collapses two anchor dates into one.
    ///
    /// Separate from `BodySnapshotBuilder.sampleWindowDays` on purpose. That one asks "is this
    /// measurement recent enough to describe the user now?" and can afford to be generous; this
    /// one asks "are these two dates the same body?" and must stay tight, or every resolvable
    /// date collapses into a single anchor and there is nothing left to compare.
    static let anchorCollapseDays = 14

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
        let window = Double(anchorCollapseDays) * 86_400

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

    /// Loads the screen's state.
    ///
    /// Snapshot building has to stay on this actor — it reads SwiftData models,
    /// which are not `Sendable`. Volume reconciliation does not: it is a pure
    /// function over `Sendable` values and costs 209 ms per date, twice in a
    /// comparison. Left on the main actor it froze the frame that draws the
    /// loading indicator, so it runs detached and only the result comes back.
    func load(samples: [MetricSample], gender: BodyGender?, age: Int, fallbackHeightCm: Double) async {
        guard let gender else {
            state = .needsProfile
            metricChanges = []
            availableDates = []
            return
        }

        let dates = Self.availableAnchorDates(
            samples: samples, gender: gender, fallbackHeightCm: fallbackHeightCm
        )
        availableDates = dates

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

        guard let newerSnapshot = snapshot(
            samples: samples, at: newest, gender: gender, age: age, fallbackHeightCm: fallbackHeightCm
        ) else {
            state = .missingMetrics(BodySnapshotBuilder.requiredKinds(for: gender))
            metricChanges = []
            return
        }

        let olderSnapshot = dates.count > 1 ? dates.last.flatMap {
            snapshot(samples: samples, at: $0, gender: gender, age: age, fallbackHeightCm: fallbackHeightCm)
        } : nil

        let newerResolved = await Self.resolved(newerSnapshot)
        var olderResolved: Resolved?
        if let olderSnapshot { olderResolved = await Self.resolved(olderSnapshot) }
        let resolved = (newerResolved, olderResolved)

        guard !Task.isCancelled else { return }

        guard let older = resolved.1 else {
            state = .single(resolved.0)
            metricChanges = []
            morphProgress = 1
            return
        }

        state = .comparison(older: older, newer: resolved.0)
        metricChanges = Self.changes(from: older.snapshot, to: resolved.0.snapshot)
        morphProgress = 1
    }

    /// The cheap half: reads samples, no reconciliation.
    private func snapshot(
        samples: [MetricSample], at date: Date,
        gender: BodyGender, age: Int, fallbackHeightCm: Double
    ) -> BodySnapshot? {
        let result = BodySnapshotBuilder.build(
            samples: samples, anchorDate: date,
            gender: gender, age: age, fallbackHeightCm: fallbackHeightCm
        )
        guard case let .success(snapshot) = result else { return nil }
        return snapshot
    }

    /// The expensive half. Goes through the shared cache, so a snapshot the
    /// prewarm already solved costs nothing here.
    private static func resolved(_ snapshot: BodySnapshot) async -> Resolved {
        let reconciled = await BodyReconcileCache.resolve(snapshot)
        return Resolved(
            snapshot: snapshot,
            parameters: reconciled.parameters,
            validation: reconciled.validation
        )
    }

    /// Same split as `load`: snapshots here, reconciliation detached.
    func select(olderDate: Date, newerDate: Date, samples: [MetricSample], gender: BodyGender, age: Int, fallbackHeightCm: Double) async {
        guard let olderSnapshot = snapshot(
                samples: samples, at: olderDate, gender: gender, age: age, fallbackHeightCm: fallbackHeightCm
              ),
              let newerSnapshot = snapshot(
                samples: samples, at: newerDate, gender: gender, age: age, fallbackHeightCm: fallbackHeightCm
              )
        else { return }

        let resolved = (await Self.resolved(olderSnapshot), await Self.resolved(newerSnapshot))

        guard !Task.isCancelled else { return }

        state = .comparison(older: resolved.0, newer: resolved.1)
        metricChanges = Self.changes(from: resolved.0.snapshot, to: resolved.1.snapshot)
        morphProgress = 1
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
