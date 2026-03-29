import XCTest
import SwiftData
@testable import MeasureMe

@MainActor
final class AINotificationEngineTests: XCTestCase {
    private var defaults: UserDefaults!
    private var settings: AppSettingsStore!
    private var container: ModelContainer!
    private var context: ModelContext!
    private var previousLocalizationSettings: AppSettingsStore?
    private let calendar = Calendar(identifier: .gregorian)

    override func setUpWithError() throws {
        let suiteName = "AINotificationEngineTests.\(name)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        settings = AppSettingsStore(defaults: defaults)
        settings.set(\.experience.appLanguage, AppLanguage.en.rawValue)
        settings.set(\.notifications.aiConsistencyEnabled, false)
        settings.set(\.notifications.aiDigestWeekday, 4)
        settings.set(\.notifications.aiDigestTime, date("2026-03-25 19:30").timeIntervalSince1970)

        previousLocalizationSettings = AppLocalization.settings
        AppLocalization.settings = settings
        AppLocalization.reloadLanguage()

        let schema = Schema([MetricSample.self, MetricGoal.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        AppLocalization.settings = previousLocalizationSettings ?? .shared
        AppLocalization.reloadLanguage()
        defaults.removePersistentDomain(forName: "AINotificationEngineTests.\(name)")
        defaults = nil
        settings = nil
        container = nil
        context = nil
        previousLocalizationSettings = nil
        super.tearDown()
    }

    func testWeeklyDigestCandidateUsesRecentSamplesAndHealthImports() throws {
        let now = date("2026-03-25 09:00")
        insertSample(kind: .weight, value: 75.0, date: date("2026-03-20 08:00"), source: .manual)
        insertSample(kind: .weight, value: 74.2, date: date("2026-03-24 08:00"), source: .healthKit)

        let builder = makeBuilder(trigger: .startup, now: now)
        let candidate = try XCTUnwrap(builder.candidates().first { $0.kind == .weeklyDigest })

        XCTAssertEqual(candidate.metricKindRaw, MetricKind.weight.rawValue)
        XCTAssertEqual(candidate.deepLink, .home)
        XCTAssertEqual(candidate.priority, .passive)
        XCTAssertEqual(candidate.fireDate, date("2026-03-25 19:30"))
        XCTAssertTrue(candidate.facts.contains(where: { $0.contains("Recent check-ins this week: 2") }))
        XCTAssertTrue(candidate.facts.contains(where: { $0.contains("Health imports this week: 1") }))
    }

    func testTrendShiftCandidateBuildsActiveMetricDetailNotification() throws {
        let now = date("2026-03-29 10:00")
        insertSample(kind: .weight, value: 80.0, date: date("2026-03-01 08:00"))
        insertSample(kind: .weight, value: 79.0, date: date("2026-03-23 08:00"))
        insertSample(kind: .weight, value: 81.0, date: date("2026-03-29 08:00"))

        let builder = makeBuilder(trigger: .manualLog(kinds: [.weight]), now: now)
        let candidate = try XCTUnwrap(builder.candidates().first { $0.kind == .trendShift })

        XCTAssertEqual(candidate.metricKindRaw, MetricKind.weight.rawValue)
        XCTAssertEqual(candidate.deepLink, .metricDetail(kindRaw: MetricKind.weight.rawValue))
        XCTAssertEqual(candidate.priority, .active)
        XCTAssertTrue(candidate.facts.contains(where: { $0.contains("Type: trend shift") }))
    }

    func testGoalMilestoneCandidateDetectsThresholdCrossing() throws {
        let now = date("2026-03-29 10:00")
        insertGoal(
            kind: .weight,
            targetValue: 80.0,
            direction: .decrease,
            createdDate: date("2026-03-01 08:00"),
            startValue: 100.0,
            startDate: date("2026-03-01 08:00")
        )
        insertSample(kind: .weight, value: 95.0, date: date("2026-03-20 08:00"))
        insertSample(kind: .weight, value: 90.0, date: date("2026-03-29 08:00"))

        let builder = makeBuilder(trigger: .manualLog(kinds: [.weight]), now: now)
        let candidate = try XCTUnwrap(builder.candidates().first { $0.kind == .goalMilestone })

        XCTAssertEqual(candidate.metricKindRaw, MetricKind.weight.rawValue)
        XCTAssertEqual(candidate.priority, .passive)
        XCTAssertTrue(candidate.facts.contains(where: { $0.contains("Goal progress reached: 50%") }))
    }

    func testRoundNumberCandidateDetectsMeaningfulMilestone() throws {
        let now = date("2026-03-29 10:00")
        insertSample(kind: .weight, value: 79.3, date: date("2026-03-28 08:00"))
        insertSample(kind: .weight, value: 80.0, date: date("2026-03-29 08:00"))

        let builder = makeBuilder(trigger: .manualLog(kinds: [.weight]), now: now)
        let candidate = try XCTUnwrap(builder.candidates().first { $0.kind == .roundNumber })

        XCTAssertEqual(candidate.metricKindRaw, MetricKind.weight.rawValue)
        XCTAssertEqual(candidate.deepLink, .metricDetail(kindRaw: MetricKind.weight.rawValue))
        XCTAssertTrue(candidate.facts.contains(where: { $0.contains("Rounded milestone hit: 80") }))
    }

    func testCandidatesAreBlockedWhenDailyCapAlreadyReached() {
        let now = date("2026-03-29 10:00")
        setLastSentTimestamps(["weeklyDigest": now.timeIntervalSince1970])
        insertSample(kind: .weight, value: 75.0, date: date("2026-03-20 08:00"))
        insertSample(kind: .weight, value: 74.2, date: date("2026-03-24 08:00"))

        let builder = makeBuilder(trigger: .startup, now: now)

        XCTAssertTrue(builder.candidates().isEmpty)
    }

    func testMutedKindsAreFilteredOut() {
        let now = date("2026-03-29 10:00")
        setMutedKinds([.roundNumber])
        insertSample(kind: .weight, value: 79.3, date: date("2026-03-28 08:00"))
        insertSample(kind: .weight, value: 80.0, date: date("2026-03-29 08:00"))

        let builder = makeBuilder(trigger: .manualLog(kinds: [.weight]), now: now)

        XCTAssertFalse(builder.candidates().contains(where: { $0.kind == .roundNumber }))
    }

    func testOutputValidatorRejectsInventedNumbers() {
        let candidate = sampleCandidate(facts: [
            "Current value: 80 kg",
            "Goal progress reached: 50%"
        ])
        let output = AINotificationGeneratedOutput(
            shouldSend: true,
            title: "50% reached",
            body: "You are now at 52% of the goal.",
            tone: "calm",
            priority: "active",
            reason: "milestone"
        )

        XCTAssertNil(AINotificationOutputValidator.validate(output: output, candidate: candidate))
    }

    func testOutputValidatorRejectsMedicalLanguage() {
        let candidate = sampleCandidate(facts: [
            "Current value: 80 kg",
            "Goal progress reached: 50%"
        ])
        let output = AINotificationGeneratedOutput(
            shouldSend: true,
            title: "50% reached",
            body: "This could help diagnose a disease trend.",
            tone: "calm",
            priority: "passive",
            reason: "milestone"
        )

        XCTAssertNil(AINotificationOutputValidator.validate(output: output, candidate: candidate))
    }

    func testOutputValidatorAcceptsFactBoundedCopy() throws {
        let candidate = sampleCandidate(facts: [
            "Current value: 80 kg",
            "Goal progress reached: 50%"
        ], priority: .passive)
        let output = AINotificationGeneratedOutput(
            shouldSend: true,
            title: "50% reached",
            body: "Current value is 80 kg. Goal progress reached 50%.",
            tone: "calm",
            priority: "active",
            reason: "milestone"
        )

        let decision = try XCTUnwrap(AINotificationOutputValidator.validate(output: output, candidate: candidate))
        XCTAssertEqual(decision.priority, .active)
        XCTAssertEqual(decision.title, "50% reached")
    }

    private func makeBuilder(trigger: AINotificationTrigger, now: Date) -> AINotificationCandidateBuilder {
        AINotificationCandidateBuilder(
            context: context,
            settings: settings,
            trigger: trigger,
            now: now,
            calendar: calendar,
            aiAvailable: true
        )
    }

    private func setLastSentTimestamps(_ timestamps: [String: TimeInterval]) {
        let data = try! JSONEncoder().encode(timestamps)
        settings.set(\.notifications.aiLastSentTimestamps, data)
    }

    private func setMutedKinds(_ kinds: [AINotificationKind]) {
        let data = try! JSONEncoder().encode(kinds.map(\.rawValue))
        settings.set(\.notifications.aiMutedTypes, data)
    }

    private func insertSample(kind: MetricKind, value: Double, date: Date, source: MetricSampleSource = .manual) {
        context.insert(MetricSample(kind: kind, value: value, date: date, source: source))
        try? context.save()
    }

    private func insertGoal(
        kind: MetricKind,
        targetValue: Double,
        direction: MetricGoal.Direction,
        createdDate: Date,
        startValue: Double?,
        startDate: Date?
    ) {
        context.insert(
            MetricGoal(
                kind: kind,
                targetValue: targetValue,
                direction: direction,
                createdDate: createdDate,
                startValue: startValue,
                startDate: startDate
            )
        )
        try? context.save()
    }

    private func sampleCandidate(
        facts: [String],
        priority: AINotificationPriority = .passive
    ) -> AINotificationCandidate {
        AINotificationCandidate(
            kind: .goalMilestone,
            metricKindRaw: MetricKind.weight.rawValue,
            facts: facts,
            score: 1.0,
            confidence: 1.0,
            fireDate: Date(timeIntervalSince1970: 1_700_000_000),
            deepLink: .metricDetail(kindRaw: MetricKind.weight.rawValue),
            priority: priority,
            dedupeKeys: []
        )
    }

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: string)!
    }
}
