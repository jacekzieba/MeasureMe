import Foundation
import SwiftData

@MainActor
struct SmartNotificationScheduler {

    let context: ModelContext
    let settings: AppSettingsStore
    let now: Date
    let calendar: Calendar

    init(context: ModelContext, settings: AppSettingsStore, now: Date = AppClock.now, calendar: Calendar = .current) {
        self.context = context
        self.settings = settings
        self.now = now
        self.calendar = calendar
    }

    // MARK: - Candidate

    struct Candidate {
        let kindRaw: String
        let reason: Reason
        let title: String
        let body: String
        let fireDate: Date

        enum Reason: Comparable {
            case missedPattern
            case staleness
        }
    }

    // MARK: - Public API

    func bestCandidate(smartDays: Int, smartTime: Date) -> Candidate? {
        let samples = fetchRecentSamples()
        let activeMetricKinds = Array(Set(samples.map(\.kindRaw)))
        let candidates = computeCandidates(activeMetricKinds: activeMetricKinds, smartDays: smartDays, samples: samples)
        guard !candidates.isEmpty else { return nil }

        // Cooldown: max 1 per 24h
        let lastNotifDate = loadLastNotificationDate()
        if let last = lastNotifDate, now.timeIntervalSince(last) < 86400 {
            return nil
        }

        // Skip if user logged anything today
        let startOfToday = calendar.startOfDay(for: now)
        let lastLogDate = settings.snapshot.notifications.lastLogDate
        if lastLogDate > 0 && Date(timeIntervalSince1970: lastLogDate) >= startOfToday {
            return nil
        }

        // Rotation: prefer different metric than last notified
        let lastNotifiedMetric = settings.string(forKey: AppSettingsKeys.Notifications.smartLastNotifiedMetric)

        let sorted = candidates.sorted { $0.reason < $1.reason }

        // Try to pick one that's different from last notified metric
        if let lastMetric = lastNotifiedMetric, sorted.count > 1 {
            if let different = sorted.first(where: { $0.kindRaw != lastMetric }) {
                return withFireDate(different, smartTime: smartTime)
            }
        }

        guard let best = sorted.first else { return nil }
        return withFireDate(best, smartTime: smartTime)
    }

    func recordNotificationScheduled(candidate: Candidate) {
        settings.set(now.timeIntervalSince1970, forKey: AppSettingsKeys.Notifications.smartLastNotificationDate)
        settings.set(candidate.kindRaw, forKey: AppSettingsKeys.Notifications.smartLastNotifiedMetric)
    }

    // MARK: - Candidate Computation

    func computeCandidates(activeMetricKinds: [String], smartDays: Int, samples: [MetricFrequencyAnalyzer.Sample]? = nil) -> [Candidate] {
        let resolvedSamples = samples ?? fetchRecentSamples()
        let analysis = MetricFrequencyAnalyzer.analyze(samples: resolvedSamples, now: now, calendar: calendar)

        var candidates: [Candidate] = []

        let userName = settings.snapshot.profile.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let namePrefix = userName.isEmpty ? "" : "\(userName), "

        // 1. Pattern-based candidates
        let todayWeekday = calendar.component(.weekday, from: now)
        let currentHour = calendar.component(.hour, from: now)

        for pattern in analysis.patterns {
            guard activeMetricKinds.contains(pattern.kindRaw) else { continue }
            guard pattern.dayOfWeek == todayWeekday else { continue }

            // Check if current time is within pattern window (bucket ± 2h after start)
            let bucketEnd = pattern.hourBucketStart + 3
            guard currentHour >= pattern.hourBucketStart && currentHour <= bucketEnd + 2 else { continue }

            // Check user hasn't logged this metric today
            if let lastDate = analysis.lastLogDates[pattern.kindRaw],
               calendar.isDate(lastDate, inSameDayAs: now) {
                continue
            }

            let metricTitle = metricDisplayName(for: pattern.kindRaw)
            let dayName = localizedWeekdayName(pattern.dayOfWeek)

            candidates.append(Candidate(
                kindRaw: pattern.kindRaw,
                reason: .missedPattern,
                title: AppLocalization.string("notification.smart.pattern.title"),
                body: AppLocalization.string("notification.smart.pattern.body", metricTitle, dayName),
                fireDate: now // will be overridden
            ))
        }

        // 2. Staleness-based candidates
        for kindRaw in activeMetricKinds {
            guard let lastDate = analysis.lastLogDates[kindRaw] else { continue }
            let daysSince = Int(ceil(now.timeIntervalSince(lastDate) / 86400.0))

            let avgInterval = analysis.averageIntervals[kindRaw]
            let avgDays = avgInterval.map { Int(ceil($0 / 86400.0)) }

            // Threshold: max(avgInterval * 1.5, smartDays)
            let threshold: Int
            if let avg = avgDays {
                threshold = max(Int(ceil(Double(avg) * 1.5)), smartDays)
            } else {
                continue // not enough data for staleness
            }

            guard daysSince > threshold else { continue }

            // Don't add if already a pattern candidate for this metric
            if candidates.contains(where: { $0.kindRaw == kindRaw }) { continue }

            let metricTitle = metricDisplayName(for: kindRaw)

            candidates.append(Candidate(
                kindRaw: kindRaw,
                reason: .staleness,
                title: AppLocalization.string("notification.smart.stale.title"),
                body: AppLocalization.string("notification.smart.stale.body", metricTitle, daysSince),
                fireDate: now // will be overridden
            ))
        }

        return candidates
    }

    // MARK: - Private Helpers

    private func fetchRecentSamples() -> [MetricFrequencyAnalyzer.Sample] {
        let windowStart = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        var descriptor = FetchDescriptor<MetricSample>(
            predicate: #Predicate { $0.date >= windowStart }
        )
        descriptor.sortBy = [SortDescriptor(\.date)]

        guard let results = try? context.fetch(descriptor) else { return [] }
        return results.map { MetricFrequencyAnalyzer.Sample(kindRaw: $0.kindRaw, date: $0.date) }
    }

    private func loadLastNotificationDate() -> Date? {
        let ts = settings.double(forKey: AppSettingsKeys.Notifications.smartLastNotificationDate)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    private func withFireDate(_ candidate: Candidate, smartTime: Date) -> Candidate {
        let timeComponents = calendar.dateComponents([.hour, .minute], from: smartTime)
        var todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        todayComponents.hour = timeComponents.hour
        todayComponents.minute = timeComponents.minute
        let todayTarget = calendar.date(from: todayComponents) ?? now

        let fireDate: Date
        if todayTarget > now {
            fireDate = todayTarget
        } else {
            fireDate = calendar.date(byAdding: .day, value: 1, to: todayTarget) ?? todayTarget
        }

        return Candidate(
            kindRaw: candidate.kindRaw,
            reason: candidate.reason,
            title: candidate.title,
            body: candidate.body,
            fireDate: fireDate
        )
    }

    private func metricDisplayName(for kindRaw: String) -> String {
        if let kind = MetricKind(rawValue: kindRaw) {
            return kind.title
        }
        // Custom metric — try to find its definition
        var descriptor = FetchDescriptor<CustomMetricDefinition>(
            predicate: #Predicate { $0.identifier == kindRaw }
        )
        descriptor.fetchLimit = 1
        if let custom = try? context.fetch(descriptor).first {
            return custom.name
        }
        return kindRaw
    }

    private func localizedWeekdayName(_ weekday: Int) -> String {
        let symbols = calendar.weekdaySymbols
        let index = (weekday - 1) % 7
        return symbols[index]
    }
}
