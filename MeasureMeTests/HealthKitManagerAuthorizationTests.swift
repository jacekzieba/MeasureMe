/// Cel testow: Weryfikuje zachowanie autoryzacji HealthKit i reakcje managera na rozne stany dostepu.
/// Dlaczego to wazne: Zle mapowanie uprawnien blokuje import i wprowadza uzytkownika w blad.
/// Kryteria zaliczenia: Dla kazdego stanu autoryzacji wynik jest poprawny i bez nieoczekiwanych wyjatkow.

import XCTest
import HealthKit
@testable import MeasureMe

private final class MockHealthStore: HealthStore {
    var healthDataAvailable = true
    var requestAuthorizationError: Error?
    var quantityStatuses: [HKQuantityTypeIdentifier: HKAuthorizationStatus] = [:]
    private(set) var didRequestAuthorization = false

    func isHealthDataAvailable() -> Bool {
        healthDataAvailable
    }

    func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws {
        didRequestAuthorization = true
        if let requestAuthorizationError {
            throw requestAuthorizationError
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
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "isSyncEnabled")
        super.tearDown()
    }

    /// Co sprawdza: Sprawdza scenariusz: RequestAuthorizationThrowsNotAvailable.
    /// Dlaczego: Zapewnia poprawna obsluge uprawnien i integracji z systemem.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testRequestAuthorizationThrowsNotAvailable() async {
        let store = MockHealthStore()
        store.healthDataAvailable = false
        let manager = HealthKitManager(store: store)

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
        let manager = HealthKitManager(store: store)

        do {
            try await manager.requestAuthorization()
            XCTFail("Expected denied error")
        } catch let error as HealthKitAuthorizationError {
            XCTAssertEqual(error, .denied)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Co sprawdza: Sprawdza scenariusz: RequestAuthorizationSucceedsWhenAtLeastOneTypeAuthorized.
    /// Dlaczego: Zapewnia poprawna obsluge uprawnien i integracji z systemem.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testRequestAuthorizationSucceedsWhenAtLeastOneTypeAuthorized() async throws {
        let store = MockHealthStore()
        store.quantityStatuses[.bodyMass] = .sharingAuthorized
        let manager = HealthKitManager(store: store)

        try await manager.requestAuthorization()
        XCTAssertTrue(store.didRequestAuthorization)
    }

    /// Co sprawdza: Sprawdza scenariusz: ReconcileStoredSyncStateDisablesSyncWhenHealthUnavailable.
    /// Dlaczego: Zapewnia poprawna obsluge uprawnien i integracji z systemem.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testReconcileStoredSyncStateDisablesSyncWhenHealthUnavailable() async {
        let store = MockHealthStore()
        store.healthDataAvailable = false
        let manager = HealthKitManager(store: store)
        UserDefaults.standard.set(true, forKey: "isSyncEnabled")
        defer { UserDefaults.standard.removeObject(forKey: "isSyncEnabled") }

        let result = manager.reconcileStoredSyncState()

        XCTAssertEqual(result, .notAvailable)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "isSyncEnabled"))
    }

    /// Co sprawdza: Sprawdza scenariusz: ReconcileStoredSyncStateDisablesSyncWhenNoAuthorizedTypes.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testReconcileStoredSyncStateDisablesSyncWhenNoAuthorizedTypes() async {
        let store = MockHealthStore()
        let manager = HealthKitManager(store: store)
        UserDefaults.standard.set(true, forKey: "isSyncEnabled")
        defer { UserDefaults.standard.removeObject(forKey: "isSyncEnabled") }

        let result = manager.reconcileStoredSyncState()

        XCTAssertEqual(result, .denied)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "isSyncEnabled"))
    }
}
