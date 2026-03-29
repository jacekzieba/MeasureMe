import Foundation
import SwiftData

extension [MetricSample] {
    /// Calculates the metric value change within a given time window.
    /// Returns a formatted string (e.g. "+1.2 kg") or nil when there is no data or only one sample.
    /// Independent of the sort order of the provided array.
    func deltaText(
        days: Int,
        kind: MetricKind,
        unitsSystem: String,
        now: Date = AppClock.now
    ) -> String? {
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return nil }
        let window = filter { $0.date >= start }
        guard let newest = window.max(by: { $0.date < $1.date }),
              let oldest = window.min(by: { $0.date < $1.date }),
              newest.persistentModelID != oldest.persistentModelID else {
            return nil
        }
        let newestValue = kind.valueForDisplay(fromMetric: newest.value, unitsSystem: unitsSystem)
        let oldestValue = kind.valueForDisplay(fromMetric: oldest.value, unitsSystem: unitsSystem)
        let delta = newestValue - oldestValue
        return kind.formattedDisplayValue(delta, unitsSystem: unitsSystem, alwaysShowSign: true)
    }

    /// Returns the raw delta for a time window (or all-time when days == nil).
    /// The oldest/newest values are in metric units (for use with trendOutcome).
    func trendDelta(
        days: Int?,
        kind: MetricKind,
        unitsSystem: String,
        now: Date = AppClock.now
    ) -> (displayDelta: Double, oldestValue: Double, newestValue: Double)? {
        let window: [MetricSample]
        if let days {
            guard let start = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return nil }
            window = filter { $0.date >= start }
        } else {
            window = Array(self)
        }
        guard let newest = window.max(by: { $0.date < $1.date }),
              let oldest = window.min(by: { $0.date < $1.date }),
              newest.persistentModelID != oldest.persistentModelID else {
            return nil
        }
        let newestDisplay = kind.valueForDisplay(fromMetric: newest.value, unitsSystem: unitsSystem)
        let oldestDisplay = kind.valueForDisplay(fromMetric: oldest.value, unitsSystem: unitsSystem)
        return (newestDisplay - oldestDisplay, oldest.value, newest.value)
    }
}
