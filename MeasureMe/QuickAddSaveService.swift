import SwiftData
import Foundation

/// Abstrakcja synchronizacji HealthKit, ulatwiajaca tworzenie atrap testowych.
protocol HealthKitSyncing: Sendable {
    func sync(kind: MetricKind, metricValue: Double, date: Date) async throws
}

/// Obsluguje zapis wpisow Quick Add do SwiftData i opcjonalna synchronizacje z HealthKit.
@MainActor
final class QuickAddSaveService {
    private let context: ModelContext
    private let healthKit: HealthKitSyncing?
    private let streak: StreakTracking
    private let widgetWriter: WidgetDataWriting

    init(
        context: ModelContext,
        healthKit: HealthKitSyncing? = nil,
        streak: StreakTracking? = nil,
        widgetWriter: WidgetDataWriting? = nil
    ) {
        self.context = context
        self.healthKit = healthKit
        self.streak = streak ?? StreakManager.shared
        self.widgetWriter = widgetWriter ?? LiveWidgetDataWriter()
    }

    struct Entry {
        let kind: MetricKind
        let metricValue: Double
    }

    /// Dodaje probki do kontekstu i zapisuje.
    func save(entries: [Entry], date: Date, unitsSystem: String) throws {
        guard !entries.isEmpty else { return }

        let previousMetricCount = AnalyticsFirstEventTracker.metricCount(in: context)

        for entry in entries {
            context.insert(MetricSample(kind: entry.kind, value: entry.metricValue, date: date))
        }
        try context.save()
        AnalyticsFirstEventTracker.trackFirstMetricIfNeeded(previousMetricCount: previousMetricCount)
        streak.recordMetricSaved(date: date)
        widgetWriter.writeAndReload(kinds: entries.map(\.kind), context: context, unitsSystem: unitsSystem)
        WatchSessionManager.shared.sendApplicationContext()
    }

    struct CustomEntry {
        let identifier: String
        let value: Double
    }

    /// Zapisuje pomiary custom metryk do SwiftData. Pomija HealthKit i widgety.
    func saveCustom(entries: [CustomEntry], date: Date) throws {
        guard !entries.isEmpty else { return }

        for entry in entries {
            context.insert(MetricSample(kindRaw: entry.identifier, value: entry.value, date: date))
        }
        try context.save()
        streak.recordMetricSaved(date: date)
    }

    /// Synchronizacja HealthKit w trybie najlepszej starannosci — failures are logged but never thrown.
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
