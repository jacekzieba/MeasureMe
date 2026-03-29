import XCTest
import SwiftData
@testable import MeasureMe

// MARK: - ISO Week Identifier Tests

final class ISOWeekIdentifierTests: XCTestCase {
    private let cal = Calendar(identifier: .iso8601)

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: string)!
    }

    func testMidYearDate() {
        XCTAssertEqual(date("2026-02-26").isoWeekIdentifier(calendar: cal), "2026-W09")
    }

    func testMondayOfWeek() {
        XCTAssertEqual(date("2026-02-23").isoWeekIdentifier(calendar: cal), "2026-W09")
    }

    func testSundayOfWeek() {
        XCTAssertEqual(date("2026-03-01").isoWeekIdentifier(calendar: cal), "2026-W09")
    }

    func testYearBoundary_Jan1BelongsToW01() {
        XCTAssertEqual(date("2026-01-01").isoWeekIdentifier(calendar: cal), "2026-W01")
    }

    func testYearBoundary_Dec31BelongsToPreviousYearWeek() {
        XCTAssertEqual(date("2025-12-29").isoWeekIdentifier(calendar: cal), "2026-W01")
    }

    func testYearBoundary_Dec28BelongsToW52() {
        XCTAssertEqual(date("2025-12-28").isoWeekIdentifier(calendar: cal), "2025-W52")
    }
}

// MARK: - Previous ISO Week Tests

@MainActor
final class PreviousISOWeekTests: XCTestCase {
    private let cal = Calendar(identifier: .iso8601)

    func testMidYear() {
        XCTAssertEqual(StreakManager.previousISOWeek("2026-W09", calendar: cal), "2026-W08")
    }

    func testFirstWeekOfYear() {
        XCTAssertEqual(StreakManager.previousISOWeek("2026-W01", calendar: cal), "2025-W52")
    }

    func testWeekAfterYearBoundary() {
        XCTAssertEqual(StreakManager.previousISOWeek("2026-W02", calendar: cal), "2026-W01")
    }

    func testInvalidInput() {
        XCTAssertEqual(StreakManager.previousISOWeek("invalid", calendar: cal), "")
    }
}

// MARK: - Monday Of Week Tests

@MainActor
final class MondayOfWeekTests: XCTestCase {
    private let cal = Calendar(identifier: .iso8601)

    func testReturnsMonday() {
        guard let monday = StreakManager.mondayOfWeek("2026-W09", calendar: cal) else {
            XCTFail("Expected a date")
            return
        }
        let weekday = cal.component(.weekday, from: monday)
        XCTAssertEqual(weekday, 2, "Expected Monday (weekday 2)")
    }

    func testRoundTrip() {
        let weekID = "2026-W09"
        guard let monday = StreakManager.mondayOfWeek(weekID, calendar: cal) else {
            XCTFail("Expected a date")
            return
        }
        XCTAssertEqual(monday.isoWeekIdentifier(calendar: cal), weekID)
    }

    func testInvalidInput() {
        XCTAssertNil(StreakManager.mondayOfWeek("bad", calendar: cal))
    }
}

// MARK: - Compute Streak Tests (pure algorithm)

@MainActor
final class ComputeStreakTests: XCTestCase {
    private let cal = Calendar(identifier: .iso8601)

    private func dateInWeek(_ weekID: String) -> Date {
        StreakManager.mondayOfWeek(weekID, calendar: cal)!
    }

    func testEmptyActiveWeeks_returnsZero() {
        let streak = StreakManager.computeStreak(
            activeWeeks: [],
            now: dateInWeek("2026-W09"),
            vacationWeeks: [],
            calendar: cal
        )
        XCTAssertEqual(streak, 0)
    }

    func testSingleCurrentWeek_returnsOne() {
        let streak = StreakManager.computeStreak(
            activeWeeks: ["2026-W09"],
            now: dateInWeek("2026-W09"),
            vacationWeeks: [],
            calendar: cal
        )
        XCTAssertEqual(streak, 1)
    }

    func testConsecutiveWeeks_returnsCorrectCount() {
        let active: Set<String> = ["2026-W06", "2026-W07", "2026-W08", "2026-W09"]
        let streak = StreakManager.computeStreak(
            activeWeeks: active,
            now: dateInWeek("2026-W09"),
            vacationWeeks: [],
            calendar: cal
        )
        XCTAssertEqual(streak, 4)
    }

    func testGapBreaksStreak() {
        let active: Set<String> = ["2026-W05", "2026-W06", "2026-W08", "2026-W09"]
        let streak = StreakManager.computeStreak(
            activeWeeks: active,
            now: dateInWeek("2026-W09"),
            vacationWeeks: [],
            calendar: cal
        )
        XCTAssertEqual(streak, 2)
    }

