// BodySnapshotBuilder.swift
//
// **BodySnapshotBuilder**
// Turns raw `MetricSample` rows into a complete `BodySnapshot`.
//
// **Responsibilities:**
// - Picking, per metric, the sample nearest the anchor date within the sample window
// - Averaging left/right pairs into a single value
// - Reporting every missing metric at once, so the empty state can list them
//
// **Why the window is generous:**
// Nobody measures sixteen circumferences on one day — people work through them in
// batches over weeks. A tight window made every one of those batches incomplete, so
// the screen reported metrics as missing that were sitting in the database, and told
// the user to log something they had already logged. The window's job is to bound
// staleness, not to demand a single measuring session.
//
import Foundation

nonisolated enum BodySnapshotBuildResult: Equatable {
    case success(BodySnapshot)
    /// Every metric the user still needs to log, in `MetricKind.allCases` order.
    case missing([MetricKind])
}

nonisolated enum BodySnapshotBuilder {
    /// Half-width of the window, in days, that a sample may sit from the anchor.
    ///
    /// Not the same thing as `BodyModelViewModel.anchorCollapseDays`, and deliberately much
    /// wider: this bounds how stale an input may be, that one decides when two dates describe
    /// the same body. They were one constant until 2026-08-13, which is what made scattered
    /// measurements read as missing.
    static let sampleWindowDays = 90

    /// Left/right pairs collapsed into one value each.
    private static let pairs: [(left: MetricKind, right: MetricKind)] = [
        (.leftBicep, .rightBicep),
        (.leftForearm, .rightForearm),
        (.leftThigh, .rightThigh),
        (.leftCalf, .rightCalf)
    ]

    /// Metrics required as a single (non-paired) value.
    private static func singleKinds(for gender: BodyGender) -> [MetricKind] {
        var kinds: [MetricKind] = [
            .height, .weight, .bodyFat, .neck, .shoulders, .chest, .waist, .hips
        ]
        if gender == .female { kinds.append(.bust) }
        return kinds
    }

    /// Every metric the user must have logged for this gender.
    static func requiredKinds(for gender: BodyGender) -> [MetricKind] {
        singleKinds(for: gender) + pairs.flatMap { [$0.left, $0.right] }
    }

    /// - Parameters:
    ///   - samples: All samples available; filtered internally by window.
    ///   - anchorDate: The date the snapshot represents.
    ///   - fallbackHeightCm: `manualHeight` from settings, used when no height
    ///     sample falls in the window. Pass 0 when unset.
    static func build(
        samples: [MetricSample],
        anchorDate: Date,
        gender: BodyGender,
        age: Int,
        fallbackHeightCm: Double
    ) -> BodySnapshotBuildResult {
        let window = Double(sampleWindowDays) * 86_400
        // Only kinds this snapshot actually reads may influence it — including
        // its date range. A leanBodyMass or (for men) bust sample sitting in
        // the window must not widen `sourceDateRange`, which is documented as
        // the span of samples actually used.
        let relevant = Set(requiredKinds(for: gender).map(\.rawValue))
        let inWindow = samples.filter {
            relevant.contains($0.kindRaw)
                && abs($0.date.timeIntervalSince(anchorDate)) <= window
        }

        // Nearest sample to the anchor wins, per metric kind.
        var nearest: [String: MetricSample] = [:]
        for sample in inWindow {
            let existing = nearest[sample.kindRaw]
            let isCloser = existing.map {
                abs(sample.date.timeIntervalSince(anchorDate))
                    < abs($0.date.timeIntervalSince(anchorDate))
            } ?? true
            if isCloser { nearest[sample.kindRaw] = sample }
        }

        func value(_ kind: MetricKind) -> Double? {
            nearest[kind.rawValue]?.value
        }

        /// A pair resolves if either side is present; both sides average.
        func pairValue(_ pair: (left: MetricKind, right: MetricKind)) -> Double? {
            switch (value(pair.left), value(pair.right)) {
            case let (left?, right?): return (left + right) / 2
            case let (left?, nil): return left
            case let (nil, right?): return right
            case (nil, nil): return nil
            }
        }

        var missing: [MetricKind] = []
        for kind in singleKinds(for: gender) where value(kind) == nil {
            // Height falls back to the profile value before counting as missing.
            if kind == .height && fallbackHeightCm > 0 { continue }
            missing.append(kind)
        }
        for pair in pairs where pairValue(pair) == nil {
            missing.append(pair.left)
        }

        guard missing.isEmpty else {
            let order = MetricKind.allCases
            return .missing(missing.sorted {
                (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0)
            })
        }

        let usedDates = nearest.values.map(\.date).sorted()
        let range = (usedDates.first ?? anchorDate)...(usedDates.last ?? anchorDate)

        return .success(BodySnapshot(
            gender: gender,
            age: age,
            heightCm: value(.height) ?? fallbackHeightCm,
            weightKg: value(.weight) ?? 0,
            bodyFatPercent: value(.bodyFat) ?? 0,
            neckCm: value(.neck) ?? 0,
            shouldersCm: value(.shoulders) ?? 0,
            chestCm: value(.chest) ?? 0,
            bustCm: gender == .female ? value(.bust) : nil,
            waistCm: value(.waist) ?? 0,
            hipsCm: value(.hips) ?? 0,
            bicepCm: pairValue(pairs[0]) ?? 0,
            forearmCm: pairValue(pairs[1]) ?? 0,
            thighCm: pairValue(pairs[2]) ?? 0,
            calfCm: pairValue(pairs[3]) ?? 0,
            anchorDate: anchorDate,
            sourceDateRange: range
        ))
    }
}
