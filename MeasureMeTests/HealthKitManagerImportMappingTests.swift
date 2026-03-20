import XCTest
import HealthKit
import SwiftData
@testable import MeasureMe

private final class MappingHealthStoreMock: HealthStore {
    var healthDataAvailable = true
    var latestByIdentifier: [HKQuantityTypeIdentifier: (value: Double, date: Date)] = [:]

    private(set) var savedQuantities: [(value: Double, identifier: HKQuantityTypeIdentifier, date: Date)] = []

    func isHealthDataAvailable() -> Bool { healthDataAvailable }

    func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws {}

    func authorizationStatus(for identifier: HKQuantityTypeIdentifier) throws -> HKAuthorizationStatus {
        .sharingAuthorized
    }

    func latestQuantity(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> (value: Double, date: Date)? {
        latestByIdentifier[identifier]
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
        savedQuantities.append((value: value, identifier: identifier, date: date))
    }

    func fetchWaistMeasurements() async throws -> [(value: Double, date: Date)] { [] }

    func saveWaistMeasurement(value: Double, date: Date) async throws {}

    func deleteWaistMeasurements(inDay date: Date) async throws {}
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
}
