/// Cel testow: Pilnuje, ze kazdy kontener otwierajacy baze na dysku uzywa pelnego, wersjonowanego schematu.
/// Dlaczego to wazne: Otwarcie bazy schematem bez jednej z encji kasuje jej dane (tak Skroty kasowaly
///   definicje wlasnych metryk), a brak wersji schematu zamyka droge do bezpiecznych migracji.
/// Kryteria zaliczenia: Baza zapisana dotychczasowym, niewersjonowanym schematem otwiera sie przez fabryke
///   bez utraty zadnych danych.

import XCTest
import SwiftData
@testable import MeasureMe

@MainActor
final class MeasureMeSchemaTests: XCTestCase {
    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeasureMeSchemaTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("default.store")
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
    }

    /// Every store on a device today was written without a versioned schema. Adopting one must open
    /// those stores as they are.
    func testStoreWrittenBeforeVersioningOpensWithAllData() throws {
        let unversioned = Schema([MetricSample.self, MetricGoal.self, PhotoEntry.self, CustomMetricDefinition.self])
        do {
            let container = try ModelContainer(
                for: unversioned,
                configurations: [ModelConfiguration(schema: unversioned, url: storeURL, cloudKitDatabase: .none)]
            )
            let context = ModelContext(container)
            context.insert(MetricSample(kind: .weight, value: 80, date: Date(timeIntervalSince1970: 1_700_000_000)))
            context.insert(MetricGoal(kind: .weight, targetValue: 75, direction: .decrease))
            context.insert(PhotoEntry(imageData: Data([1, 2, 3]), tags: []))
            context.insert(CustomMetricDefinition(name: "Wrist", unitLabel: "cm"))
            try context.save()
        }

        let context = ModelContext(try MeasureMeModelContainer.makePersistent(url: storeURL))

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricSample>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricGoal>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PhotoEntry>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CustomMetricDefinition>()), 1)
    }

    /// The Shortcuts container listed three of the four models; opening the store with it deleted every
    /// custom metric definition.
    func testSchemaHoldsEveryModelInTheStore() {
        let entityNames = Set(MeasureMeModelContainer.schema.entities.map(\.name))

        XCTAssertEqual(entityNames, ["MetricSample", "MetricGoal", "PhotoEntry", "CustomMetricDefinition"])
    }

    func testReopeningKeepsCustomMetricDefinitions() throws {
        do {
            let context = ModelContext(try MeasureMeModelContainer.makePersistent(url: storeURL))
            context.insert(CustomMetricDefinition(name: "Wrist", unitLabel: "cm"))
            try context.save()
        }

        let context = ModelContext(try MeasureMeModelContainer.makePersistent(url: storeURL))

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CustomMetricDefinition>()), 1)
    }
}
