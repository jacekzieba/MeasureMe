/// Cel testow: Weryfikuje zachowanie autoryzacji HealthKit i reakcje managera na rozne stany dostepu.
/// Dlaczego to wazne: Zle mapowanie uprawnien blokuje import i wprowadza uzytkownika w blad.
/// Kryteria zaliczenia: Dla kazdego stanu autoryzacji wynik jest poprawny i bez nieoczekiwanych wyjatkow.

import XCTest
import HealthKit
@testable import MeasureMe

private final class MockHealthStore: HealthStore {
    static let supportedIdentifiers: [HKQuantityTypeIdentifier] = [
        .waistCircumference,
        .bodyMassIndex,
        .height,
        .bodyMass,
        .bodyFatPercentage,
        .leanBodyMass
    ]

    var healthDataAvailable = true
    var requestAuthorizationError: Error?
    var quantityStatuses: [HKQuantityTypeIdentifier: HKAuthorizationStatus] = [:]
    var statusesAfterRequest: [HKQuantityTypeIdentifier: HKAuthorizationStatus]?
    private(set) var requestAuthorizationCallCount = 0

    func isHealthDataAvailable() -> Bool {
        healthDataAvailable
    }

    func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws {
        requestAuthorizationCallCount += 1
        if let requestAuthorizationError {
            throw requestAuthorizationError
        }
        if let statusesAfterRequest {
            quantityStatuses.merge(statusesAfterRequest) { _, new in new }
        }
    }

    func authorizationStatus(for identifier: HKQuantityTypeIdentifier) throws -> HKAuthorizationStatus {
        quantityStatuses[identifier] ?? .sharingDenied
    }

    func latestQuantity(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> (value: Double, date: Date)? {
        nil
    }

    func anchoredQuantitySamples(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        anchorData: Data?,
        since: Date?
    ) async throws -> (samples: [(value: Double, date: Date, sourceBundleID: String?)], newAnchorData: Data?) {
        ([], nil)
    }

    func saveQuantity(_ value: Double, unit: HKUnit, identifier: HKQuantityTypeIdentifier, date: Date) async throws {}

    func fetchWaistMeasurements() async throws -> [(value: Double, date: Date)] {
        []
    }

    func saveWaistMeasurement(value: Double, date: Date) async throws {}

    func deleteWaistMeasurements(inDay date: Date) async throws {}
}

@MainActor
final class HealthKitManagerAuthorizationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var settings: AppSettingsStore!