    func testCurrentWeekInactive_gracePeriod() {
        let active: Set<String> = ["2026-W07", "2026-W08"]
        let streak = StreakManager.computeStreak(
            activeWeeks: active,
            now: dateInWeek("2026-W09"),
            vacationWeeks: [],
            calendar: cal
        )
        XCTAssertEqual(streak, 2)
    }

    func testCurrentWeekInactive_gapBeforeLastWeek() {
        let active: Set<String> = ["2026-W06", "2026-W08"]
        let streak = StreakManager.computeStreak(
            activeWeeks: active,
            now: dateInWeek("2026-W09"),
            vacationWeeks: [],
            calendar: cal
        )
        XCTAssertEqual(streak, 1)
    }

    func testVacationWeekSkipped() {
        // Active W05, W06, vacation W07, active W08, W09
        // Vacation weeks are transparent: don't break the chain, but don't add to the count.
        let active: Set<String> = ["2026-W05", "2026-W06", "2026-W08", "2026-W09"]
        let vacation: Set<String> = ["2026-W07"]
        let streak = StreakManager.computeStreak(
            activeWeeks: active,
            now: dateInWeek("2026-W09"),
            vacationWeeks: vacation,
            calendar: cal
        )
        XCTAssertEqual(streak, 4) // W09 + W08 + (skip W07) + W06 + W05 = 4 active weeks
    }

    func testVacationOnlyWeeks_returnsZero() {
        let vacation: Set<String> = ["2026-W08", "2026-W07"]
        let streak = StreakManager.computeStreak(
            activeWeeks: [],
            now: dateInWeek("2026-W09"),
            vacationWeeks: vacation,
            calendar: cal
        )
        XCTAssertEqual(streak, 0)
    }

    func testYearBoundaryStreak() {
        let active: Set<String> = ["2025-W51", "2025-W52", "2026-W01", "2026-W02"]
        let streak = StreakManager.computeStreak(
            activeWeeks: active,
            now: dateInWeek("2026-W02"),
            vacationWeeks: [],
            calendar: cal
        )
        XCTAssertEqual(streak, 4)
    }

    func testLongStreak() {
        var active = Set<String>()
        var date = dateInWeek("2026-W09")
        for _ in 0..<52 {
            active.insert(date.isoWeekIdentifier(calendar: cal))
            date = cal.date(byAdding: .day, value: -7, to: date)!
        }
        let streak = StreakManager.computeStreak(
            activeWeeks: active,
            now: dateInWeek("2026-W09"),
            vacationWeeks: [],
            calendar: cal
        )
        XCTAssertEqual(streak, 52)
    }

    func testMultipleVacationWeeksInARow() {
        // Active W04 and W08, vacation W05-W07
        // Vacation bridges the gap: 2 active weeks in an unbroken chain.
        let active: Set<String> = ["2026-W04", "2026-W08"]
        let vacation: Set<String> = ["2026-W05", "2026-W06", "2026-W07"]
        let streak = StreakManager.computeStreak(
            activeWeeks: active,
            now: dateInWeek("2026-W08"),
            vacationWeeks: vacation,
            calendar: cal
        )
        XCTAssertEqual(streak, 2) // W08 + (skip W07,W06,W05) + W04 = 2 active weeks
    }
}

// MARK: - StreakManager Integration Tests

