import XCTest
import SwiftData
@testable import MeasureMe

@MainActor
final class WidgetPayloadCompatibilityTests: XCTestCase {
    private struct DecodedWidgetPayload: Decodable {
        struct SampleDTO: Decodable {
            let value: Double
            let date: Date
        }

        struct GoalDTO: Decodable {
            let targetValue: Double
            let startValue: Double?
            let direction: String
        }

        let kind: String
        let samples: [SampleDTO]
        let goal: GoalDTO?
        let unitsSystem: String
    }

    private var container: ModelContainer!
    private var context: ModelContext!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let schema = Schema([MetricSample.self, MetricGoal.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)

        suiteName = "WidgetPayloadCompatibilityTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create UserDefaults suite")
            return
        }
        self.defaults = defaults

        WidgetDataWriter.resetTestHooks()
        WidgetDataWriter.setTestHooks(
            defaultsProvider: { [weak self] _ in self?.defaults },
            reloadHandler: { _ in }
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

    func testWriterPayloadDecodesWithWidgetSchema() throws {
        let sampleDate = Date(timeIntervalSince1970: floor(AppClock.now.timeIntervalSince1970))
        context.insert(MetricSample(kind: .weight, value: 82.4, date: sampleDate))
        context.insert(MetricGoal(kind: .weight, targetValue: 79.0, direction: .decrease, startValue: 85.0, startDate: sampleDate))
        try context.save()

        WidgetDataWriter.writeAndReload(kinds: [.weight], context: context, unitsSystem: "metric")
        WidgetDataWriter.flushPendingWrites()

        guard let data = defaults.data(forKey: "widget_data_weight") else {
            XCTFail("Missing widget payload for weight")
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let payload = try decoder.decode(DecodedWidgetPayload.self, from: data)

        XCTAssertEqual(payload.kind, MetricKind.weight.rawValue)
        XCTAssertEqual(payload.unitsSystem, "metric")
        XCTAssertEqual(payload.samples.count, 1)
        XCTAssertEqual(payload.samples.first?.value, 82.4)
        XCTAssertEqual(payload.samples.first?.date, sampleDate)
        XCTAssertEqual(payload.goal?.targetValue, 79.0)
        XCTAssertEqual(payload.goal?.startValue, 85.0)
        XCTAssertEqual(payload.goal?.direction, MetricGoal.Direction.decrease.rawValue)
    }
}
