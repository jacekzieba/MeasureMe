import XCTest
import SwiftData
@testable import MeasureMe

@MainActor
final class WidgetSharedPayloadTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var suiteName: String!
    private var appGroupDefaults: UserDefaults!
    private var standardDefaults: UserDefaults { .standard }

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([MetricSample.self, MetricGoal.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)

        suiteName = "WidgetSharedPayloadTests.\(UUID().uuidString)"
        appGroupDefaults = UserDefaults(suiteName: suiteName)
        WidgetDataWriter.resetTestHooks()
        WidgetDataWriter.setTestHooks(
            defaultsProvider: { [weak self] _ in self?.appGroupDefaults },
            reloadHandler: { _ in }
        )
    }

    override func tearDownWithError() throws {
        WidgetDataWriter.resetTestHooks()
        if let suiteName {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        standardDefaults.removeObject(forKey: AppSettingsKeys.Premium.entitlement)
        standardDefaults.removeObject(forKey: "streak_current_count")
        standardDefaults.removeObject(forKey: "streak_max_count")
        standardDefaults.removeObject(forKey: "streak_active_weeks")
        appGroupDefaults = nil
        suiteName = nil
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    func testWriteAndReload_WritesPremiumAndStreakPayload() throws {
        let currentWeek = AppClock.now.isoWeekIdentifier(calendar: Calendar(identifier: .iso8601))
        let activeWeeksData = try JSONEncoder().encode([currentWeek])
        standardDefaults.set(true, forKey: AppSettingsKeys.Premium.entitlement)
        standardDefaults.set(5, forKey: "streak_current_count")
        standardDefaults.set(11, forKey: "streak_max_count")
        standardDefaults.set(activeWeeksData, forKey: "streak_active_weeks")

        context.insert(MetricSample(kind: .weight, value: 81.3, date: AppClock.now))
        try context.save()

        WidgetDataWriter.writeAndReload(kinds: [.weight], context: context, unitsSystem: "metric")
        WidgetDataWriter.flushPendingWrites()

        XCTAssertEqual(appGroupDefaults.bool(forKey: "widget_premium_enabled"), true)
        guard let streakData = appGroupDefaults.data(forKey: "widget_streak_payload") else {
            XCTFail("Missing streak payload")
            return
        }
        let streakPayload = try JSONDecoder().decode(StreakPayloadDTO.self, from: streakData)
        XCTAssertEqual(streakPayload.currentStreak, 5)
        XCTAssertEqual(streakPayload.maxStreak, 11)
        XCTAssertEqual(streakPayload.loggedToday, true)
    }
}

private struct StreakPayloadDTO: Decodable {
    let currentStreak: Int
    let maxStreak: Int
    let loggedToday: Bool
}