    override func setUp() {
        super.setUp()
        let suiteName = "HealthKitManagerAuthorizationTests.\(name)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        settings = AppSettingsStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "HealthKitManagerAuthorizationTests.\(name)")
        defaults = nil
        settings = nil
        super.tearDown()
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        pollNanoseconds: UInt64 = 10_000_000,
        _ condition: @autoclosure () -> Bool
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !condition() && DispatchTime.now().uptimeNanoseconds < deadline {
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
    }

    /// Co sprawdza: Sprawdza scenariusz: RequestAuthorizationThrowsNotAvailable.
    /// Dlaczego: Zapewnia poprawna obsluge uprawnien i integracji z systemem.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testRequestAuthorizationThrowsNotAvailable() async {
        let store = MockHealthStore()
        store.healthDataAvailable = false
        let manager = HealthKitManager(store: store, settings: settings)

        do {
            try await manager.requestAuthorization()
            XCTFail("Expected notAvailable error")
        } catch let error as HealthKitAuthorizationError {
            XCTAssertEqual(error, .notAvailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Co sprawdza: Sprawdza scenariusz: RequestAuthorizationThrowsDeniedWhenNoTypeAuthorized.
    /// Dlaczego: Zapewnia poprawna obsluge uprawnien i integracji z systemem.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testRequestAuthorizationThrowsDeniedWhenNoTypeAuthorized() async {
        let store = MockHealthStore()
        let manager = HealthKitManager(store: store, settings: settings)

        do {
            try await manager.requestAuthorization()
            XCTFail("Expected denied error")
        } catch let error as HealthKitAuthorizationError {
            XCTAssertEqual(error, .denied)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Co sprawdza: Brak wstepnych zgód nadal prowadzi przez żądanie systemowe.
    /// Dlaczego: Pierwsza autoryzacja nie może zostać pominięta.
    /// Kryteria: Manager wywołuje requestAuthorization i kończy powodzeniem po nadaniu zgód.
    func testRequestAuthorizationRequestsWhenNoTypesAuthorized() async throws {
        let store = MockHealthStore()
        store.statusesAfterRequest = Dictionary(
            uniqueKeysWithValues: MockHealthStore.supportedIdentifiers.map { ($0, .sharingAuthorized) }
        )
        let manager = HealthKitManager(store: store, settings: settings)

        try await manager.requestAuthorization()
        XCTAssertEqual(store.requestAuthorizationCallCount, 1, "Expected first-time authorization to call HealthKit.")
    }

    /// Co sprawdza: Częściowe zgody nadal prowadzą przez żądanie systemowe.
    /// Dlaczego: Nowe typy metryk po aktualizacji muszą zostać dopytane.
    /// Kryteria: Manager nie używa fast-pathu, jeśli tylko część typów ma autoryzację.
    func testRequestAuthorizationRequestsWhenOnlySomeTypesAuthorized() async throws {
        let store = MockHealthStore()
        store.quantityStatuses[.bodyMass] = .sharingAuthorized
        store.statusesAfterRequest = Dictionary(
            uniqueKeysWithValues: MockHealthStore.supportedIdentifiers.map { ($0, .sharingAuthorized) }
        )
        let manager = HealthKitManager(store: store, settings: settings)

        try await manager.requestAuthorization()
        XCTAssertEqual(store.requestAuthorizationCallCount, 1, "Expected HealthKit to re-request missing metric types.")
    }

    /// Co sprawdza: Pełna autoryzacja używa fast-pathu bez kolejnego promptu.
    /// Dlaczego: Nie chcemy niepotrzebnie ponawiać systemowego okna uprawnień.
    /// Kryteria: RequestAuthorization nie jest wywoływane ponownie, gdy wszystkie typy są już autoryzowane.
    func testRequestAuthorizationSkipsPromptWhenAllTypesAuthorized() async throws {
        let store = MockHealthStore()
        store.quantityStatuses = Dictionary(
            uniqueKeysWithValues: MockHealthStore.supportedIdentifiers.map { ($0, .sharingAuthorized) }
        )
        let manager = HealthKitManager(store: store, settings: settings)

        try await manager.requestAuthorization()
        XCTAssertEqual(store.requestAuthorizationCallCount, 0, "Expected fast-path when every supported type is already authorized.")
    }

    /// Co sprawdza: Nowo dodane typy po upgrade wymuszają ponowne żądanie zgody.
    /// Dlaczego: Użytkownik może mieć stare zgody bez nowszych metryk.
    /// Kryteria: Manager ponawia requestAuthorization, gdy choć jeden wspierany typ nie jest jeszcze autoryzowany.
    func testRequestAuthorizationRequestsWhenUpgradeAddsNewTypes() async throws {
        let store = MockHealthStore()
        let previouslyAuthorized: [HKQuantityTypeIdentifier] = [.bodyMass, .bodyFatPercentage]
        for identifier in previouslyAuthorized {
            store.quantityStatuses[identifier] = .sharingAuthorized
        }
        store.statusesAfterRequest = Dictionary(
            uniqueKeysWithValues: MockHealthStore.supportedIdentifiers.map { ($0, .sharingAuthorized) }
        )
        let manager = HealthKitManager(store: store, settings: settings)

        try await manager.requestAuthorization()
        XCTAssertEqual(store.requestAuthorizationCallCount, 1, "Expected authorization refresh when upgrade adds unsupported-yet-ungranted types.")
    }

    /// Co sprawdza: Sprawdza scenariusz: ReconcileStoredSyncStateDisablesSyncWhenHealthUnavailable.
    /// Dlaczego: Zapewnia poprawna obsluge uprawnien i integracji z systemem.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testReconcileStoredSyncStateDisablesSyncWhenHealthUnavailable() async {
        let store = MockHealthStore()
        store.healthDataAvailable = false
        let manager = HealthKitManager(store: store, settings: settings)
        settings.set(\.health.isSyncEnabled, true)
        await waitUntil(settings.snapshot.health.isSyncEnabled)

        let result = manager.reconcileStoredSyncState()
        await waitUntil(!settings.snapshot.health.isSyncEnabled)

        XCTAssertEqual(result, .notAvailable)
        XCTAssertFalse(settings.snapshot.health.isSyncEnabled)
    }

    /// Co sprawdza: Sprawdza scenariusz: ReconcileStoredSyncStateDisablesSyncWhenNoAuthorizedTypes.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testReconcileStoredSyncStateDisablesSyncWhenNoAuthorizedTypes() async {
        let store = MockHealthStore()
        let manager = HealthKitManager(store: store, settings: settings)
        settings.set(\.health.isSyncEnabled, true)
        await waitUntil(settings.snapshot.health.isSyncEnabled)

        let result = manager.reconcileStoredSyncState()
        await waitUntil(!settings.snapshot.health.isSyncEnabled)

        XCTAssertEqual(result, .denied)
        XCTAssertFalse(settings.snapshot.health.isSyncEnabled)
    }
}
