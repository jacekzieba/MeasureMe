import Combine
import Foundation
import SwiftData

// MARK: - ISO Week Helpers

extension Date {
    /// Returns an ISO 8601 week identifier like `"2026-W09"`.
    func isoWeekIdentifier(calendar: Calendar = Calendar(identifier: .iso8601)) -> String {
        let year = calendar.component(.yearForWeekOfYear, from: self)
        let week = calendar.component(.weekOfYear, from: self)
        return String(format: "%04d-W%02d", year, week)
    }
}

// MARK: - StreakManager

/// Tracks consecutive weeks of user activity (metric saves, photo saves, HealthKit imports).
///
/// Storage lives in UserDefaults (streak is derived metadata, not first-class data).
/// Designed with future vacation-mode support in mind (``vacationWeeks`` are skipped
/// transparently by the streak algorithm).
@MainActor
final class StreakManager: ObservableObject {

    static let shared = StreakManager(clock: { AppClock.now })

    // MARK: - Published State

    @Published private(set) var currentStreak: Int = 0
    @Published private(set) var shouldPlayAnimation: Bool = false

    // MARK: - Dependencies

    private let defaults: UserDefaults
    private let clock: () -> Date
    private let calendar: Calendar

    // MARK: - Keys

    private enum Keys {
        static let activeWeeks = "streak_active_weeks"
        static let currentCount = "streak_current_count"
        static let animationPlayedWeek = "streak_animation_played_week"
        static let appOpenedWeeks = "streak_app_opened_weeks"
        static let vacationWeeks = "streak_vacation_weeks"
    }

    // MARK: - Init

    init(
        defaults: UserDefaults = .standard,
        clock: @escaping () -> Date = { Date() },
        calendar: Calendar = Calendar(identifier: .iso8601)
    ) {
        self.defaults = defaults
        self.clock = clock
        self.calendar = calendar
        self.currentStreak = defaults.integer(forKey: Keys.currentCount)
    }

    // MARK: - Public API

    /// Called when the user opens the app (from HomeView.onAppear).
    /// Records the app-open week, retroactively credits HealthKit for the
    /// current week, recomputes the streak, and determines whether the
    /// celebration animation should play.
    func recordAppOpen(context: ModelContext) {
        let now = clock()
        let currentWeek = now.isoWeekIdentifier(calendar: calendar)

        // 1. Record this week as "app opened"
        var openedWeeks = loadWeekSet(forKey: Keys.appOpenedWeeks)
        openedWeeks.insert(currentWeek)
        saveWeekSet(openedWeeks, forKey: Keys.appOpenedWeeks)

        // 2. Retroactively credit HealthKit samples for the current week
        retroactivelyCreditCurrentWeek(currentWeek, context: context)

        // 3. Recompute
        let previousStreak = currentStreak
        recomputeStreak()

        // 4. Animation: play once per week when streak > 0
        let animationPlayedWeek = defaults.string(forKey: Keys.animationPlayedWeek)
        if currentStreak > 0 && animationPlayedWeek != currentWeek && currentStreak >= previousStreak {
            shouldPlayAnimation = true
        }
    }

    /// Called after the celebration animation finishes.
    func markAnimationPlayed() {
        let currentWeek = clock().isoWeekIdentifier(calendar: calendar)
        defaults.set(currentWeek, forKey: Keys.animationPlayedWeek)
        shouldPlayAnimation = false
    }

    /// Records that a metric was manually saved.
    func recordMetricSaved(date: Date) {
        let week = date.isoWeekIdentifier(calendar: calendar)
        addActiveWeek(week)
        recomputeStreak()
    }

    /// Records that a photo was saved.
    func recordPhotoSaved(date: Date) {
        let week = date.isoWeekIdentifier(calendar: calendar)
        addActiveWeek(week)
        recomputeStreak()
    }

    /// Records HealthKit-imported samples. Only credits weeks where the
    /// user also opened the app.
    func recordHealthKitImport(sampleDates: [Date]) {
        let openedWeeks = loadWeekSet(forKey: Keys.appOpenedWeeks)
        var activeWeeks = loadWeekSet(forKey: Keys.activeWeeks)
        var changed = false

        for date in sampleDates {
            let week = date.isoWeekIdentifier(calendar: calendar)
            if openedWeeks.contains(week) && !activeWeeks.contains(week) {
                activeWeeks.insert(week)
                changed = true
            }
        }

        if changed {
            pruneOldWeeks(&activeWeeks)
            saveWeekSet(activeWeeks, forKey: Keys.activeWeeks)
            recomputeStreak()
        }
    }

    // MARK: - Streak Algorithm (pure, static for testability)

