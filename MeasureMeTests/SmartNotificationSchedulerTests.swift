import XCTest
import SwiftData
@testable import MeasureMe

@MainActor
final class SmartNotificationSchedulerTests: XCTestCase {

    private var defaults: UserDefaults!
    private var settings: AppSettingsStore!
    private var container: ModelContainer!
    private var context: ModelContext!
    private let calendar = Calendar(identifier: .gregorian)

    // MARK: - Setup

    override func setUpWithError() throws {
        let suiteName = "SmartNotificationSchedulerTests.\(name)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        settings = AppSettingsStore(defaults: defaults)

        let schema = Schema([MetricSample.self, CustomMetricDefinition.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "SmartNotificationSchedulerTests.\(name)")
        settings = nil
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: string)!
    }

    private func insertSample(kind: MetricKind, date: Date, value: Double = 70.0) {
        let sample = MetricSample(kind: kind, value: value, date: date)
        context.insert(sample)
        try? context.save()
    }

    private func makeScheduler(now: Date) -> SmartNotificationScheduler {
        SmartNotificationScheduler(
            context: context,
            settings: settings,
            now: now,
            calendar: calendar
        )
    }

    private func smartTime(hour: Int, minute: Int = 0) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        return calendar.date(from: comps) ?? Date()
    }

    // MARK: - computeCandidates: Staleness

    func testStalenessCandidate_WhenMetricExceedsThreshold() {
        // 3 samples 7 days apart, last one 20 days ago
        // avgInterval = 7 days, threshold = max(7*1.5, 5) = 11 days
        // daysSince = 20 > 11 → staleness candidate
        let now = date("2026-03-20 12:00")
        insertSample(kind: .weight, date: date("2026-02-07 10:00"))
        insertSample(kind: .weight, date: date("2026-02-14 10:00"))
        insertSample(kind: .weight, date: date("2026-02-28 10:00"))

        let scheduler = makeScheduler(now: now)
        let candidates = scheduler.computeCandidates(
            activeMetricKinds: ["weight"],
            smartDays: 5
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.kindRaw, "weight")
        XCTAssertEqual(candidates.first?.reason, .staleness)
    }

    func testStalenessCandidate_NotTriggeredWhenWithinThreshold() {
        // 3 samples 7 days apart, last one 5 days ago
        // avgInterval = 7 days, threshold = 11 days
        // daysSince = 5 < 11 → no candidate
        let now = date("2026-03-05 12:00")
        insertSample(kind: .weight, date: date("2026-02-14 10:00"))
        insertSample(kind: .weight, date: date("2026-02-21 10:00"))
        insertSample(kind: .weight, date: date("2026-02-28 10:00"))

        let scheduler = makeScheduler(now: now)
        let candidates = scheduler.computeCandidates(
            activeMetricKinds: ["weight"],
            smartDays: 5
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func testStalenessCandidate_RespectsSmartDaysMinimum() {
        // 3 samples 2 days apart, last 4 days ago
        // avgInterval = 2 days, threshold = max(2*1.5, 14) = 14 (smartDays dominates)
        // daysSince = 4 < 14 → no candidate
        let now = date("2026-03-10 12:00")
        insertSample(kind: .weight, date: date("2026-03-02 10:00"))
        insertSample(kind: .weight, date: date("2026-03-04 10:00"))
        insertSample(kind: .weight, date: date("2026-03-06 10:00"))

        let scheduler = makeScheduler(now: now)
        let candidates = scheduler.computeCandidates(
            activeMetricKinds: ["weight"],
            smartDays: 14
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func testStalenessCandidate_SkipsMetricWithTooFewSamples() {
        // Only 2 samples → no avgInterval → no staleness
        let now = date("2026-03-20 12:00")
        insertSample(kind: .weight, date: date("2026-01-01 10:00"))
        insertSample(kind: .weight, date: date("2026-01-08 10:00"))

        let scheduler = makeScheduler(now: now)
        let candidates = scheduler.computeCandidates(
            activeMetricKinds: ["weight"],
            smartDays: 5
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func testStalenessCandidate_MultipleMetrics() {
        let now = date("2026-03-20 12:00")
        // Weight: stale (last 18 days ago, avg 5 days → threshold 8)
        insertSample(kind: .weight, date: date("2026-02-15 10:00"))
        insertSample(kind: .weight, date: date("2026-02-20 10:00"))
        insertSample(kind: .weight, date: date("2026-03-02 10:00"))
        // Waist: not stale (last 3 days ago)
        insertSample(kind: .waist, date: date("2026-03-07 10:00"))
        insertSample(kind: .waist, date: date("2026-03-12 10:00"))
        insertSample(kind: .waist, date: date("2026-03-17 10:00"))

        let scheduler = makeScheduler(now: now)
        let candidates = scheduler.computeCandidates(
            activeMetricKinds: ["weight", "waist"],
            smartDays: 5
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.kindRaw, "weight")
    }

    // MARK: - computeCandidates: Pattern Detection

    func testPatternCandidate_MatchesDayOfWeek() {
        // Create pattern: weight on Saturdays at 10AM
        // 2026-01-03 is a Saturday (weekday 7 in Gregorian)
        let saturdaySamples: [(String, String)] = [
            ("weight", "2026-01-03 10:00"),
            ("weight", "2026-01-10 10:00"),
            ("weight", "2026-01-17 10:00"),
            ("weight", "2026-01-24 10:00"),
        ]
        for (kind, dateStr) in saturdaySamples {
            insertSample(kind: MetricKind(rawValue: kind)!, date: date(dateStr))
        }

        // Now is a Saturday at 11AM → should match
        let now = date("2026-03-21 11:00") // Saturday
        let scheduler = makeScheduler(now: now)
        let candidates = scheduler.computeCandidates(
            activeMetricKinds: ["weight"],
            smartDays: 5
        )

        let patternCandidates = candidates.filter { $0.reason == .missedPattern }
        XCTAssertEqual(patternCandidates.count, 1)
        XCTAssertEqual(patternCandidates.first?.kindRaw, "weight")
    }

    func testPatternCandidate_DoesNotMatchWrongDay() {
        // Pattern: weight on Saturdays
        let saturdaySamples: [(MetricKind, String)] = [
            (.weight, "2026-01-03 10:00"),
            (.weight, "2026-01-10 10:00"),
            (.weight, "2026-01-17 10:00"),
            (.weight, "2026-01-24 10:00"),
        ]
        for (kind, dateStr) in saturdaySamples {
            insertSample(kind: kind, date: date(dateStr))
        }

        // Now is a Wednesday → should not match
        let now = date("2026-03-18 10:00") // Wednesday
        let scheduler = makeScheduler(now: now)
        let candidates = scheduler.computeCandidates(
            activeMetricKinds: ["weight"],
            smartDays: 5
        )

        let patternCandidates = candidates.filter { $0.reason == .missedPattern }
        XCTAssertTrue(patternCandidates.isEmpty)
    }

    func testPatternCandidate_SkipsIfAlreadyLoggedToday() {
        // Pattern: weight on Saturdays at 10AM
        for week in 0..<4 {
            let d = date("2026-01-03 10:00").addingTimeInterval(Double(week * 7) * 86400)
            insertSample(kind: .weight, date: d)
        }
        // User already logged weight today (Saturday)
        insertSample(kind: .weight, date: date("2026-03-21 08:00"))

        let now = date("2026-03-21 11:00") // Saturday
        let scheduler = makeScheduler(now: now)
        let candidates = scheduler.computeCandidates(
            activeMetricKinds: ["weight"],
            smartDays: 5
        )

        let patternCandidates = candidates.filter { $0.reason == .missedPattern }
        XCTAssertTrue(patternCandidates.isEmpty)
    }

    func testPatternCandidate_OutsideTimeWindow_NoCandidate() {
        // Pattern: weight on Saturdays at 10AM (bucket 9-12)
        for week in 0..<4 {
            let d = date("2026-01-03 10:00").addingTimeInterval(Double(week * 7) * 86400)
            insertSample(kind: .weight, date: d)
        }

        // Now is Saturday but at 20:00 → outside 9-14 window
        let now = date("2026-03-21 20:00")
        let scheduler = makeScheduler(now: now)
        let candidates = scheduler.computeCandidates(
            activeMetricKinds: ["weight"],
            smartDays: 5
        )

        let patternCandidates = candidates.filter { $0.reason == .missedPattern }
        XCTAssertTrue(patternCandidates.isEmpty)
    }

    // MARK: - bestCandidate: Priority

    func testPatternCandidateHasHigherPriorityThanStaleness() {
        // Both pattern and staleness candidates exist
        // Pattern for weight on Saturday, staleness for waist
        for week in 0..<4 {
            let d = date("2026-01-03 10:00").addingTimeInterval(Double(week * 7) * 86400)
            insertSample(kind: .weight, date: d)
        }
        insertSample(kind: .waist, date: date("2026-01-01 10:00"))
        insertSample(kind: .waist, date: date("2026-01-08 10:00"))
        insertSample(kind: .waist, date: date("2026-01-15 10:00"))

        // Saturday 11AM, both should be candidates
        let now = date("2026-03-21 11:00")
        let scheduler = makeScheduler(now: now)
        let candidates = scheduler.computeCandidates(
            activeMetricKinds: ["weight", "waist"],
            smartDays: 5
        )

        let sorted = candidates.sorted { $0.reason < $1.reason }
        XCTAssertEqual(sorted.first?.reason, .missedPattern)
    }

    // MARK: - bestCandidate: Cooldown

    func testCooldown_ReturnsNilIfNotificationSentWithin24h() {
        insertSample(kind: .weight, date: date("2026-01-01 10:00"))
        insertSample(kind: .weight, date: date("2026-01-08 10:00"))
        insertSample(kind: .weight, date: date("2026-01-15 10:00"))

        let now = date("2026-03-20 12:00")
        // Last notification sent 12h ago
        settings.set(
            now.addingTimeInterval(-12 * 3600).timeIntervalSince1970,
            forKey: AppSettingsKeys.Notifications.smartLastNotificationDate
        )

        let scheduler = makeScheduler(now: now)
        let result = scheduler.bestCandidate(smartDays: 5, smartTime: smartTime(hour: 7))

        XCTAssertNil(result)
    }

    func testCooldown_ReturnsCandidateIfOver24h() {
        insertSample(kind: .weight, date: date("2026-01-01 10:00"))
        insertSample(kind: .weight, date: date("2026-01-08 10:00"))
        insertSample(kind: .weight, date: date("2026-01-15 10:00"))

        let now = date("2026-03-20 12:00")
        // Last notification 48h ago
        settings.set(
            now.addingTimeInterval(-48 * 3600).timeIntervalSince1970,
            forKey: AppSettingsKeys.Notifications.smartLastNotificationDate
        )

        let scheduler = makeScheduler(now: now)
        let result = scheduler.bestCandidate(smartDays: 5, smartTime: smartTime(hour: 18))

        XCTAssertNotNil(result)
    }

    // MARK: - bestCandidate: Skip If Logged Today

    func testSkipsIfUserLoggedToday() {
        insertSample(kind: .weight, date: date("2026-01-01 10:00"))
        insertSample(kind: .weight, date: date("2026-01-08 10:00"))
        insertSample(kind: .weight, date: date("2026-01-15 10:00"))

        let now = date("2026-03-20 12:00")
        // lastLogDate is today
        settings.set(\.notifications.lastLogDate, now.addingTimeInterval(-3600).timeIntervalSince1970)

        let scheduler = makeScheduler(now: now)
        let result = scheduler.bestCandidate(smartDays: 5, smartTime: smartTime(hour: 18))

        XCTAssertNil(result)
    }

    func testDoesNotSkipIfUserLoggedYesterday() {
        insertSample(kind: .weight, date: date("2026-01-01 10:00"))
        insertSample(kind: .weight, date: date("2026-01-08 10:00"))
        insertSample(kind: .weight, date: date("2026-01-15 10:00"))

        let now = date("2026-03-20 12:00")
        // lastLogDate is yesterday
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        settings.set(\.notifications.lastLogDate, yesterday.timeIntervalSince1970)

        let scheduler = makeScheduler(now: now)
        let result = scheduler.bestCandidate(smartDays: 5, smartTime: smartTime(hour: 18))

        XCTAssertNotNil(result)
    }

    // MARK: - bestCandidate: Rotation

    func testRotation_PrefersDifferentMetricThanLast() {
        // Two stale metrics
        insertSample(kind: .weight, date: date("2026-01-01 10:00"))
        insertSample(kind: .weight, date: date("2026-01-08 10:00"))
        insertSample(kind: .weight, date: date("2026-01-15 10:00"))
        insertSample(kind: .waist, date: date("2026-01-01 10:00"))
        insertSample(kind: .waist, date: date("2026-01-08 10:00"))
        insertSample(kind: .waist, date: date("2026-01-15 10:00"))

        let now = date("2026-03-20 12:00")
        // Last notified about weight
        settings.set("weight", forKey: AppSettingsKeys.Notifications.smartLastNotifiedMetric)

        let scheduler = makeScheduler(now: now)
        let result = scheduler.bestCandidate(smartDays: 5, smartTime: smartTime(hour: 18))

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.kindRaw, "waist")
    }

    func testRotation_FallsBackToSameMetricIfOnlyOne() {
        insertSample(kind: .weight, date: date("2026-01-01 10:00"))
        insertSample(kind: .weight, date: date("2026-01-08 10:00"))
        insertSample(kind: .weight, date: date("2026-01-15 10:00"))

        let now = date("2026-03-20 12:00")
        settings.set("weight", forKey: AppSettingsKeys.Notifications.smartLastNotifiedMetric)

        let scheduler = makeScheduler(now: now)
        let result = scheduler.bestCandidate(smartDays: 5, smartTime: smartTime(hour: 18))

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.kindRaw, "weight")
    }

    // MARK: - bestCandidate: Fire Date

    func testFireDate_UsesSmartTimeIfInFuture() {
        insertSample(kind: .weight, date: date("2026-01-01 10:00"))
        insertSample(kind: .weight, date: date("2026-01-08 10:00"))
        insertSample(kind: .weight, date: date("2026-01-15 10:00"))

        // Now is 06:00, smartTime is 09:00 → fire today at 09:00
        let now = date("2026-03-20 06:00")
        let scheduler = makeScheduler(now: now)
        let result = scheduler.bestCandidate(smartDays: 5, smartTime: smartTime(hour: 9))

        XCTAssertNotNil(result)
        let fireComponents = calendar.dateComponents([.hour], from: result!.fireDate)
        XCTAssertEqual(fireComponents.hour, 9)
    }

    func testFireDate_ShiftsToTomorrowIfSmartTimePassed() {
        insertSample(kind: .weight, date: date("2026-01-01 10:00"))
        insertSample(kind: .weight, date: date("2026-01-08 10:00"))
        insertSample(kind: .weight, date: date("2026-01-15 10:00"))

        // Now is 15:00, smartTime is 09:00 → fire tomorrow at 09:00
        let now = date("2026-03-20 15:00")
        let scheduler = makeScheduler(now: now)
        let result = scheduler.bestCandidate(smartDays: 5, smartTime: smartTime(hour: 9))

        XCTAssertNotNil(result)
        let nowDay = calendar.component(.day, from: now)
        let fireDay = calendar.component(.day, from: result!.fireDate)
        XCTAssertEqual(fireDay, nowDay + 1)
    }

    // MARK: - bestCandidate: Explicit Parameters

    func testBestCandidate_RespectsExplicitLastNotificationDate() {
        insertSample(kind: .weight, date: date("2026-01-01 10:00"))
        insertSample(kind: .weight, date: date("2026-01-08 10:00"))
        insertSample(kind: .weight, date: date("2026-01-15 10:00"))

        let now = date("2026-03-20 12:00")
        let scheduler = makeScheduler(now: now)

        // Passing explicit cooldown date within 24h → nil
        let result = scheduler.bestCandidate(
            smartDays: 5,
            smartTime: smartTime(hour: 18),
            lastNotificationDate: now.addingTimeInterval(-12 * 3600)
        )
        XCTAssertNil(result)
    }

    func testBestCandidate_RespectsExplicitLastNotifiedMetric() {
        // Two stale metrics
        insertSample(kind: .weight, date: date("2026-01-01 10:00"))
        insertSample(kind: .weight, date: date("2026-01-08 10:00"))
        insertSample(kind: .weight, date: date("2026-01-15 10:00"))
        insertSample(kind: .waist, date: date("2026-01-01 10:00"))
        insertSample(kind: .waist, date: date("2026-01-08 10:00"))
        insertSample(kind: .waist, date: date("2026-01-15 10:00"))

        let now = date("2026-03-20 12:00")
        let scheduler = makeScheduler(now: now)

        // Passing explicit last notified metric → rotation picks the other
        let result = scheduler.bestCandidate(
            smartDays: 5,
            smartTime: smartTime(hour: 18),
            lastNotifiedMetric: "weight"
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.kindRaw, "waist")
    }

    // MARK: - bestCandidate: No Data

    func testNoCandidates_WhenNoSamples() {
        let now = date("2026-03-20 12:00")
        let scheduler = makeScheduler(now: now)
        let result = scheduler.bestCandidate(smartDays: 5, smartTime: smartTime(hour: 7))

        XCTAssertNil(result)
    }

    // MARK: - Edge: Only Inactive Metrics Filtered

    func testOnlyActiveMetricsConsideredForStaleness() {
        insertSample(kind: .weight, date: date("2026-01-01 10:00"))
        insertSample(kind: .weight, date: date("2026-01-08 10:00"))
        insertSample(kind: .weight, date: date("2026-01-15 10:00"))

        let now = date("2026-03-20 12:00")
        let scheduler = makeScheduler(now: now)

        // Compute with empty active list → no candidates
        let candidates = scheduler.computeCandidates(
            activeMetricKinds: [],
            smartDays: 5
        )
        XCTAssertTrue(candidates.isEmpty)
    }
}
