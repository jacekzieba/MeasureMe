import Foundation
import SwiftData
import UserNotifications
import os.log

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AINotificationKind: String, CaseIterable, Codable, Sendable {
    case weeklyDigest
    case trendShift
    case goalMilestone
    case roundNumber
    case consistencyNudge

    var settingsKeyPath: WritableKeyPath<AppSettingsSnapshot.Notifications, Bool> {
        switch self {
        case .weeklyDigest:
            return \.aiWeeklyDigestEnabled
        case .trendShift:
            return \.aiTrendShiftEnabled
        case .goalMilestone:
            return \.aiGoalMilestonesEnabled
        case .roundNumber:
            return \.aiRoundNumbersEnabled
        case .consistencyNudge:
            return \.aiConsistencyEnabled
        }
    }

    var threadIdentifier: String {
        "ai.\(rawValue)"
    }
}

enum AINotificationPriority: String, Codable, Sendable {
    case passive
    case active

    var interruptionLevel: UNNotificationInterruptionLevel {
        switch self {
        case .passive:
            return .passive
        case .active:
            return .active
        }
    }

    var relevanceScore: Double {
        switch self {
        case .passive:
            return 0.5
        case .active:
            return 0.8
        }
    }
}

enum AINotificationTrigger: Sendable {
    case startup
    case manualLog(kinds: [MetricKind])
    case healthImport(kind: MetricKind)
    case backgroundRefresh
}

struct AINotificationPromptInput: Sendable, Equatable {
    let localeCode: String
    let kind: AINotificationKind
    let metricKindRaw: String?
    let priority: AINotificationPriority
    let facts: [String]
}

struct AINotificationDecision: Sendable, Equatable {
    let shouldSend: Bool
    let title: String
    let body: String
    let priority: AINotificationPriority
    let reason: String
}

struct AINotificationGeneratedOutput: Sendable, Equatable {
    let shouldSend: Bool
    let title: String
    let body: String
    let tone: String
    let priority: String
    let reason: String
}

struct AINotificationCandidate: Sendable, Equatable {
    let kind: AINotificationKind
    let metricKindRaw: String?
    let facts: [String]
    let score: Double
    let confidence: Double
    let fireDate: Date
    let deepLink: AppNavigationRoute
    let priority: AINotificationPriority
    let dedupeKeys: [String]

    var identifier: String {
        let metricSuffix = metricKindRaw.map { ".\($0)" } ?? ""
        let dateSuffix = Int(fireDate.timeIntervalSince1970)
        return "\(AppSettingsKeys.Notifications.aiNotificationPrefix)\(kind.rawValue)\(metricSuffix).\(dateSuffix)"
    }

    var threadIdentifier: String {
        if let metricKindRaw {
            return "\(kind.threadIdentifier).\(metricKindRaw)"
        }
        return kind.threadIdentifier
    }

    var promptInput: AINotificationPromptInput {
        AINotificationPromptInput(
            localeCode: AINotificationLanguage.currentPromptLocaleCode,
            kind: kind,
            metricKindRaw: metricKindRaw,
            priority: priority,
            facts: facts
        )
    }

    var userInfo: [AnyHashable: Any] {
        var userInfo: [AnyHashable: Any] = [
            "aiNotificationKind": kind.rawValue
        ]
        if let metricKindRaw {
            userInfo["aiMetricKindRaw"] = metricKindRaw
        }
        switch deepLink {
        case .home:
            userInfo["aiRoute"] = "home"
        case .metricDetail(let kindRaw):
            userInfo["aiRoute"] = "metricDetail"
            userInfo["aiRouteMetricKindRaw"] = kindRaw
        case .quickAdd(let kindRaw):
            userInfo["aiRoute"] = "quickAdd"
            if let kindRaw {
                userInfo["aiRouteMetricKindRaw"] = kindRaw
            }
        }
        return userInfo
    }
}

enum AINotificationLanguage {
    static var supportedLanguages: Set<AppLanguage> { [.en, .pl, .de, .fr] }

    static var resolvedLanguage: AppLanguage {
        switch AppLocalization.currentLanguage {
        case .system:
            return AppLanguage.resolvedSystemLanguage
        case .en, .pl, .es, .de, .fr, .ptBR:
            return AppLocalization.currentLanguage
        }
    }

