import XCTest
import HealthKit
import SwiftData
@testable import MeasureMe

private final class MappingHealthStoreMock: HealthStore {
    var healthDataAvailable = true
    var latestByIdentifier: [HKQuantityTypeIdentifier: (value: Double, date: Date)] = [:]
    var latestQuantityError: Error?
    var saveQuantityError: Error?
    var saveWaistError: Error?
    var waistMeasurements: [(value: Double, date: Date)] = []

    private(set) var savedQuantities: [(value: Double, identifier: HKQuantityTypeIdentifier, date: Date)] = []
    private(set) var savedWaistMeasurements: [(value: Double, date: Date)] = []
    private(set) var deletedWaistMeasurementDates: [Date] = []

    func isHealthDataAvailable() -> Bool { healthDataAvailable }

    func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws {}

    func authorizationStatus(for identifier: HKQuantityTypeIdentifier) throws -> HKAuthorizationStatus {
        .sharingAuthorized
    }

    func latestQuantity(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> (value: Double, date: Date)? {
        if let latestQuantityError {
            throw latestQuantityError
        }
        return latestByIdentifier[identifier]
    }

    func anchoredQuantitySamples(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        anchorData: Data?,
        since: Date?
    ) async throws -> (samples: [(value: Double, date: Date, sourceBundleID: String?)], newAnchorData: Data?) {
        ([], nil)
    }

    func saveQuantity(_ value: Double, unit: HKUnit, identifier: HKQuantityTypeIdentifier, date: Date) async throws {
        if let saveQuantityError {
            throw saveQuantityError
        }
        savedQuantities.append((value: value, identifier: identifier, date: date))
    }

    func fetchWaistMeasurements() async throws -> [(value: Double, date: Date)] { waistMeasurements }

    func saveWaistMeasurement(value: Double, date: Date) async throws {
        if let saveWaistError {
            throw saveWaistError
        }
        savedWaistMeasurements.append((value: value, date: date))
    }

    func deleteWaistMeasurements(inDay date: Date) async throws {
        deletedWaistMeasurementDates.append(date)
    }
}

@MainActor
final class HealthKitManagerImportMappingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var settings: AppSettingsStore!
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let suiteName = "HealthKitManagerImportMappingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        settings = AppSettingsStore(defaults: defaults)

