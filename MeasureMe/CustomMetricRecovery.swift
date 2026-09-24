// CustomMetricRecovery.swift
//
// **CustomMetricRecovery**
// Recreates custom metric definitions whose samples or goals survived without them.
//
// **Why:**
// Adding a measurement from Shortcuts or Siri used to open the store with a schema that left out
// `CustomMetricDefinition`, and SwiftData dropped every definition. The samples and goals kept their
// `custom_<UUID>` identifiers, but without a definition the app no longer showed them. The name and
// unit are gone for good; the definition comes back under a placeholder name the person can edit.
//
import Foundation
import SwiftData

enum CustomMetricRecovery {
    /// Returns how many definitions were recreated.
    @discardableResult
    static func recoverOrphanedDefinitions(in context: ModelContext, settings: AppSettingsStore) throws -> Int {
        let customPrefix = "custom_"
        let known = Set(try context.fetch(FetchDescriptor<CustomMetricDefinition>()).map(\.identifier))

        var firstUse: [String: Date] = [:]
        let samples = try context.fetch(FetchDescriptor<MetricSample>(
            predicate: #Predicate { $0.kindRaw.starts(with: customPrefix) }
        ))
        for sample in samples where !known.contains(sample.kindRaw) {
            firstUse[sample.kindRaw] = min(firstUse[sample.kindRaw] ?? sample.date, sample.date)
        }
        let goals = try context.fetch(FetchDescriptor<MetricGoal>(
            predicate: #Predicate { $0.kindRaw.starts(with: customPrefix) }
        ))
        for goal in goals where !known.contains(goal.kindRaw) {
            firstUse[goal.kindRaw] = min(firstUse[goal.kindRaw] ?? goal.createdDate, goal.createdDate)
        }
        guard !firstUse.isEmpty else { return 0 }

        let orphans = firstUse.sorted { ($0.value, $0.key) < ($1.value, $1.key) }
        let metricsStore = ActiveMetricsStore(settings: settings)
        for (offset, orphan) in orphans.enumerated() {
            let definition = CustomMetricDefinition(
                name: String(format: AppLocalization.string("Recovered metric %d"), offset + 1),
                unitLabel: "",
                sortOrder: known.count + offset
            )
            definition.identifier = orphan.key
            definition.createdDate = orphan.value
            context.insert(definition)

            // A metric the person switched off stays off; one with no setting left is shown so the data
            // is visible again.
            if settings.object(forKey: AppSettingsKeys.Metrics.customEnabled(orphan.key)) == nil {
                metricsStore.setCustomEnabled(true, for: orphan.key)
            }
        }
        try context.save()
        AppLog.debug("CustomMetricRecovery: recreated \(orphans.count) custom metric definition(s)")
        return orphans.count
    }
}
