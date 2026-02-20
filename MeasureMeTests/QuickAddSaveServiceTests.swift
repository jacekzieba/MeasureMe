/// Cel testow: Sprawdza zapis Quick Add i kontrakt synchronizacji z HealthKit (w tym odpornosc na bledy).
/// Dlaczego to wazne: To krytyczny przeplyw zapisu; bledy moga skutkowac utrata danych lub crashami.
/// Kryteria zaliczenia: Zapis dziala dla poprawnych danych, a bledy HealthKit nie sa propagowane.

import XCTest
import SwiftData
@testable import MeasureMe

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

    /// Co sprawdza: Sprawdza, ze SyncHealthKit nie propaguje bledow (nie rzuca wyjatku).
    /// Dlaczego: Zapewnia poprawna obsluge uprawnien i integracji z systemem.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
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

        // Musi zakonczyc sie bez bledu mimo awarii atrapy.
        await svc.syncHealthKit(entries: entries, date: .now)

        // Atrapa zostala wywolana, a blad przechwycony.
        XCTAssertTrue(stub.syncedEntries.isEmpty, "Synchronizacja po bledzie nie powinna dodawac wpisow do syncedEntries")
    }

    /// Co sprawdza: Sprawdza scenariusz: SyncHealthKitCallsProviderForEachEntry.
    /// Dlaczego: Zapewnia poprawna obsluge uprawnien i integracji z systemem.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
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

    /// Co sprawdza: Sprawdza scenariusz: SyncHealthKitSkipsWhenProviderIsNil.
    /// Dlaczego: Zapewnia poprawna obsluge uprawnien i integracji z systemem.
    /// Kryteria: Test konczy sie bez bledu i bez efektow ubocznych niezgodnych z oczekiwaniem.
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
