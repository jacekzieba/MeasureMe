import SwiftData
import Foundation

/// Abstraction for HealthKit syncing, enabling test stubs.
protocol HealthKitSyncing: Sendable {
    func sync(kind: MetricKind, metricValue: Double, date: Date) async throws
}

/// Handles persisting quick-add entries to SwiftData and optionally syncing to HealthKit.
@MainActor
final class QuickAddSaveService {
    private let context: ModelContext
    private let healthKit: HealthKitSyncing?

    init(context: ModelContext, healthKit: HealthKitSyncing? = nil) {
        self.context = context
        self.healthKit = healthKit
    }

    struct Entry {
        let kind: MetricKind
        let metricValue: Double
    }

    /// Inserts samples into the context and saves.
    func save(entries: [Entry], date: Date) throws {
        for entry in entries {
            context.insert(MetricSample(kind: entry.kind, value: entry.metricValue, date: date))
        }
        try context.save()
    }

    /// Best-effort HealthKit sync — failures are logged but never thrown.
    func syncHealthKit(entries: [Entry], date: Date) async {
        guard let healthKit else { return }
        for entry in entries {
            do {
                try await healthKit.sync(kind: entry.kind, metricValue: entry.metricValue, date: date)
            } catch {
                AppLog.debug("⚠️ HealthKit sync failed for \(entry.kind.rawValue): \(error.localizedDescription)")
            }
        }
    }
}