        let schema = Schema([MetricSample.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        defaults = nil
        settings = nil
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    func testFetchLatestBodyFatPercentage_MapsFromFractionToPercent() async throws {
        let store = MappingHealthStoreMock()
        let date = Date(timeIntervalSince1970: 1_736_400_000)
        store.latestByIdentifier[.bodyFatPercentage] = (value: 0.187, date: date)
        let manager = HealthKitManager(store: store, settings: settings)

        let result = try await manager.fetchLatestBodyFatPercentage()

        guard let result else {
            return XCTFail("Expected body fat result")
        }
        XCTAssertEqual(result.value, 18.7, accuracy: 0.0001)
        XCTAssertEqual(result.date, date)
    }

    func testSaveBodyFatPercentage_MapsFromPercentToFraction() async throws {
        let store = MappingHealthStoreMock()
        let date = Date(timeIntervalSince1970: 1_736_400_100)
        let manager = HealthKitManager(store: store, settings: settings)

        try await manager.saveBodyFatPercentage(percent: 23.5, date: date)

        XCTAssertEqual(store.savedQuantities.count, 1)
        guard let saved = store.savedQuantities.first else {
            return XCTFail("Expected a saved quantity")
        }
        XCTAssertEqual(saved.identifier, .bodyFatPercentage)
        XCTAssertEqual(saved.value, 0.235, accuracy: 0.0001)
        XCTAssertEqual(saved.date, date)
    }

    func testImportHeightFromHealthKit_CreatesSingleHeightMetricSampleAndDeduplicatesByDate() async throws {
        let store = MappingHealthStoreMock()
        let date = Date(timeIntervalSince1970: 1_736_401_000)
        store.latestByIdentifier[.height] = (value: 180.2, date: date)
        let manager = HealthKitManager(store: store, settings: settings)

        try await manager.importHeightFromHealthKit(to: context)
        try await manager.importHeightFromHealthKit(to: context)

        let descriptor = FetchDescriptor<MetricSample>(
            predicate: #Predicate { sample in
                sample.kindRaw == "height"
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 1)
        guard let first = fetched.first else {
            return XCTFail("Expected one fetched sample")
        }
        XCTAssertEqual(first.kindRaw, MetricKind.height.rawValue)
        XCTAssertEqual(first.value, 180.2, accuracy: 0.0001)
        XCTAssertEqual(first.date, date)
    }

    func testImportHeightFromHealthKit_NoDataIsNoOp() async throws {
        let store = MappingHealthStoreMock()
        let manager = HealthKitManager(store: store, settings: settings)

        try await manager.importHeightFromHealthKit(to: context)

        let descriptor = FetchDescriptor<MetricSample>(
            predicate: #Predicate { sample in
                sample.kindRaw == "height"
            }
        )
        let fetched = try context.fetch(descriptor)
        XCTAssertTrue(fetched.isEmpty)
    }

    func testImportHeightFromHealthKit_PropagatesProviderError() async {
        struct ProviderError: Error {}

        let store = MappingHealthStoreMock()
        store.latestQuantityError = ProviderError()
        let manager = HealthKitManager(store: store, settings: settings)

        do {
            try await manager.importHeightFromHealthKit(to: context)
            XCTFail("Expected provider error")
        } catch {
            XCTAssertTrue(error is ProviderError)
        }
    }

    func testFetchLatestBodyComposition_AllowsPartialHealthKitData() async throws {
        let store = MappingHealthStoreMock()
        let date = Date(timeIntervalSince1970: 1_736_402_000)
        store.latestByIdentifier[.bodyFatPercentage] = (value: 0.187, date: date)
        let manager = HealthKitManager(store: store, settings: settings)

        let result = try await manager.fetchLatestBodyCompositionCached(forceRefresh: true)

        XCTAssertEqual(try XCTUnwrap(result.bodyFat), 18.7, accuracy: 0.0001)
        XCTAssertNil(result.leanMass)
    }

    func testSyncPersistsSupportedKindsWithExpectedHealthKitIdentifiers() async throws {
        let store = MappingHealthStoreMock()
        let date = Date(timeIntervalSince1970: 1_736_403_000)
        let manager = HealthKitManager(store: store, settings: settings)

        try await manager.sync(kind: .weight, metricValue: 82.0, date: date)
        try await manager.sync(kind: .height, metricValue: 180.0, date: date)
        try await manager.sync(kind: .bodyFat, metricValue: 18.5, date: date)
        try await manager.sync(kind: .leanBodyMass, metricValue: 63.0, date: date)
        try await manager.sync(kind: .waist, metricValue: 84.0, date: date)
        try await manager.sync(kind: .neck, metricValue: 39.0, date: date)

        XCTAssertEqual(store.savedQuantities.map(\.identifier), [.bodyMass, .height, .bodyFatPercentage, .leanBodyMass])
        let savedValues = store.savedQuantities.map(\.value)
        XCTAssertEqual(savedValues.count, 4)
        XCTAssertEqual(savedValues[0], 82.0, accuracy: 0.0001)
        XCTAssertEqual(savedValues[1], 180.0, accuracy: 0.0001)
        XCTAssertEqual(savedValues[2], 0.185, accuracy: 0.0001)
        XCTAssertEqual(savedValues[3], 63.0, accuracy: 0.0001)
        XCTAssertEqual(store.savedWaistMeasurements.count, 1)
        XCTAssertEqual(store.savedWaistMeasurements.first?.value, 84.0)
        XCTAssertEqual(store.savedWaistMeasurements.first?.date, date)
    }

    func testSyncPropagatesProviderError() async {
        struct ProviderError: Error {}

        let store = MappingHealthStoreMock()
        store.saveQuantityError = ProviderError()
        let manager = HealthKitManager(store: store, settings: settings)

        do {
            try await manager.sync(kind: .weight, metricValue: 82.0, date: Date())
            XCTFail("Expected provider error")
        } catch {
            XCTAssertTrue(error is ProviderError)
        }
    }

    func testUserFacingSyncErrorMessageMapsAuthorizationAndUnknownErrors() {
        XCTAssertEqual(
            HealthKitManager.userFacingSyncErrorMessage(for: HealthKitAuthorizationError.notAvailable),
            HealthKitAuthorizationError.notAvailable.errorDescription
        )
        XCTAssertEqual(
            HealthKitManager.userFacingSyncErrorMessage(for: HealthKitAuthorizationError.denied),
            HealthKitAuthorizationError.denied.errorDescription
        )

        let storeError = NSError(domain: "HealthStore", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Store failed"
        ])
        XCTAssertEqual(
            HealthKitManager.userFacingSyncErrorMessage(for: storeError),
            "Could not enable Health sync. Please try again."
        )
    }
}
