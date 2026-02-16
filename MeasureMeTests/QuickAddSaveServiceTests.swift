import XCTest
import SwiftData
@testable import MeasureMe

/// Tests for QuickAddSaveService.
///
/// Persistence round-trip (insert → save → fetch) is already covered by
/// `PersistenceAndModelIntegrityTests`.  These tests focus on service-level
/// behaviour: HealthKit sync contract and error resilience.
@MainActor
final class QuickAddSaveServiceTests: XCTestCase {

    // MARK: - Stub

    private final class StubHealthKit: HealthKitSyncing, @unchecked Sendable {
        var syncedEntries: [(MetricKind, Double, Date)] = []
        var shouldThrow = false

        func sync(kind: MetricKind, metricValue: Double, date: Date) async throws {
            if shouldThrow { throw NSError(domain: "test", code: 1) }
            syncedEntries.append((kind, metricValue, date))
        }
    }

    // MARK: - Tests

    /// syncHealthKit must swallow HealthKit errors — they must never propagate.
    func testSyncHealthKitDoesNotThrowOnFailure() async {
        let stub = StubHealthKit()
        stub.shouldThrow = true

        let schema = Schema([MetricSample.self, MetricGoal.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let ctx = ModelContext(container)
        let svc = QuickAddSaveService(context: ctx, healthKit: stub)

        let entries: [QuickAddSaveService.Entry] = [
            .init(kind: .weight, metricValue: 80),
        ]

        // Must complete without throwing despite stub failure.
        await svc.syncHealthKit(entries: entries, date: .now)

        // Stub was called, error was swallowed.
        XCTAssertTrue(stub.syncedEntries.isEmpty, "Failed sync should not append to syncedEntries")
    }

    /// syncHealthKit must call the HealthKit provider once per entry.
    func testSyncHealthKitCallsProviderForEachEntry() async {
        let stub = StubHealthKit()

        let schema = Schema([MetricSample.self, MetricGoal.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let ctx = ModelContext(container)
        let svc = QuickAddSaveService(context: ctx, healthKit: stub)

        let date = Date()
        let entries: [QuickAddSaveService.Entry] = [
            .init(kind: .weight, metricValue: 80),
            .init(kind: .bodyFat, metricValue: 18.5),
        ]

        await svc.syncHealthKit(entries: entries, date: date)

        XCTAssertEqual(stub.syncedEntries.count, 2)
        XCTAssertEqual(stub.syncedEntries[0].0, .weight)
        XCTAssertEqual(stub.syncedEntries[0].1, 80, accuracy: 0.001)
        XCTAssertEqual(stub.syncedEntries[1].0, .bodyFat)
        XCTAssertEqual(stub.syncedEntries[1].1, 18.5, accuracy: 0.001)
    }

    /// syncHealthKit with nil provider does nothing (no crash).
    func testSyncHealthKitSkipsWhenProviderIsNil() async {
        let schema = Schema([MetricSample.self, MetricGoal.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let ctx = ModelContext(container)
        let svc = QuickAddSaveService(context: ctx, healthKit: nil)

        let entries: [QuickAddSaveService.Entry] = [
            .init(kind: .weight, metricValue: 80),
        ]

        // Must not crash or throw — just a no-op.
        await svc.syncHealthKit(entries: entries, date: .now)
    }
}
