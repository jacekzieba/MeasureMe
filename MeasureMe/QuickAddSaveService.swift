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

    init(context: ModelContext, healthKit: HealthKitSyncing? = nil) {
        self.context = context
        self.healthKit = healthKit
    }

    struct Entry {
        let kind: MetricKind
        let metricValue: Double
    }

    /// Dodaje probki do kontekstu i zapisuje.
    func save(entries: [Entry], date: Date) throws {
        for entry in entries {
            context.insert(MetricSample(kind: entry.kind, value: entry.metricValue, date: date))
        }
        try context.save()
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