    static var isSupported: Bool {
        supportedLanguages.contains(resolvedLanguage)
    }

    static var currentPromptLocaleCode: String {
        switch resolvedLanguage {
        case .pl:
            return "pl"
        case .de:
            return "de"
        case .fr:
            return "fr"
        default:
            return "en"
        }
    }
}

@MainActor
struct AINotificationCandidateBuilder {
    let context: ModelContext
    let settings: AppSettingsStore
    let trigger: AINotificationTrigger
    let now: Date
    let calendar: Calendar
    let aiAvailable: Bool

    init(
        context: ModelContext,
        settings: AppSettingsStore,
        trigger: AINotificationTrigger,
        now: Date = AppClock.now,
        calendar: Calendar = .current,
        aiAvailable: Bool? = nil
    ) {
        self.context = context
        self.settings = settings
        self.trigger = trigger
        self.now = now
        self.calendar = calendar
        self.aiAvailable = aiAvailable ?? AppleIntelligenceSupport.isAvailable()
    }

    func bestCandidate() -> AINotificationCandidate? {
        candidates().sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.fireDate < rhs.fireDate
            }
            return lhs.score > rhs.score
        }.first
    }

    func candidates() -> [AINotificationCandidate] {
        guard settings.snapshot.notifications.aiNotificationsEnabled else { return [] }
        guard aiAvailable else { return [] }
        guard AINotificationLanguage.isSupported else { return [] }

        let sentTimestamps = loadLastSentTimestamps()
        guard !hasReachedCaps(sentTimestamps: sentTimestamps) else { return [] }

        let groupedSamples = fetchGroupedSamples()
        let goalsByKind = fetchGoalsByKind()
        var items: [AINotificationCandidate] = []

        if settings.snapshot.notifications.aiWeeklyDigestEnabled,
           shouldEvaluateWeeklyDigest,
           let candidate = weeklyDigestCandidate(groupedSamples: groupedSamples, sentTimestamps: sentTimestamps) {
            items.append(candidate)
        }

        if settings.snapshot.notifications.aiTrendShiftEnabled {
            items.append(contentsOf: trendShiftCandidates(groupedSamples: groupedSamples, sentTimestamps: sentTimestamps))
        }

        if settings.snapshot.notifications.aiGoalMilestonesEnabled {
            items.append(contentsOf: goalMilestoneCandidates(groupedSamples: groupedSamples, goalsByKind: goalsByKind, sentTimestamps: sentTimestamps))
        }

        if settings.snapshot.notifications.aiRoundNumbersEnabled {
            items.append(contentsOf: roundNumberCandidates(groupedSamples: groupedSamples, sentTimestamps: sentTimestamps))
        }

        if settings.snapshot.notifications.aiConsistencyEnabled,
           shouldEvaluateConsistency,
           let candidate = consistencyCandidate(groupedSamples: groupedSamples, sentTimestamps: sentTimestamps) {
            items.append(candidate)
        }

        return items.filter { candidate in
            !isMuted(candidate.kind) && candidate.confidence >= 0.55 && candidate.score > 0
        }
    }

    private var shouldEvaluateWeeklyDigest: Bool {
        switch trigger {
        case .startup, .backgroundRefresh:
            return true
        case .manualLog, .healthImport:
            return false
        }
    }

    private var shouldEvaluateConsistency: Bool {
        switch trigger {
        case .backgroundRefresh, .startup:
            return true
        case .manualLog, .healthImport:
            return false
        }
    }

    private func fetchGroupedSamples() -> [MetricKind: [MetricSample]] {
        let startDate = calendar.date(byAdding: .day, value: -120, to: now) ?? .distantPast
        let descriptor = FetchDescriptor<MetricSample>(
            predicate: #Predicate { $0.date >= startDate }
        )
        let samples = (try? context.fetch(descriptor)) ?? []
        let grouped = Dictionary(grouping: samples.compactMap { sample -> (MetricKind, MetricSample)? in
            guard let kind = sample.kind else { return nil }
            return (kind, sample)
        }, by: \.0)

        return grouped.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key] = entry.value.map(\.1).sorted { $0.date < $1.date }
        }
    }

    private func fetchGoalsByKind() -> [MetricKind: MetricGoal] {
        let descriptor = FetchDescriptor<MetricGoal>()
        let goals = (try? context.fetch(descriptor)) ?? []
        return goals.reduce(into: [:]) { partialResult, goal in
            guard let kind = goal.kind else { return }
            partialResult[kind] = goal
        }
    }

    private func weeklyDigestCandidate(
        groupedSamples: [MetricKind: [MetricSample]],
        sentTimestamps: [String: TimeInterval]
    ) -> AINotificationCandidate? {
        let key = "weeklyDigest"
        if let lastSent = sentTimestamps[key],
           calendar.isDate(Date(timeIntervalSince1970: lastSent), equalTo: now, toGranularity: .weekOfYear) {
            return nil
        }

        let recentKinds = groupedSamples.compactMap { kind, samples -> (MetricKind, Double, Int)? in
            let recent = samplesInLast(samples, days: 10)
            guard recent.count >= 2 else { return nil }
            let delta30 = delta(samples: samples, days: 30) ?? 0
            return (kind, abs(delta30), recent.count)
        }
        guard let strongest = recentKinds.max(by: { $0.1 < $1.1 }) else { return nil }

        let importedCount = groupedSamples.values
            .flatMap { samplesInLast($0, days: 7) }
            .filter { $0.source == .healthKit }
            .count
        let totalRecentLogs = groupedSamples.values.reduce(0) { $0 + samplesInLast($1, days: 7).count }
        guard totalRecentLogs >= 2 else { return nil }

        let fireDate = nextDigestDate()
        let facts = [
            localeLine(en: "Type: weekly digest", pl: "Typ: podsumowanie tygodnia"),
            localeLine(en: "Recent check-ins this week: \(totalRecentLogs)", pl: "Liczba wpisów w tym tygodniu: \(totalRecentLogs)"),
            localeLine(en: "Health imports this week: \(importedCount)", pl: "Importów ze Zdrowia w tym tygodniu: \(importedCount)"),
            localeLine(
                en: "Strongest tracked movement: \(strongest.0.englishTitle)",
                pl: "Najmocniejszy ruch w danych: \(strongest.0.title)"
            )
        ]

        return AINotificationCandidate(
            kind: .weeklyDigest,
            metricKindRaw: strongest.0.rawValue,
            facts: facts,
            score: 3.4 + strongest.1,
            confidence: 0.7,
            fireDate: fireDate,
            deepLink: .home,
            priority: .passive,
            dedupeKeys: [key]
        )
    }

    private func trendShiftCandidates(
        groupedSamples: [MetricKind: [MetricSample]],
        sentTimestamps: [String: TimeInterval]
    ) -> [AINotificationCandidate] {
        groupedSamples.compactMap { kind, samples in
            guard let delta7 = delta(samples: samples, days: 7),
                  let delta30 = delta(samples: samples, days: 30),
                  samplesInLast(samples, days: 30).count >= 3 else {
                return nil
            }

            let threshold = trendThreshold(for: kind, unitsSystem: settings.snapshot.profile.unitsSystem)
            guard abs(delta7) >= threshold || abs(delta30) >= threshold else { return nil }

            let signChanged = delta7.sign != delta30.sign && delta30 != 0
            let accelerated = abs(delta7) > abs(delta30) * 0.65
            guard signChanged || accelerated else { return nil }

            let key = "trendShift.\(kind.rawValue)"
            if wasSentRecently(key: key, minimumDays: 3, sentTimestamps: sentTimestamps) {
                return nil
            }

            let facts = [
                localeLine(en: "Type: trend shift", pl: "Typ: zmiana trendu"),
                localeLine(en: "Metric: \(kind.englishTitle)", pl: "Metryka: \(kind.title)"),
                localeLine(
                    en: "7 day delta: \(kind.formattedMetricValue(fromMetric: delta7, unitsSystem: settings.snapshot.profile.unitsSystem, includeUnit: true, alwaysShowSign: true))",
                    pl: "Zmiana 7 dni: \(kind.formattedMetricValue(fromMetric: delta7, unitsSystem: settings.snapshot.profile.unitsSystem, includeUnit: true, alwaysShowSign: true))"
                ),
                localeLine(
                    en: "30 day delta: \(kind.formattedMetricValue(fromMetric: delta30, unitsSystem: settings.snapshot.profile.unitsSystem, includeUnit: true, alwaysShowSign: true))",
                    pl: "Zmiana 30 dni: \(kind.formattedMetricValue(fromMetric: delta30, unitsSystem: settings.snapshot.profile.unitsSystem, includeUnit: true, alwaysShowSign: true))"
                ),
                localeLine(
                    en: signChanged ? "Recent direction differs from the longer trend." : "Recent direction is stronger than the longer trend.",
                    pl: signChanged ? "Ostatni kierunek różni się od dłuższego trendu." : "Ostatni kierunek jest mocniejszy niż trend długoterminowy."
                )
            ]

            return AINotificationCandidate(
                kind: .trendShift,
                metricKindRaw: kind.rawValue,
                facts: facts,
                score: 4.8 + abs(delta7) + abs(delta30) * 0.2,
                confidence: signChanged ? 0.82 : 0.74,
                fireDate: now.addingTimeInterval(90),
                deepLink: .metricDetail(kindRaw: kind.rawValue),
                priority: kind == .weight || kind == .waist || kind == .bodyFat ? .active : .passive,
                dedupeKeys: [key]
            )
        }
    }

    private func goalMilestoneCandidates(
        groupedSamples: [MetricKind: [MetricSample]],
        goalsByKind: [MetricKind: MetricGoal],
        sentTimestamps: [String: TimeInterval]
    ) -> [AINotificationCandidate] {
        groupedSamples.compactMap { kind, samples in
            guard let goal = goalsByKind[kind],
                  let latest = samples.last,
                  let baselineValue = goalBaselineValue(for: goal, samples: samples) else {
                return nil
            }

            let previousValue = samples.dropLast().last?.value ?? baselineValue
            let currentProgress = goalProgress(goal: goal, baselineValue: baselineValue, currentValue: latest.value)
            let previousProgress = goalProgress(goal: goal, baselineValue: baselineValue, currentValue: previousValue)
            let milestones = [25, 50, 75, 90, 100]

            guard let crossed = milestones.last(where: {
                previousProgress < Double($0) / 100.0 && currentProgress >= Double($0) / 100.0
            }) else {
                return nil
            }

            let key = "goalMilestone.\(kind.rawValue).\(crossed)"
            if wasSentRecently(key: key, minimumDays: 7, sentTimestamps: sentTimestamps) {
                return nil
            }

            let facts = [
                localeLine(en: "Type: goal milestone", pl: "Typ: kamień milowy celu"),
                localeLine(en: "Metric: \(kind.englishTitle)", pl: "Metryka: \(kind.title)"),
                localeLine(en: "Goal progress reached: \(crossed)%", pl: "Postęp celu osiągnął: \(crossed)%"),
                localeLine(
                    en: "Current value: \(kind.formattedMetricValue(fromMetric: latest.value, unitsSystem: settings.snapshot.profile.unitsSystem))",
                    pl: "Aktualna wartość: \(kind.formattedMetricValue(fromMetric: latest.value, unitsSystem: settings.snapshot.profile.unitsSystem))"
                ),
                localeLine(
                    en: "Goal value: \(kind.formattedMetricValue(fromMetric: goal.targetValue, unitsSystem: settings.snapshot.profile.unitsSystem))",
                    pl: "Wartość celu: \(kind.formattedMetricValue(fromMetric: goal.targetValue, unitsSystem: settings.snapshot.profile.unitsSystem))"
                )
            ]

            return AINotificationCandidate(
                kind: .goalMilestone,
                metricKindRaw: kind.rawValue,
                facts: facts,
                score: crossed >= 90 ? 6.4 : 5.2,
                confidence: 0.88,
                fireDate: now.addingTimeInterval(90),
                deepLink: .metricDetail(kindRaw: kind.rawValue),
                priority: crossed >= 90 ? .active : .passive,
                dedupeKeys: [key]
            )
        }
    }

    private func roundNumberCandidates(
        groupedSamples: [MetricKind: [MetricSample]],
        sentTimestamps: [String: TimeInterval]
    ) -> [AINotificationCandidate] {
        groupedSamples.compactMap { kind, samples in
            guard let latest = samples.last, let previous = samples.dropLast().last else { return nil }
            guard let step = roundNumberStep(for: kind, unitsSystem: settings.snapshot.profile.unitsSystem) else { return nil }

            let latestDisplay = kind.valueForDisplay(fromMetric: latest.value, unitsSystem: settings.snapshot.profile.unitsSystem)
            let previousDisplay = kind.valueForDisplay(fromMetric: previous.value, unitsSystem: settings.snapshot.profile.unitsSystem)
            let rounded = (latestDisplay / step).rounded() * step

            guard abs(latestDisplay - rounded) <= 0.15 else { return nil }
            guard abs(previousDisplay - rounded) > 0.15 else { return nil }

            let roundedText = kind.formattedDisplayValue(rounded, unitsSystem: settings.snapshot.profile.unitsSystem)
            let key = "roundNumber.\(kind.rawValue).\(Int(rounded))"
            if sentTimestamps[key] != nil {
                return nil
            }

            let facts = [
                localeLine(en: "Type: round number", pl: "Typ: okrągła liczba"),
                localeLine(en: "Metric: \(kind.englishTitle)", pl: "Metryka: \(kind.title)"),
                localeLine(en: "Rounded milestone hit: \(roundedText)", pl: "Osiągnięta okrągła wartość: \(roundedText)"),
                localeLine(
                    en: "Previous visible value: \(kind.formattedDisplayValue(previousDisplay, unitsSystem: settings.snapshot.profile.unitsSystem))",
                    pl: "Poprzednia widoczna wartość: \(kind.formattedDisplayValue(previousDisplay, unitsSystem: settings.snapshot.profile.unitsSystem))"
                )
            ]

            return AINotificationCandidate(
                kind: .roundNumber,
                metricKindRaw: kind.rawValue,
                facts: facts,
                score: 4.2,
                confidence: 0.68,
                fireDate: now.addingTimeInterval(120),
                deepLink: .metricDetail(kindRaw: kind.rawValue),
                priority: .passive,
                dedupeKeys: [key]
            )
        }
    }

    private func consistencyCandidate(
        groupedSamples: [MetricKind: [MetricSample]],
        sentTimestamps: [String: TimeInterval]
    ) -> AINotificationCandidate? {
        let scheduler = SmartNotificationScheduler(context: context, settings: settings, now: now, calendar: calendar)
        guard let result = scheduler.bestCandidate(
            smartDays: max(settings.snapshot.notifications.smartDays, 5),
            smartTime: digestOrFallbackTime(),
            lastNotificationDate: lastSentDate(for: "consistencyNudge", sentTimestamps: sentTimestamps),
            lastNotifiedMetric: nil,
            lastLogTimestamp: settings.snapshot.notifications.lastLogDate
        ) else {
            return nil
        }

        let facts = [
            localeLine(en: "Type: consistency nudge", pl: "Typ: przypomnienie o regularności"),
            localeLine(en: "Metric: \(metricTitle(for: result.kindRaw))", pl: "Metryka: \(metricTitle(for: result.kindRaw))"),
            result.body
        ]

        let route: AppNavigationRoute
        if let kind = MetricKind(rawValue: result.kindRaw) {
            route = .metricDetail(kindRaw: kind.rawValue)
        } else {
            route = .quickAdd(kindRaw: nil)
        }

        return AINotificationCandidate(
            kind: .consistencyNudge,
            metricKindRaw: result.kindRaw,
            facts: facts,
            score: result.reason == .missedPattern ? 3.6 : 3.2,
            confidence: result.reason == .missedPattern ? 0.72 : 0.64,
            fireDate: result.fireDate,
            deepLink: route,
            priority: .passive,
            dedupeKeys: ["consistencyNudge", "consistencyNudge.\(result.kindRaw)"]
        )
    }

    private func samplesInLast(_ samples: [MetricSample], days: Int) -> [MetricSample] {
        let start = calendar.date(byAdding: .day, value: -days, to: now) ?? .distantPast
        return samples.filter { $0.date >= start }
    }

    private func delta(samples: [MetricSample], days: Int) -> Double? {
        let window = samplesInLast(samples, days: days)
        guard let first = window.first, let last = window.last, first.date != last.date else { return nil }
        return last.value - first.value
    }

    private func trendThreshold(for kind: MetricKind, unitsSystem: String) -> Double {
        switch kind.unitCategory {
        case .weight:
            return kind.valueToMetric(fromDisplay: unitsSystem == "imperial" ? 1.5 : 0.7, unitsSystem: unitsSystem)
        case .length:
            return kind.valueToMetric(fromDisplay: unitsSystem == "imperial" ? 0.75 : 1.0, unitsSystem: unitsSystem)
        case .percent:
            return 1.0
        }
    }

    private func roundNumberStep(for kind: MetricKind, unitsSystem: String) -> Double? {
        switch kind {
        case .weight, .leanBodyMass:
            return unitsSystem == "imperial" ? 5 : 5
        case .waist, .hips, .chest, .shoulders, .neck, .leftBicep, .rightBicep, .leftForearm, .rightForearm, .leftThigh, .rightThigh, .leftCalf, .rightCalf, .bust:
            return unitsSystem == "imperial" ? 2 : 5
        case .bodyFat:
            return 5
        case .height:
            return nil
        }
    }

    private func nextDigestDate() -> Date {
        let digestTime = digestOrFallbackTime()
        let digestWeekday = min(max(settings.snapshot.notifications.aiDigestWeekday, 1), 7)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: digestTime)
        let currentWeekday = calendar.component(.weekday, from: now)
        var offset = digestWeekday - currentWeekday
        if offset < 0 {
            offset += 7
        }
        var candidateDate = calendar.date(byAdding: .day, value: offset, to: now) ?? now
        var components = calendar.dateComponents([.year, .month, .day], from: candidateDate)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        candidateDate = calendar.date(from: components) ?? candidateDate
        if candidateDate <= now {
            return calendar.date(byAdding: .day, value: 7, to: candidateDate) ?? candidateDate
        }
        return candidateDate
    }

    private func digestOrFallbackTime() -> Date {
        let digestTime = settings.snapshot.notifications.aiDigestTime
        if digestTime > 0 {
            return Date(timeIntervalSince1970: digestTime)
        }
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 19
        components.minute = 0
        return calendar.date(from: components) ?? now
    }

    private func goalBaselineValue(for goal: MetricGoal, samples: [MetricSample]) -> Double? {
        if let startValue = goal.startValue {
            return startValue
        }
        let anchorDate = goal.startDate ?? goal.createdDate
        if let baseline = samples.last(where: { $0.date <= anchorDate }) {
            return baseline.value
        }
        return samples.first?.value
    }

    private func goalProgress(goal: MetricGoal, baselineValue: Double, currentValue: Double) -> Double {
        switch goal.direction {
        case .increase:
            let denominator = goal.targetValue - baselineValue
            guard denominator > 0 else { return 0 }
            return min(max((currentValue - baselineValue) / denominator, 0), 1)
        case .decrease:
            let denominator = baselineValue - goal.targetValue
            guard denominator > 0 else { return 0 }
            return min(max((baselineValue - currentValue) / denominator, 0), 1)
        }
    }

    private func loadLastSentTimestamps() -> [String: TimeInterval] {
        guard let data = settings.snapshot.notifications.aiLastSentTimestamps else { return [:] }
        return (try? JSONDecoder().decode([String: TimeInterval].self, from: data)) ?? [:]
    }

    private func isMuted(_ kind: AINotificationKind) -> Bool {
        guard let data = settings.snapshot.notifications.aiMutedTypes,
              let rawValues = try? JSONDecoder().decode([String].self, from: data) else {
            return false
        }
        return rawValues.contains(kind.rawValue)
    }

    private func hasReachedCaps(sentTimestamps: [String: TimeInterval]) -> Bool {
        let dates = sentTimestamps.values.map { Date(timeIntervalSince1970: $0) }
        let todayCount = dates.filter { calendar.isDate($0, inSameDayAs: now) }.count
        guard todayCount < 1 else { return true }
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        return dates.filter { $0 >= weekAgo }.count >= 3
    }

    private func lastSentDate(for key: String, sentTimestamps: [String: TimeInterval]) -> Date? {
        guard let value = sentTimestamps[key] else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    private func wasSentRecently(
        key: String,
        minimumDays: Int,
        sentTimestamps: [String: TimeInterval]
    ) -> Bool {
        guard let lastDate = lastSentDate(for: key, sentTimestamps: sentTimestamps) else { return false }
        guard let thresholdDate = calendar.date(byAdding: .day, value: -minimumDays, to: now) else { return false }
        return lastDate >= thresholdDate
    }

    private func metricTitle(for kindRaw: String) -> String {
        MetricKind(rawValue: kindRaw)?.title ?? kindRaw
    }

    private func localeLine(en: String, pl: String) -> String {
        switch AINotificationLanguage.resolvedLanguage {
        case .pl:
            return pl
        default:
            return en
        }
    }
}

