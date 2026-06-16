import XCTest
@testable import MeasureMe

private final class OnboardingHealthKitMock: OnboardingHealthKitAuthorizing {
    func prepareAuthorizationRequest() async {
        // No-op for onboarding tests.
    }
    
    func fetchDateOfBirth() throws -> Date? {
        nil
    }
    
    func fetchLatestHeightInCentimeters() async throws -> (value: Double, date: Date)? {
        nil
    }
    
    private(set) var requestAuthorizationCallCount = 0

    func requestAuthorization() async throws {
        requestAuthorizationCallCount += 1
    }
}

private final class OnboardingNotificationManagerMock: OnboardingNotificationManaging {
    var notificationsEnabled: Bool = false
    var smartEnabled: Bool = false
    var smartTime: Date = .distantPast
    var requestAuthorizationResult: Bool = false
    var reminders: [MeasurementReminder] = []
    private(set) var scheduledBatches: [[MeasurementReminder]] = []

    func requestAuthorization() async -> Bool {
        requestAuthorizationResult
    }

    func loadReminders() -> [MeasurementReminder] {
        reminders
    }

    func saveReminders(_ reminders: [MeasurementReminder]) {
        self.reminders = reminders
    }

    func scheduleAllReminders(_ reminders: [MeasurementReminder]) {
        scheduledBatches.append(reminders)
    }
}

@MainActor
final class OnboardingEffectsTests: XCTestCase {
    private func makeDefaults(suffix: String = UUID().uuidString) -> UserDefaults {
        let suite = "OnboardingEffectsTests.\(suffix)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testReminderSeedUsesExistingWeeklyReminderAndScheduledState() {
        let notifications = OnboardingNotificationManagerMock()
        notifications.notificationsEnabled = true
        notifications.smartEnabled = false
        notifications.reminders = [
            MeasurementReminder(
                id: "weekly",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                repeatRule: .weekly
            )
        ]
        let effects = OnboardingEffects(
            healthKit: OnboardingHealthKitMock(),
            notifications: notifications,
            settings: AppSettingsStore(defaults: makeDefaults())
        )

        let seed = effects.loadReminderSeed(defaultWeeklyReminderDate: .distantPast)

        XCTAssertEqual(seed.repeatRule, .weekly)
        XCTAssertEqual(seed.reminderTime.timeIntervalSince1970, 1_700_000_000, accuracy: 0.01)
        XCTAssertTrue(seed.isReminderScheduled)
    }

    func testUpsertReminderUpdatesExistingRuleAndSchedulesBatch() {
        let notifications = OnboardingNotificationManagerMock()
        notifications.notificationsEnabled = true
        notifications.reminders = [
            MeasurementReminder(
                id: "daily-id",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                repeatRule: .daily
            )
        ]
        let effects = OnboardingEffects(
            healthKit: OnboardingHealthKitMock(),
            notifications: notifications,
            settings: AppSettingsStore(defaults: makeDefaults())
        )
        let newDate = Date(timeIntervalSince1970: 1_710_000_000)

        effects.upsertReminder(date: newDate, repeatRule: .daily)

        XCTAssertEqual(notifications.reminders.count, 1)
        XCTAssertEqual(notifications.reminders[0].id, "daily-id")
        XCTAssertEqual(notifications.reminders[0].date.timeIntervalSince1970, newDate.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(notifications.scheduledBatches.count, 1)
        XCTAssertEqual(notifications.scheduledBatches[0].count, 1)
    }

    func testGoalStatUsesInjectedSettings() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)
        let effects = OnboardingEffects(
            healthKit: OnboardingHealthKitMock(),
            notifications: OnboardingNotificationManagerMock(),
            settings: store
        )

        effects.incrementWelcomeGoalSelectionStat(goalRawValue: "loseWeight")
        effects.incrementWelcomeGoalSelectionStat(goalRawValue: "loseWeight")

        XCTAssertEqual(store.integer(forKey: "onboarding_goal_selection_stat_loseWeight"), 2)
    }

    func testApplyMetricPackMarksAllBuildMuscleMetricsAsHomeKeyMetrics() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)
        let effects = OnboardingEffects(
            healthKit: OnboardingHealthKitMock(),
            notifications: OnboardingNotificationManagerMock(),
            settings: store
        )

        effects.applyMetricPack(GoalMetricPack.trackedKinds(for: .buildMuscle))

        XCTAssertEqual(
            store.stringArray(forKey: "home_key_metrics"),
            ["weight", "bodyFat", "chest", "leftBicep", "rightBicep"]
        )
    }
}
