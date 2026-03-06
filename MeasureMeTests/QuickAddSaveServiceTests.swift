/// Cel testow: Sprawdza zapis Quick Add i kontrakt synchronizacji z HealthKit (w tym odpornosc na bledy).
/// Dlaczego to wazne: To krytyczny przeplyw zapisu; bledy moga skutkowac utrata danych lub crashami.
/// Kryteria zaliczenia: Zapis dziala dla poprawnych danych, a bledy HealthKit nie sa propagowane.

import XCTest
import SwiftData
@testable import MeasureMe

@MainActor
final class QuickAddSaveServiceTests: XCTestCase {

    // MARK: - Stubs

    private final class StubHealthKit: HealthKitSyncing, @unchecked Sendable {
        var syncedEntries: [(MetricKind, Double, Date)] = []
        var shouldThrow = false

        func sync(kind: MetricKind, metricValue: Double, date: Date) async throws {
            if shouldThrow { throw NSError(domain: "test", code: 1) }
            syncedEntries.append((kind, metricValue, date))
        }
    }

    private final class StubStreak: StreakTracking {
        var recordedDates: [Date] = []
        func recordMetricSaved(date: Date) { recordedDates.append(date) }
    }

    private final class StubWidgetWriter: WidgetDataWriting {
        var writeCalls: [(kinds: [MetricKind], unitsSystem: String)] = []
        func writeAndReload(kinds: [MetricKind], context: ModelContext, unitsSystem: String) {
            writeCalls.append((kinds, unitsSystem))
        }
    }

    // MARK: - Setup

    private var ctx: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        #if !targetEnvironment(simulator)
        throw XCTSkip("QuickAddSaveServiceTests are unstable on this physical iOS setup due allocator crash; covered on simulator.")
        #else

        let schema = Schema([MetricSample.self, MetricGoal.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        ctx = ModelContext(container)
        #endif
    }

    // MARK: - syncHealthKit Tests

    /// Co sprawdza: Sprawdza, ze SyncHealthKit nie propaguje bledow (nie rzuca wyjatku).
    /// Dlaczego: Zapewnia poprawna obsluge uprawnien i integracji z systemem.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testSyncHealthKitDoesNotThrowOnFailure() async {
        let stub = StubHealthKit()
        stub.shouldThrow = true
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
        let svc = QuickAddSaveService(context: ctx, healthKit: nil)

        let entries: [QuickAddSaveService.Entry] = [
            .init(kind: .weight, metricValue: 80),
        ]

        // Must not crash or throw — just a no-op.
        await svc.syncHealthKit(entries: entries, date: .now)
    }

    // MARK: - save() Tests

    /// Co sprawdza: Zapis tworzy MetricSample w kontekscie SwiftData.
    /// Dlaczego: save() jest krytycznym przeplywem; musi trwale zapisywac wpisy.
    /// Kryteria: Po wywolaniu save() kontekst zawiera dokladnie 1 probke z oczekiwanym rodzajem.
    func testSaveInsertsSampleIntoContext() throws {
        let streak = StubStreak()
        let writer = StubWidgetWriter()
        let service = QuickAddSaveService(context: ctx, streak: streak, widgetWriter: writer)

        try service.save(entries: [.init(kind: .weight, metricValue: 80.0)], date: Date(), unitsSystem: "metric")

        let saved = try ctx.fetch(FetchDescriptor<MetricSample>())
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.kind, .weight)
    }

    /// Co sprawdza: save() wywoluje streak i widget writer po udanym zapisie.
    /// Dlaczego: Efekty uboczne (streak, widget) musza byc wywolane dokladnie raz na niepusty zapis.
    /// Kryteria: Stub streak ma 1 wpis; stub writer ma 1 wywolanie z poprawnym unitsSystem.
    func testSaveCallsStreakAndWidget() throws {
        let streak = StubStreak()
        let writer = StubWidgetWriter()
        let service = QuickAddSaveService(context: ctx, streak: streak, widgetWriter: writer)
        let date = Date()

        try service.save(entries: [.init(kind: .weight, metricValue: 80.0)], date: date, unitsSystem: "imperial")

        XCTAssertEqual(streak.recordedDates.count, 1)
        XCTAssertEqual(writer.writeCalls.first?.unitsSystem, "imperial")
    }

    /// Co sprawdza: Pusta lista entries pomija efekty uboczne.
    /// Dlaczego: save([]) nie powinno wywolywac streak ani writera — brak realnych danych.
    /// Kryteria: Oba stuby pozostaja puste po wywolaniu z pustymi entries.
    func testEmptyEntriesSkipsSideEffects() throws {
        let streak = StubStreak()
        let writer = StubWidgetWriter()
        let service = QuickAddSaveService(context: ctx, streak: streak, widgetWriter: writer)

        try service.save(entries: [], date: Date(), unitsSystem: "metric")

        XCTAssertTrue(streak.recordedDates.isEmpty)
        XCTAssertTrue(writer.writeCalls.isEmpty)
    }

    /// Co sprawdza: Wiele entries przekazuje wszystkie MetricKind do widget writera.
    /// Dlaczego: Writer musi znac wszystkie rodzaje metryk, by zaktualizowac odpowiednie widgety.
    /// Kryteria: writeCalls[0].kinds zawiera 2 elementy.
    func testSaveWithMultipleEntriesPassesAllKindsToWidget() throws {
        let streak = StubStreak()
        let writer = StubWidgetWriter()
        let service = QuickAddSaveService(context: ctx, streak: streak, widgetWriter: writer)
        let entries: [QuickAddSaveService.Entry] = [
            .init(kind: .weight, metricValue: 80.0),
            .init(kind: .waist, metricValue: 90.0),
        ]

        try service.save(entries: entries, date: Date(), unitsSystem: "metric")

        XCTAssertEqual(writer.writeCalls.first?.kinds.count, 2)
    }
}
