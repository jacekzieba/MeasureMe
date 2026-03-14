import Foundation

/// Validates that measurement changes are physiologically plausible.
///
/// Unlike `MetricInputValidator` (which checks absolute ranges), `SanityChecker`
/// compares a new value against the most recent stored value, scaling the
/// allowed change by the elapsed time. If the change exceeds the threshold,
/// the entry is flagged so the UI can show a confirmation dialog.
enum SanityChecker {
    struct SuspiciousEntry: Equatable {
        let kind: MetricKind
        let previousValue: Double   // metric units
        let newValue: Double         // metric units
        let previousDate: Date
        let newDate: Date
    }

    /// Returns entries whose change exceeds the time-scaled threshold.
    ///
    /// - Parameters:
    ///   - entries: New measurements. Values must be in **metric** units.
    ///   - previousValues: Most recent stored value per metric (metric units).
    /// - Returns: Array of suspicious entries (empty when everything looks fine).
    static func check(
        entries: [(kind: MetricKind, metricValue: Double, date: Date)],
        previousValues: [MetricKind: (value: Double, date: Date)]
    ) -> [SuspiciousEntry] {
        entries.compactMap { entry in
            guard let previous = previousValues[entry.kind] else {
                // First-ever entry — nothing to compare against.
                return nil
            }

            let absoluteChange = abs(entry.metricValue - previous.value)
            let elapsedDays = max(
                Calendar.current.dateComponents([.day], from: previous.date, to: entry.date).day.map(Double.init) ?? 0,
                1 // minimum 1 day to avoid false positives on same-day entries
            )
            let elapsedWeeks = elapsedDays / 7.0
            let allowedChange = maxChangePerWeek(for: entry.kind) * elapsedWeeks

            guard absoluteChange > allowedChange else { return nil }

            return SuspiciousEntry(
                kind: entry.kind,
                previousValue: previous.value,
                newValue: entry.metricValue,
                previousDate: previous.date,
                newDate: entry.date
            )
        }
    }

    /// Maximum plausible change per week in metric units.
    static func maxChangePerWeek(for kind: MetricKind) -> Double {
        switch kind {
        case .weight:                                           return 3.0  // kg
        case .bodyFat:                                          return 3.0  // %
        case .leanBodyMass:                                     return 2.0  // kg
        case .height:                                           return 2.0  // cm
        case .waist, .hips, .bust, .chest, .shoulders:          return 5.0  // cm
        case .neck:                                             return 2.0  // cm
        case .leftBicep, .rightBicep,
             .leftForearm, .rightForearm:                       return 3.0  // cm
        case .leftThigh, .rightThigh:                           return 4.0  // cm
        case .leftCalf, .rightCalf:                             return 3.0  // cm
        }
    }
}
