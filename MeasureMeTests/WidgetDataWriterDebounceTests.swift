import XCTest
import SwiftData
@testable import MeasureMe

@MainActor
final class WidgetDataWriterDebounceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var reloadCount = 0

    override func setUpWithError() throws {
        try super.setUpWithError()

        let schema = Schema([MetricSample.self, MetricGoal.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)

        suiteName = "WidgetDataWriterDebounceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create UserDefaults suite")
            return
        }
        self.defaults = defaults
        reloadCount = 0

        WidgetDataWriter.resetTestHooks()
        WidgetDataWriter.setTestHooks(
            defaultsProvider: { [weak self] _ in self?.defaults },
            reloadHandler: { [weak self] _ in self?.reloadCount += 1 }
        )
    }

    override func tearDownWithError() throws {
        WidgetDataWriter.resetTestHooks()
        if let suiteName {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    func testWriteAndReload_CoalescesMultipleCallsIntoSingleReload() throws {
        context.insert(MetricSample(kind: .weight, value: 80.0, date: Date(timeIntervalSince1970: 1_736_100_000)))
        context.insert(MetricSample(kind: .waist, value: 90.0, date: Date(timeIntervalSince1970: 1_736_100_100)))
        try context.save()

        WidgetDataWriter.writeAndReload(kinds: [.weight], context: context, unitsSystem: "metric")
        WidgetDataWriter.writeAndReload(kinds: [.waist], context: context, unitsSystem: "metric")
        WidgetDataWriter.flushPendingWrites()

        XCTAssertEqual(reloadCount, 1)
        XCTAssertNotNil(defaults.data(forKey: "widget_data_weight"))
        XCTAssertNotNil(defaults.data(forKey: "widget_data_waist"))
    }

    func testFlushPendingWrites_WritesImmediately() throws {
        context.insert(MetricSample(kind: .weight, value: 79.4, date: Date(timeIntervalSince1970: 1_736_110_000)))
        try context.save()

        WidgetDataWriter.writeAndReload(kinds: [.weight], context: context, unitsSystem: "metric")
        WidgetDataWriter.flushPendingWrites()

        XCTAssertEqual(reloadCount, 1)
        XCTAssertNotNil(defaults.data(forKey: "widget_data_weight"))
    }

    func testWriteAllAndReload_BypassesDebounceAndFlushesPending() throws {
        context.insert(MetricSample(kind: .weight, value: 81.2, date: Date(timeIntervalSince1970: 1_736_120_000)))
        try context.save()

        WidgetDataWriter.writeAndReload(kinds: [.weight], context: context, unitsSystem: "metric")
        WidgetDataWriter.writeAllAndReload(context: context, unitsSystem: "imperial")

        XCTAssertEqual(reloadCount, 2)
        XCTAssertNotNil(defaults.data(forKey: "widget_data_weight"))
        XCTAssertNotNil(defaults.data(forKey: "widget_data_bodyFat"))
        XCTAssertEqual(unitsSystem(forKey: "widget_data_weight"), "imperial")
    }
}

private extension WidgetDataWriterDebounceTests {
    func unitsSystem(forKey key: String) -> String? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let payload = object as? [String: Any]
        else {
            return nil
        }
        return payload["unitsSystem"] as? String
    }
}
