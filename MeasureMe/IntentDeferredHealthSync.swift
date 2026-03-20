import Foundation

struct PendingHealthKitIntentSyncEntry: Codable, Equatable, Sendable {
    let kindRaw: String
    let metricValue: Double
    let date: Date
}

enum IntentDeferredHealthSyncStore {
    @MainActor
    static func enqueue(
        kind: MetricKind,
        metricValue: Double,
        date: Date,
        settings: AppSettingsStore
    ) {
        var entries = pendingEntries(settings: settings)
        entries.append(
            PendingHealthKitIntentSyncEntry(
                kindRaw: kind.rawValue,
                metricValue: metricValue,
                date: date
            )
        )
        persist(entries, settings: settings)
    }

    @MainActor
    static func pendingEntries(
        settings: AppSettingsStore
    ) -> [PendingHealthKitIntentSyncEntry] {
        guard let data = settings.data(forKey: AppSettingsKeys.Entry.pendingHealthKitSyncFromIntent) else {
            return []
        }
        return (try? JSONDecoder().decode([PendingHealthKitIntentSyncEntry].self, from: data)) ?? []
    }

    @MainActor
    static func drain(settings: AppSettingsStore) -> [PendingHealthKitIntentSyncEntry] {
        let entries = pendingEntries(settings: settings)
        settings.removeObject(forKey: AppSettingsKeys.Entry.pendingHealthKitSyncFromIntent)
        return entries
    }

    @MainActor
    private static func persist(
        _ entries: [PendingHealthKitIntentSyncEntry],
        settings: AppSettingsStore
    ) {
        if entries.isEmpty {
            settings.removeObject(forKey: AppSettingsKeys.Entry.pendingHealthKitSyncFromIntent)
            return
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        settings.set(data, forKey: AppSettingsKeys.Entry.pendingHealthKitSyncFromIntent)
    }
}

@MainActor
extension IntentDeferredHealthSyncStore {
    static func enqueue(kind: MetricKind, metricValue: Double, date: Date) {
        enqueue(kind: kind, metricValue: metricValue, date: date, settings: .shared)
    }

    static func pendingEntries() -> [PendingHealthKitIntentSyncEntry] {
        pendingEntries(settings: .shared)
    }

    static func drain() -> [PendingHealthKitIntentSyncEntry] {
        drain(settings: .shared)
    }
}

@MainActor
enum IntentDeferredHealthSyncProcessor {
    static func processPendingIfNeeded(
        settings: AppSettingsStore,
        syncOperation: @escaping @Sendable (MetricKind, Double, Date) async throws -> Void = { kind, metricValue, date in
            try await HealthKitManager.shared.sync(kind: kind, metricValue: metricValue, date: date)
        }
    ) async {
        guard settings.snapshot.health.isSyncEnabled else { return }

        let entries = IntentDeferredHealthSyncStore.drain(settings: settings)
        guard !entries.isEmpty else { return }

        var failedEntries: [PendingHealthKitIntentSyncEntry] = []
        for entry in entries {
            guard let kind = MetricKind(rawValue: entry.kindRaw), kind.isHealthSynced else { continue }
            do {
                try await syncOperation(kind, entry.metricValue, entry.date)
            } catch {
                AppLog.debug("⚠️ Deferred HealthKit sync from intent failed for \(kind.rawValue): \(error.localizedDescription)")
                failedEntries.append(entry)
            }
        }
        // Re-enqueue failed entries for next attempt
        for failed in failedEntries {
            if let kind = MetricKind(rawValue: failed.kindRaw) {
                IntentDeferredHealthSyncStore.enqueue(
                    kind: kind, metricValue: failed.metricValue, date: failed.date, settings: settings
                )
            }
        }
    }
}

@MainActor
extension IntentDeferredHealthSyncProcessor {
    static func processPendingIfNeeded(
        syncOperation: @escaping @Sendable (MetricKind, Double, Date) async throws -> Void = { kind, metricValue, date in
            try await HealthKitManager.shared.sync(kind: kind, metricValue: metricValue, date: date)
        }
    ) async {
        await processPendingIfNeeded(settings: .shared, syncOperation: syncOperation)
    }
}