actor AINotificationGenerator {
    static let shared = AINotificationGenerator()

    private static let logger = Logger(subsystem: "com.jacek.measureme", category: "AINotifications")

    func generateDecision(for candidate: AINotificationCandidate) async -> AINotificationDecision? {
        guard await isAvailable() else { return nil }
        guard #available(iOS 26.0, *) else { return nil }

        do {
            let output = try await generateStructuredDecision(for: candidate.promptInput)
            return AINotificationOutputValidator.validate(output: output, candidate: candidate)
        } catch {
            Self.logger.warning("AI notification generation failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func isAvailable() async -> Bool {
        await MainActor.run {
            AppleIntelligenceSupport.isAvailable() && AINotificationLanguage.isSupported
        }
    }

    @available(iOS 26.0, *)
    private func generateStructuredDecision(
        for input: AINotificationPromptInput
    ) async throws -> AINotificationGeneratedOutput {
        #if canImport(FoundationModels)
        let session = LanguageModelSession(
            model: .default,
            instructions: instructions(for: input.localeCode)
        )
        let prompt = buildPrompt(for: input)
        let response = try await session.respond(to: prompt, generating: AINotificationStructuredOutput.self)
        return AINotificationGeneratedOutput(
            shouldSend: response.content.shouldSend,
            title: response.content.title,
            body: response.content.body,
            tone: response.content.tone,
            priority: response.content.priority,
            reason: response.content.reason
        )
        #else
        throw AINotificationGenerationError.notAvailable
        #endif
    }

    private func buildPrompt(for input: AINotificationPromptInput) -> String {
        let facts = input.facts.joined(separator: "\n")
        switch input.localeCode {
        case "pl":
            return """
            Wygeneruj decyzję dla krótkiego powiadomienia premium o postępie zdrowia/sylwetki.
            Priorytet bazowy: \(input.priority.rawValue)
            Typ: \(input.kind.rawValue)
            Fakty:
            \(facts)
            """
        case "de":
            return """
            Erstelle eine Entscheidung für eine kurze Premium-Mitteilung über Fortschritte bei Körper- und Gesundheitswerten.
            Grundpriorität: \(input.priority.rawValue)
            Typ: \(input.kind.rawValue)
            Fakten:
            \(facts)
            """
        case "fr":
            return """
            Génère une décision pour une courte notification premium sur les progrès liés au suivi du corps et de la santé.
            Priorité de base : \(input.priority.rawValue)
            Type : \(input.kind.rawValue)
            Faits :
            \(facts)
            """
        default:
            return """
            Generate a structured decision for a short premium health-progress notification.
            Base priority: \(input.priority.rawValue)
            Kind: \(input.kind.rawValue)
            Facts:
            \(facts)
            """
        }
    }

    private func instructions(for localeCode: String) -> String {
        switch localeCode {
        case "pl":
            return polishInstructions
        case "de":
            return germanInstructions
        case "fr":
            return frenchInstructions
        default:
            return englishInstructions
        }
    }

    private var englishInstructions: String {
        """
        You write short on-device premium notifications about body tracking progress.
        Decide whether this notification is worth sending based only on the facts provided.

        Hard rules:
        - Never invent facts, causes, dates, numbers, or comparisons.
        - Never give medical advice, diagnosis, treatment, or disease language.
        - Never shame, pressure, or use guilt.
        - If the facts are weak, repetitive, or low-value, return shouldSend false.

        Output rules:
        - Title: 3 to 8 words.
        - Body: 1 or 2 short sentences, max 180 characters.
        - Keep the tone concise, calm, specific, and encouraging.
        - Use only numbers already present in the facts.
        - Priority must be either passive or active.
        """
    }

    private var polishInstructions: String {
        """
        Tworzysz krótkie powiadomienia premium o postępach w śledzeniu sylwetki i zdrowia.
        Zdecyduj, czy warto wysłać to powiadomienie wyłącznie na podstawie podanych faktów.

        Twarde zasady:
        - Nie wymyślaj faktów, przyczyn, dat, liczb ani porównań.
        - Nie dawaj porad medycznych, diagnoz ani języka chorób.
        - Nie zawstydzaj i nie wywieraj presji.
        - Jeśli sygnał jest słaby, powtarzalny albo mało wartościowy, zwróć shouldSend = false.

        Zasady formatu:
        - Tytuł: od 3 do 8 słów.
        - Treść: 1 albo 2 krótkie zdania, maks. 180 znaków.
        - Ton: konkretny, spokojny, wspierający.
        - Używaj tylko liczb obecnych w faktach.
        - Priority musi być passive albo active.
        """
    }

    private var germanInstructions: String {
        """
        Du schreibst kurze Premium-Benachrichtigungen auf dem Gerät über Fortschritte beim Tracking von Körper- und Gesundheitswerten.
        Entscheide ausschließlich auf Basis der bereitgestellten Fakten, ob diese Benachrichtigung sinnvoll ist.

        Harte Regeln:
        - Erfinde niemals Fakten, Ursachen, Daten, Zahlen oder Vergleiche.
        - Gib keine medizinischen Ratschläge, Diagnosen, Behandlungen oder Krankheitsformulierungen.
        - Beschäme nicht und setze nicht unter Druck.
        - Wenn das Signal schwach, wiederholt oder wenig wertvoll ist, gib shouldSend false zurück.

        Ausgabe-Regeln:
        - Titel: 3 bis 8 Wörter.
        - Text: 1 oder 2 kurze Sätze, maximal 180 Zeichen.
        - Ton: präzise, ruhig, spezifisch und ermutigend.
        - Verwende nur Zahlen, die bereits in den Fakten vorkommen.
        - Priority muss entweder passive oder active sein.
        """
    }

    private var frenchInstructions: String {
        """
        Tu rédiges de courtes notifications premium sur l’appareil au sujet des progrès liés au suivi du corps et de la santé.
        Décide uniquement à partir des faits fournis si cette notification mérite d’être envoyée.

        Règles strictes :
        - N’invente jamais de faits, de causes, de dates, de chiffres ou de comparaisons.
        - Ne donne aucun conseil médical, diagnostic, traitement ou formulation liée à une maladie.
        - N’utilise ni culpabilisation ni pression.
        - Si le signal est faible, répétitif ou peu utile, renvoie shouldSend à false.

        Règles de sortie :
        - Titre : 3 à 8 mots.
        - Corps : 1 ou 2 phrases courtes, 180 caractères maximum.
        - Ton : concis, calme, précis et encourageant.
        - Utilise uniquement les nombres déjà présents dans les faits.
        - Priority doit être soit passive, soit active.
        """
    }
}

enum AINotificationOutputValidator {
    nonisolated static func validate(
        output: AINotificationGeneratedOutput,
        candidate: AINotificationCandidate
    ) -> AINotificationDecision? {
        let title = output.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = output.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard output.shouldSend else { return nil }
        guard !title.isEmpty, !body.isEmpty else { return nil }
        guard title.count <= 80, body.count <= 180 else { return nil }
        guard !containsDisallowedLanguage(body), !containsDisallowedLanguage(title) else { return nil }

        let candidateNumbers = extractNumericTokens(from: candidate.facts.joined(separator: " "))
        let responseNumbers = extractNumericTokens(from: "\(title) \(body)")
        guard responseNumbers.isSubset(of: candidateNumbers) else { return nil }

        let priority = AINotificationPriority(rawValue: output.priority) ?? candidate.priority
        return AINotificationDecision(
            shouldSend: true,
            title: title,
            body: body,
            priority: priority,
            reason: output.reason
        )
    }

    private nonisolated static func containsDisallowedLanguage(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let disallowedTokens = [
            "diagnosis", "disease", "mortality", "supplement", "medication",
            "diagnoza", "choroba", "śmiertelność", "suplement", "lek"
        ]
        return disallowedTokens.contains { lowercased.contains($0) }
    }

    private nonisolated static func extractNumericTokens(from text: String) -> Set<String> {
        let pattern = #"-?\d+(?:[.,]\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return Set(regex.matches(in: text, range: nsRange).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]).replacingOccurrences(of: ",", with: ".") }
        })
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "Structured result for a premium AI notification.")
struct AINotificationStructuredOutput {
    let shouldSend: Bool
    let title: String
    let body: String
    let tone: String
    let priority: String
    let reason: String
}
#endif

private enum AINotificationGenerationError: Error {
    case notAvailable
}