@MainActor
final class StreakManagerIntegrationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var settings: AppSettingsStore!
    private var fixedDate: Date!
    private var manager: StreakManager!
    private let cal = Calendar(identifier: .iso8601)

    override func setUp() {
        super.setUp()
        suiteName = "StreakManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        settings = AppSettingsStore(defaults: defaults)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        fixedDate = formatter.date(from: "2026-02-25 12:00:00")!

        manager = StreakManager(
            defaults: settings,
            clock: { [fixedDate] in fixedDate! },
            calendar: cal
        )
    }

    override func tearDown() {
        manager = nil
        settings = nil
        defaults = nil
        if let suiteName, let cleanupDefaults = UserDefaults(suiteName: suiteName) {
            cleanupDefaults.removePersistentDomain(forName: suiteName)
        }
        suiteName = nil
        super.tearDown()
    }

    private func dateTime(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: string)!
    }

    private func makeEmptyContext() throws -> ModelContext {
        let schema = Schema([MetricSample.self, PhotoEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }

    func testRecordMetricSaved_addsActiveWeek() {
        manager.recordMetricSaved(date: fixedDate)
        XCTAssertEqual(manager.currentStreak, 1)
    }

    func testRecordPhotoSaved_addsActiveWeek() {
        manager.recordPhotoSaved(date: fixedDate)
        XCTAssertEqual(manager.currentStreak, 1)
    }

    func testRecordMetricSaved_previousWeek_extendsStreak() {
        let w08Date = cal.date(byAdding: .day, value: -7, to: fixedDate)!
        manager.recordMetricSaved(date: w08Date)
        manager.recordMetricSaved(date: fixedDate)
        XCTAssertEqual(manager.currentStreak, 2)
    }

    func testRecordHealthKitImport_onlyCreditsWhenAppOpened() {
        manager.recordHealthKitImport(sampleDates: [fixedDate])
        XCTAssertEqual(manager.currentStreak, 0)

        let weekID = fixedDate.isoWeekIdentifier(calendar: cal)
        let data = try! JSONEncoder().encode([weekID])
        settings.set(data, forKey: "streak_app_opened_weeks")

        manager.recordHealthKitImport(sampleDates: [fixedDate])
        XCTAssertEqual(manager.currentStreak, 1)
    }

    func testAnimationCondition_newWeekWithStreak() {
        let w08Date = cal.date(byAdding: .day, value: -7, to: fixedDate)!
        manager.recordMetricSaved(date: w08Date)
        manager.recordMetricSaved(date: fixedDate)

        settings.set("2026-W08", forKey: "streak_animation_played_week")

        let currentWeek = fixedDate.isoWeekIdentifier(calendar: cal)
        let animPlayedWeek = settings.string(forKey: "streak_animation_played_week")
        XCTAssertNotEqual(animPlayedWeek, currentWeek)
        XCTAssertGreaterThan(manager.currentStreak, 0)
    }

    func testMarkAnimationPlayed_preventsReplay() {
        manager.recordMetricSaved(date: fixedDate)

        manager.markAnimationPlayed()

        XCTAssertFalse(manager.shouldPlayAnimation)
        let currentWeek = fixedDate.isoWeekIdentifier(calendar: cal)
        XCTAssertEqual(defaults.string(forKey: "streak_animation_played_week"), currentWeek)
    }

    func testPruning_keepsOnly104Weeks() {
        var date = fixedDate!
        for _ in 0..<150 {
            manager.recordMetricSaved(date: date)
            date = cal.date(byAdding: .day, value: -7, to: date)!
        }

        guard let data = defaults.data(forKey: "streak_active_weeks"),
              let stored = try? JSONDecoder().decode([String].self, from: data) else {
            XCTFail("Expected stored weeks")
            return
        }
        XCTAssertEqual(stored.count, 104)
    }

    func testStreakBrokenWhenGap() {
        let w07Date = cal.date(byAdding: .day, value: -14, to: fixedDate)!
        manager.recordMetricSaved(date: w07Date)
        XCTAssertEqual(manager.currentStreak, 0)
    }

    func testNoActivityReturnsZero() {
        XCTAssertEqual(manager.currentStreak, 0)
    }

    func testStreakPersistsInDefaults() {
        manager.recordMetricSaved(date: fixedDate)
        XCTAssertEqual(defaults.integer(forKey: "streak_current_count"), 1)
    }

    func testStreakResetsAfterMissingWeekWithoutVacationMode() throws {
        var now = dateTime("2026-02-25 12:00:00") // 2026-W09
        let manager = StreakManager(defaults: settings, clock: { now }, calendar: cal)
        let context = try makeEmptyContext()

        manager.recordMetricSaved(date: dateTime("2026-02-18 12:00:00")) // 2026-W08
        XCTAssertEqual(manager.currentStreak, 1)

        now = dateTime("2026-03-04 12:00:00") // 2026-W10, no log in W09
        manager.recordAppOpen(context: context)

        XCTAssertEqual(manager.currentStreak, 0)
    }

    func testVacationModeFreezesStreakWithoutNewValues() throws {
        var now = dateTime("2026-02-25 12:00:00") // 2026-W09
        let manager = StreakManager(defaults: settings, clock: { now }, calendar: cal)
        let context = try makeEmptyContext()

        manager.recordMetricSaved(date: dateTime("2026-02-18 12:00:00")) // 2026-W08
        manager.recordMetricSaved(date: dateTime("2026-02-25 12:00:00")) // 2026-W09
        XCTAssertEqual(manager.currentStreak, 2)

        manager.enableVacationMode(durationWeeks: 3)
        let baseline = manager.currentStreak

        now = dateTime("2026-03-04 12:00:00") // 2026-W10
        manager.recordAppOpen(context: context)
        XCTAssertEqual(manager.currentStreak, baseline)

        now = dateTime("2026-03-11 12:00:00") // 2026-W11
        manager.recordAppOpen(context: context)
        XCTAssertEqual(manager.currentStreak, baseline)
    }
}
