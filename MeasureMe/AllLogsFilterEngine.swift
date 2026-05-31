import Foundation

/// Pure, testable filtering logic for the All Logs list.
///
/// Owns the source/date filter definitions shared with `AllLogsView`. The view
/// uses `SourceFilter` for its segmented picker and `customDateBounds(...)` to
/// build its SwiftData paging predicate, so the filtering rules live in one place.
enum AllLogsFilterEngine {

    enum SourceFilter: String, CaseIterable, Identifiable {
        case all
        case manual
        case healthKit

        var id: String { rawValue }
    }

    enum DateFilter: Equatable {
        case all
        case custom(start: Date, end: Date)
    }

    /// Inclusive, day-aligned bounds for a custom date range: from the start of
    /// `start`'s day to the last second of `end`'s day (whole end day included).
    static func customDateBounds(
        start: Date,
        end: Date,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let startDate = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let endDate = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endDay) ?? end
        return (startDate, endDate)
    }

    static func filter(
        samples: [MetricSample],
        sourceFilter: SourceFilter,
        dateFilter: DateFilter,
        calendar: Calendar = .current
    ) -> [MetricSample] {
        let healthKitRaw = MetricSampleSource.healthKit.rawValue
        let bounds: (start: Date, end: Date)?
        switch dateFilter {
        case .all:
            bounds = nil
        case .custom(let start, let end):
            bounds = customDateBounds(start: start, end: end, calendar: calendar)
        }

        return samples.filter { sample in
            switch sourceFilter {
            case .all:
                break
            case .manual:
                if sample.sourceRaw == healthKitRaw { return false }
            case .healthKit:
                if sample.sourceRaw != healthKitRaw { return false }
            }

            if let bounds {
                if sample.date < bounds.start || sample.date > bounds.end { return false }
            }
            return true
        }
    }
}