    /// Computes the consecutive-week streak ending at or before `now`.
    ///
    /// - If the current week is active, it counts and we walk backwards.
    /// - If the current week is NOT active, we start from the previous week
    ///   (grace period: the user has until Sunday to maintain the streak).
    /// - Vacation weeks are skipped transparently (neither break nor extend).
    static func computeStreak(
        activeWeeks: Set<String>,
        now: Date,
        vacationWeeks: Set<String>,
        calendar: Calendar = Calendar(identifier: .iso8601)
    ) -> Int {
        let currentWeek = now.isoWeekIdentifier(calendar: calendar)
        var streak = 0
        var weekToCheck: String

        if activeWeeks.contains(currentWeek) {
            streak = 1
            weekToCheck = previousISOWeek(currentWeek, calendar: calendar)
        } else {
            weekToCheck = previousISOWeek(currentWeek, calendar: calendar)
        }

        var iterations = 0
        let maxIterations = 520 // ~10 years safety cap

        while iterations < maxIterations {
            iterations += 1
            if vacationWeeks.contains(weekToCheck) {
                weekToCheck = previousISOWeek(weekToCheck, calendar: calendar)
                continue
            }
            if activeWeeks.contains(weekToCheck) {
                streak += 1
                weekToCheck = previousISOWeek(weekToCheck, calendar: calendar)
            } else {
                break
            }
        }

        return streak
    }

    /// Returns the ISO week identifier for the week before `weekID`.
    static func previousISOWeek(_ weekID: String, calendar: Calendar = Calendar(identifier: .iso8601)) -> String {
        guard let monday = mondayOfWeek(weekID, calendar: calendar) else { return "" }
        let previousMonday = calendar.date(byAdding: .day, value: -7, to: monday)!
        return previousMonday.isoWeekIdentifier(calendar: calendar)
    }

    // MARK: - Private Helpers

    private func addActiveWeek(_ week: String) {
        var weeks = loadWeekSet(forKey: Keys.activeWeeks)
        guard !weeks.contains(week) else { return }
        weeks.insert(week)
        pruneOldWeeks(&weeks)
        saveWeekSet(weeks, forKey: Keys.activeWeeks)
    }

    private func recomputeStreak() {
        let activeWeeks = loadWeekSet(forKey: Keys.activeWeeks)
        let vacationWeeks = loadWeekSet(forKey: Keys.vacationWeeks)
        let now = clock()
        let computed = Self.computeStreak(
            activeWeeks: activeWeeks,
            now: now,
            vacationWeeks: vacationWeeks,
            calendar: calendar
        )
        currentStreak = computed
        defaults.set(computed, forKey: Keys.currentCount)
    }

    /// Checks SwiftData for any MetricSample or PhotoEntry in the given
    /// ISO week. If data exists, marks the week as active. This handles
    /// the case where HealthKit imported data in the background before the
    /// user opened the app this week.
    private func retroactivelyCreditCurrentWeek(_ week: String, context: ModelContext) {
        guard let (start, end) = Self.dateRange(forWeek: week, calendar: calendar) else { return }

        let activeWeeks = loadWeekSet(forKey: Keys.activeWeeks)
        guard !activeWeeks.contains(week) else { return }

        var sampleDescriptor = FetchDescriptor<MetricSample>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        sampleDescriptor.fetchLimit = 1

        let hasSamples = (try? context.fetchCount(sampleDescriptor)) ?? 0 > 0

        if hasSamples {
            addActiveWeek(week)
            return
        }

        var photoDescriptor = FetchDescriptor<PhotoEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        photoDescriptor.fetchLimit = 1

        let hasPhotos = (try? context.fetchCount(photoDescriptor)) ?? 0 > 0

        if hasPhotos {
            addActiveWeek(week)
        }
    }

    // MARK: - Date Parsing

    /// Returns the Monday 00:00 UTC for the given ISO week identifier.
    static func mondayOfWeek(_ weekID: String, calendar: Calendar = Calendar(identifier: .iso8601)) -> Date? {
        // Parse "YYYY-Www"
        guard weekID.count == 8,
              let year = Int(weekID.prefix(4)),
              weekID[weekID.index(weekID.startIndex, offsetBy: 5)] == "W",
              let week = Int(weekID.suffix(2)) else {
            return nil
        }

        var components = DateComponents()
        components.yearForWeekOfYear = year
        components.weekOfYear = week
        components.weekday = 2 // Monday in ISO calendar
        return calendar.date(from: components)
    }

    /// Returns the (start, end) date range for a given ISO week: [Monday 00:00, next Monday 00:00).
    static func dateRange(forWeek weekID: String, calendar: Calendar = Calendar(identifier: .iso8601)) -> (start: Date, end: Date)? {
        guard let monday = mondayOfWeek(weekID, calendar: calendar) else { return nil }
        let start = calendar.startOfDay(for: monday)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
        return (start, end)
    }

    // MARK: - UserDefaults Persistence

    private func loadWeekSet(forKey key: String) -> Set<String> {
        guard let data = defaults.data(forKey: key),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(array)
    }

    private func saveWeekSet(_ set: Set<String>, forKey key: String) {
        let sorted = set.sorted()
        if let data = try? JSONEncoder().encode(sorted) {
            defaults.set(data, forKey: key)
        }
    }

    private func pruneOldWeeks(_ weeks: inout Set<String>) {
        guard weeks.count > 104 else { return }
        let sorted = weeks.sorted()
        weeks = Set(sorted.suffix(104))
    }
}
