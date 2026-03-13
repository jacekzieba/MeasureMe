import XCTest
@testable import MeasureMe

actor IntentSyncRecorder {
    private(set) var syncedKinds: [MetricKind] = []

    func append(_ kind: MetricKind) {
        syncedKinds.append(kind)
    }
}

@MainActor
final class IntentDeferredHealthSyncProcessorTests: XCTestCase {
    func testProcessorAttemptsSyncOnceAndClearsQueue() async {
        let suiteName = "IntentDeferredHealthSyncProcessorTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected dedicated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettingsStore(defaults: defaults)
        settings.set(\.health.isSyncEnabled, true)

        IntentDeferredHealthSyncStore.enqueue(
            kind: .weight,
            metricValue: 80,
            date: Date(timeIntervalSince1970: 1_000),
            settings: settings
        )
        IntentDeferredHealthSyncStore.enqueue(
            kind: .waist,
            metricValue: 90,
            date: Date(timeIntervalSince1970: 2_000),
            settings: settings
        )

        let recorder = IntentSyncRecorder()
        await IntentDeferredHealthSyncProcessor.processPendingIfNeeded(settings: settings) { kind, _, _ in
            await recorder.append(kind)
        }

        let syncedKinds = await recorder.syncedKinds
        XCTAssertEqual(syncedKinds, [.weight, .waist])
        XCTAssertTrue(IntentDeferredHealthSyncStore.pendingEntries(settings: settings).isEmpty)
    }
}
