import Foundation
import SwiftData
import WidgetKit

/// Writes metric data to the App Group shared container so the widget can read it.
/// Call after saving any MetricSample to keep the widget up to date.
enum WidgetDataWriter {
    static let appGroupID = "group.com.jacek.measureme"
    static let widgetKind = "MetricWidget"

    // MARK: - Payload (matches WidgetMetricData in widget target)

    private struct SamplePayload: Encodable {
        let value: Double
        let date: Date
    }

    private struct GoalPayload: Encodable {
        let targetValue: Double
        let startValue: Double?
        let direction: String
    }

    private struct MetricPayload: Encodable {
        let kind: String
        let samples: [SamplePayload]
        let goal: GoalPayload?
        let unitsSystem: String
    }

    // MARK: - Public API

    /// Writes data for the given metrics and triggers a widget timeline reload.
    /// Fetches the last 90 days of samples from the provided context.
    static func writeAndReload(
        kinds: [MetricKind],
        context: ModelContext,
        unitsSystem: String
    ) {
        let kindsDescription = kinds.map { $0.rawValue }.joined(separator: ",")
        AppLog.debug("🧩 WidgetDataWriter: writeAndReload kinds=\(kindsDescription) count=\(kinds.count)")
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }

        let cutoff = Date().addingTimeInterval(-90 * 24 * 3600)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970

        for kind in kinds {
            let kindRawValue = kind.rawValue

            // Fetch samples for this metric
            let descriptor = FetchDescriptor<MetricSample>(
                predicate: #Predicate<MetricSample> { sample in
                    sample.kindRaw == kindRawValue && sample.date >= cutoff
                },
                sortBy: [SortDescriptor(\.date)]
            )
            let samples = (try? context.fetch(descriptor)) ?? []

            // Fetch goal for this metric
            let goalDescriptor = FetchDescriptor<MetricGoal>(
                predicate: #Predicate<MetricGoal> { goal in
                    goal.kindRaw == kindRawValue
                }
            )
            let goal = (try? context.fetch(goalDescriptor))?.first

            let sampleDTOs = samples.map { SamplePayload(value: $0.value, date: $0.date) }
            let goalDTO: GoalPayload? = goal.map {
                GoalPayload(targetValue: $0.targetValue, startValue: $0.startValue, direction: $0.directionRaw)
            }
            let payload = MetricPayload(kind: kind.rawValue, samples: sampleDTOs, goal: goalDTO, unitsSystem: unitsSystem)

            if let data = try? encoder.encode(payload) {
                defaults.set(data, forKey: "widget_data_\(kind.rawValue)")
            }
        }

        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        AppLog.debug("🧩 WidgetDataWriter: reloadTimelines(ofKind: \(widgetKind))")
    }

    /// Writes data for all MetricKind cases that have at least one sample.
    /// Intended for initial population at app startup.
    static func writeAllAndReload(context: ModelContext, unitsSystem: String) {
        writeAndReload(kinds: MetricKind.allCases, context: context, unitsSystem: unitsSystem)
    }
}
