import Foundation
import os.log

#if canImport(FoundationModels)
import FoundationModels
#endif

nonisolated struct MetricInsightInput: Sendable, Hashable {
    let userName: String?
    let metricTitle: String
    let latestValueText: String
    let timeframeLabel: String
    let sampleCount: Int
    let delta7DaysText: String?
    let delta14DaysText: String?
    let delta30DaysText: String?
    let delta90DaysText: String?
    let goalStatusText: String?
    /// "increase" | "decrease" (nil oznacza brak aktywnego celu)
    let goalDirectionText: String?
    /// "increase" | "decrease" | "neutral"
    let defaultFavorableDirectionText: String
}

struct MetricInsightPair: Sendable {
    let shortText: String
    let detailedText: String
}

struct InsightMessage: Identifiable, Sendable {
    let id = UUID()
    let role: Role
    let text: String
    enum Role: Sendable { case assistant, user }
}

nonisolated struct HealthInsightInput: Sendable, Hashable {
    let userName: String?
    let ageText: String?
    let genderText: String?
    let latestWeightText: String?
    let latestWaistText: String?
    let latestBodyFatText: String?
    let latestLeanMassText: String?
    let weightDelta7dText: String?
    let waistDelta7dText: String?
    let coreWHtRText: String?
    let coreBMIText: String?
    let coreRFMText: String?
}

nonisolated struct SectionInsightInput: Sendable, Hashable {
    let sectionID: String
    let sectionTitle: String
    let userName: String?
    let contextLines: [String]
}

enum AppleIntelligenceSupport {
    static func isAvailable() -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestForceAIAvailable") {
            return true
        }
        #endif
        let settings = AppSettingsStore.shared.snapshot
        let enabled = settings.analytics.appleIntelligenceEnabled
        guard enabled else { return false }
        let premium = settings.premium.premiumEntitlement
        guard premium else { return false }
        #if targetEnvironment(simulator)
        return false
        #else
        guard #available(iOS 26.0, *) else { return false }
        #if canImport(FoundationModels)
        return SystemLanguageModel.default.isAvailable
        #else
        return false
        #endif
        #endif
    }

#if DEBUG
    static func debugAvailabilityText() -> String {
        let settings = AppSettingsStore.shared.snapshot
        let enabled = settings.analytics.appleIntelligenceEnabled
        guard enabled else { return "AI Insights: unavailable (disabled in app)" }
        let premium = settings.premium.premiumEntitlement
        guard premium else { return AppLocalization.string("AI Insights: unavailable (Premium Edition required)") }
        #if targetEnvironment(simulator)
        return "AI Insights: unavailable (not supported in Simulator)"
        #else
        guard #available(iOS 26.0, *) else {
            return "AI Insights: unavailable (requires iOS 26+)"
        }
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return "AI Insights: available"
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "AI Insights: unavailable (device not eligible)"
            case .appleIntelligenceNotEnabled:
                return "AI Insights: unavailable (disabled in Settings)"
            case .modelNotReady:
                return "AI Insights: unavailable (model not ready)"
            @unknown default:
                return "AI Insights: unavailable (unknown reason)"
            }
        }
        #else
        return "AI Insights: unavailable (FoundationModels missing)"
        #endif
        #endif
    }
#endif
}

// MARK: - Persistent Cache

nonisolated struct InsightDiskCache {
    #if DEBUG
    nonisolated(unsafe) static var suiteName = "group.com.jacek.measureme"
    nonisolated(unsafe) static var ttl: TimeInterval = 24 * 60 * 60
    nonisolated(unsafe) static var maxEntries = 80
    #else
    static let suiteName = "group.com.jacek.measureme"
    static let ttl: TimeInterval = 24 * 60 * 60
    static let maxEntries = 80
    #endif
    private static let storeKey = "insight_disk_cache_v1"

    struct Entry: Codable {
        let shortText: String
        let detailedText: String
        let timestamp: Date
    }

    static func read(forKey key: String) -> MetricInsightPair? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: storeKey),
              let store = try? JSONDecoder().decode([String: Entry].self, from: data),
              let entry = store[key] else { return nil }
        guard Date().timeIntervalSince(entry.timestamp) < ttl else { return nil }
        return MetricInsightPair(shortText: entry.shortText, detailedText: entry.detailedText)
    }

    static func write(_ pair: MetricInsightPair, forKey key: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        var store: [String: Entry] = {
            guard let data = defaults.data(forKey: storeKey),
                  let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
            return decoded
        }()

        // Evict expired entries
        let now = Date()
        store = store.filter { now.timeIntervalSince($0.value.timestamp) < ttl }

        // Enforce max size
        if store.count >= maxEntries {
            let sorted = store.sorted { $0.value.timestamp < $1.value.timestamp }
            let toRemove = store.count - maxEntries + 1
            for item in sorted.prefix(toRemove) {
                store.removeValue(forKey: item.key)
            }
        }

        store[key] = Entry(shortText: pair.shortText, detailedText: pair.detailedText, timestamp: now)

        if let encoded = try? JSONEncoder().encode(store) {
            defaults.set(encoded, forKey: storeKey)
        }
    }

    static func removeEntries(matching metricTitle: String) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: storeKey),
              var store = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        store = store.filter { !$0.key.contains(metricTitle) }
        if let encoded = try? JSONEncoder().encode(store) {
            defaults.set(encoded, forKey: storeKey)
        }
    }
}

actor MetricInsightService {
    static let shared = MetricInsightService()

    private static let logger = Logger(subsystem: "com.jacek.measureme", category: "AIInsights")
    static let cacheLimit = 50

    private var cache: [MetricInsightInput: MetricInsightPair] = [:]
    private var healthCache: [HealthInsightInput: String] = [:]
    private var sectionCache: [SectionInsightInput: String] = [:]
    private var inFlight: [MetricInsightInput: Task<MetricInsightPair?, Never>] = [:]
    private var healthInFlight: [HealthInsightInput: Task<String?, Never>] = [:]
    private var sectionInFlight: [SectionInsightInput: Task<String?, Never>] = [:]

    // MARK: - Concurrency Queue

    private let maxConcurrent = 2
    private var activeGenerationCount = 0
    private var generationWaiters: [CheckedContinuation<Void, Never>] = []

    private func acquireGenerationSlot() async {
        if activeGenerationCount < maxConcurrent {
            activeGenerationCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            generationWaiters.append(continuation)
        }
    }

    private func releaseGenerationSlot() {
        if let next = generationWaiters.first {
            generationWaiters.removeFirst()
            next.resume()
        } else {
            activeGenerationCount -= 1
        }
    }

    #if DEBUG
    /// Visible only in tests via @testable import.
    private var _testGenerateOverride: (@Sendable (MetricInsightInput) async throws -> MetricInsightPair)?
    private var _testGenerateHealthOverride: (@Sendable (HealthInsightInput) async throws -> String)?
    private var _testGenerateSectionOverride: (@Sendable (SectionInsightInput) async throws -> String)?
    private var _testAvailabilityOverride: Bool?

    func setTestGenerateOverride(_ block: (@Sendable (MetricInsightInput) async throws -> MetricInsightPair)?) {
        _testGenerateOverride = block
    }

    func setTestGenerateHealthOverride(_ block: (@Sendable (HealthInsightInput) async throws -> String)?) {
        _testGenerateHealthOverride = block
    }

    func setTestGenerateSectionOverride(_ block: (@Sendable (SectionInsightInput) async throws -> String)?) {
        _testGenerateSectionOverride = block
    }

    func setTestAvailabilityOverride(_ value: Bool?) {
        _testAvailabilityOverride = value
    }
    #endif

    #if canImport(FoundationModels)
    private var conversationSessionStorage: Any?
    #endif

    // MARK: - Conversation

    func followUp(question: String, originalInsight: String, input: MetricInsightInput) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            throw MetricInsightError.notAvailable
        }

        var conversationSession: LanguageModelSession? {
            get { conversationSessionStorage as? LanguageModelSession }
            set { conversationSessionStorage = newValue }
        }

        if conversationSession == nil {
            let session = LanguageModelSession(
                model: .default,
                instructions: """
                You are a calm, supportive health-tracking coach continuing a conversation about a user's metric data.
                Answer follow-up questions about the insight you provided.
                Keep answers concise, 1-3 sentences, max 280 characters.
                Stay focused on the metric data provided. Do not speculate beyond the data.

                Safety rules:
                Do not provide medical diagnosis or medical advice.
                Do not mention diseases, mortality, or clinical "risk of" outcomes.
                Do not recommend supplements, medications, or extreme diets.

                Format rules:
                Do not use markdown, hashtags, bullets, quotes, or bold markers.
                Do not add greetings, preambles, framing phrases, or meta text.
                Address the user directly using "you" and "your".
                """
            )

            // Seed the session with the metric context and original insight
            let context = InsightTextProcessor.buildPrompt(for: input) + "\n\nYour previous insight:\n" + originalInsight
            _ = try await session.respond(to: context)
            conversationSession = session
        }

        guard let session = conversationSession else {
            throw MetricInsightError.notAvailable
        }
        let response = try await session.respond(to: question)
        let cleaned = InsightTextProcessor.sanitize(response.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
        #else
        throw MetricInsightError.notAvailable
        #endif
    }

    func clearConversation() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            conversationSessionStorage = nil
        }
        #endif
    }

    // MARK: - Cache Invalidation

    func invalidate(for metricTitle: String) {
        cache = cache.filter { $0.key.metricTitle != metricTitle }
        InsightDiskCache.removeEntries(matching: metricTitle)
    }

    func invalidateHealth() {
        healthCache.removeAll()
    }

    func invalidateSections() {
        sectionCache.removeAll()
    }

    // MARK: - Generation

    func generateInsight(for input: MetricInsightInput) async -> MetricInsightPair? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestLongInsight") {
            return MetricInsightPair(
                shortText: "UI_TEST_LONG_INSIGHT_MARKER You are moving in a positive direction with stable momentum across recent entries and better consistency.",
                detailedText: "UI_TEST_LONG_INSIGHT_MARKER Keep this pace for the next 7 days by logging at the same time every day and adding one more structured check-in before the week ends."
            )
        }
        #endif
        guard await isAvailable() else { return nil }

        if let cached = cache[input] {
            return cached
        }

        // Check persistent disk cache
        let diskKey = "\(input.metricTitle)_\(input.hashValue)"
        if let diskCached = InsightDiskCache.read(forKey: diskKey) {
            cache[input] = diskCached
            return diskCached
        }

        if let running = inFlight[input] {
            return await running.value
        }

        let task = Task<MetricInsightPair?, Never> { [input] in
            do {
                let generated = try await self.generate(input: input)
                self.storeGenerated(generated, for: input)
                return generated
            } catch {
                Self.logger.warning("Metric insight generation failed for \(input.metricTitle): \(error.localizedDescription)")
                return nil
            }
        }
        inFlight[input] = task

        let value = await task.value
        inFlight[input] = nil
        return value
    }

    private func storeGenerated(_ insight: MetricInsightPair, for input: MetricInsightInput) {
        if cache.count >= Self.cacheLimit {
            cache.removeAll()
        }
        cache[input] = insight

        let diskKey = "\(input.metricTitle)_\(input.hashValue)"
        InsightDiskCache.write(insight, forKey: diskKey)
    }

    func generateHealthInsight(for input: HealthInsightInput) async -> String? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestLongHealthInsight") {
            return "UI_TEST_LONG_HEALTH_INSIGHT_MARKER You're trending in a steady direction with consistent entries and balanced changes across your core indicators. Keep momentum by logging at the same time, aiming for three strength sessions, and a daily 8–10k step target this week. Focus on regular meals and hydration to support recovery and energy."
        }
        #endif
        guard await isAvailable() else { return nil }

        if let cached = healthCache[input] {
            return cached
        }

        if let running = healthInFlight[input] {
            return await running.value
        }

        let task = Task<String?, Never> { [input] in
            do {
                let generated = try await self.generateHealth(input: input)
                if self.healthCache.count >= Self.cacheLimit {
                    self.healthCache.removeAll()
                }
                self.healthCache[input] = generated
                return generated
            } catch {
                Self.logger.warning("Health insight generation failed: \(error.localizedDescription)")
                return nil
            }
        }
        healthInFlight[input] = task

        let value = await task.value
        healthInFlight[input] = nil
        return value
    }

    func generateSectionInsight(for input: SectionInsightInput) async -> String? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestLongHealthInsight") {
            return "UI_TEST_LONG_SECTION_INSIGHT_MARKER You have enough signal across measurements, health indicators, and physique ratios to keep a clear direction this week. Stay consistent with logging and focus on one priority lever to keep momentum."
        }
        #endif
        guard await isAvailable() else { return nil }

        if let cached = sectionCache[input] {
            return cached
        }

        if let running = sectionInFlight[input] {
            return await running.value
        }

        let task = Task<String?, Never> { [input] in
            do {
                let generated = try await self.generateSection(input: input)
                if self.sectionCache.count >= Self.cacheLimit {
                    self.sectionCache.removeAll()
                }
                self.sectionCache[input] = generated
                return generated
            } catch {
                Self.logger.warning("Section insight generation failed for \(input.sectionID): \(error.localizedDescription)")
                return nil
            }
        }
        sectionInFlight[input] = task

        let value = await task.value
        sectionInFlight[input] = nil
        return value
    }

    // MARK: - Private Generation (with concurrency queue)

    private func isAvailable() async -> Bool {
        #if DEBUG
        if let override = _testAvailabilityOverride { return override }
        #endif
        return await MainActor.run(body: { AppleIntelligenceSupport.isAvailable() })
    }

    private func generate(input: MetricInsightInput) async throws -> MetricInsightPair {
        #if DEBUG
        if let override = _testGenerateOverride {
            await acquireGenerationSlot()
            do {
                let result = try await override(input)
                releaseGenerationSlot()
                return result
            } catch {
                releaseGenerationSlot()
                throw error
            }
        }
        #endif

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            throw MetricInsightError.notAvailable
        }

        await acquireGenerationSlot()

        do {
            let session = LanguageModelSession(
                model: .default,
                instructions: """
                You are a calm, supportive health-tracking coach.
                Write in clear, plain English.
                Keep tone non-judgmental, practical, and concise.
                Address the user directly using "you" and "your".
                Never write in third person about the user.

                Safety rules:
                Do not provide medical diagnosis or medical advice.
                Do not mention diseases, mortality, or clinical "risk of" outcomes.
                Do not recommend supplements, medications, or extreme diets.
                If some data is missing or ambiguous, do not guess; omit that detail.
                Do not repeat placeholders like "unknown", "n/a", or "not enough data".

                Format rules:
                Do not use markdown, hashtags, bullets, quotes, or bold markers.
                Do not add greetings, preambles, framing phrases, or meta text (e.g., "As an AI...").
                Return exactly two paragraphs separated by a single line containing only: <SEP>
                Do not include any other line breaks.

                Content rules:
                Use the provided goal direction if present; otherwise use the default favorable direction hint.
                Paragraph 1: 1 very short sentence, around 40-60 characters, summarizing the overall trend. This is shown as a headline on a compact card — keep it punchy.
                Paragraph 2: 2-4 short sentences, around 150-250 characters total.
                Paragraph 2 must include:
                - one comparison across available trend windows (14/30/90 days),
                - one concrete recommendation for the next 7 days,
                - if a goal is present: mention progress so far, current momentum, and whether the pace needs adjusting. Go beyond just an estimated completion date — highlight what is working and what could improve.

                Example output:
                Weight trending down steadily.
                <SEP>
                You lost 0.8 kg in 30 days while your 7-day pace picked up. Try one extra walk this week to keep momentum. You are 2.3 kg from your goal and recent progress looks solid.
                """
            )

            let prompt = InsightTextProcessor.buildPrompt(for: input)
            let response = try await session.respond(to: prompt)
            releaseGenerationSlot()
            return InsightTextProcessor.parse(response.content)
        } catch {
            releaseGenerationSlot()
            throw error
        }
        #else
        throw MetricInsightError.notAvailable
        #endif
    }

    private func generateHealth(input: HealthInsightInput) async throws -> String {
        #if DEBUG
        if let override = _testGenerateHealthOverride {
            await acquireGenerationSlot()
            do {
                let result = try await override(input)
                releaseGenerationSlot()
                return result
            } catch {
                releaseGenerationSlot()
                throw error
            }
        }
        #endif

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            throw MetricInsightError.notAvailable
        }

        await acquireGenerationSlot()

        do {
            let session = LanguageModelSession(
                model: .default,
                instructions: """
                You are a supportive health and fitness coach.
                Write in plain English.
                Address the user directly using "you" and "your".
                Never write in third person about the user.
                Summarize current state, recent changes, and trend direction.
                Include one concrete focus area and one practical next-step instruction.
                Keep it warm, encouraging, and non-alarming.
                Use positive framing and gentle reassurance.
                Avoid judgmental labels.

                Safety rules:
                Do not provide medical diagnosis or medical advice.
                Do not mention diseases, mortality, or clinical "risk of" outcomes.
                Do not recommend supplements, medications, or extreme diets.
                If some data is missing or ambiguous, do not guess; omit that detail.
                Do not repeat placeholders like "unknown", "n/a", or "not enough data".

                Format rules:
                Do not use markdown, hashtags, bullets, quotes, or bold markers.
                Do not add greetings, preambles, framing phrases, or meta text (e.g., "As an AI...").
                Output 3-4 short sentences in one paragraph, max 360 characters.

                Example output:
                Your weight is holding steady at 82 kg with body fat down slightly over the past week. Your waist-to-height ratio sits in a healthy range and your lean mass is well maintained. Focus on hitting three strength sessions this week and keeping daily steps above 8,000.
                """
            )

            let prompt = InsightTextProcessor.buildHealthPrompt(for: input)
            let response = try await session.respond(to: prompt)
            let normalized = InsightTextProcessor.sanitize(response.content)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            releaseGenerationSlot()
            return normalized
        } catch {
            releaseGenerationSlot()
            throw error
        }
        #else
        throw MetricInsightError.notAvailable
        #endif
    }

    private func generateSection(input: SectionInsightInput) async throws -> String {
        #if DEBUG
        if let override = _testGenerateSectionOverride {
            await acquireGenerationSlot()
            do {
                let result = try await override(input)
                releaseGenerationSlot()
                return result
            } catch {
                releaseGenerationSlot()
                throw error
            }
        }
        #endif

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            throw MetricInsightError.notAvailable
        }

        await acquireGenerationSlot()

        do {
            let session = LanguageModelSession(
                model: .default,
                instructions: """
                You are a concise fitness and body-tracking coach.
                Write in plain English.
                Address the user directly using "you" and "your".
                Never write in third person about the user.
                Summarize the current state from the provided section data.
                Mention one clear trend and one practical next step for the next 7 days.

                Safety rules:
                Do not provide medical diagnosis or medical advice.
                Do not mention diseases, mortality, or clinical "risk of" outcomes.
                Do not recommend supplements, medications, or extreme diets.
                If data is missing, skip it instead of guessing.

                Format rules:
                Do not use markdown, bullets, quotes, or headings.
                Do not add greetings or meta text.
                Output 2-3 short sentences in one paragraph, max 380 characters.
                """
            )

            let prompt = InsightTextProcessor.buildSectionPrompt(for: input)
            let response = try await session.respond(to: prompt)
            let normalized = InsightTextProcessor.sanitize(response.content)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            releaseGenerationSlot()
            return normalized
        } catch {
            releaseGenerationSlot()
            throw error
        }
        #else
        throw MetricInsightError.notAvailable
        #endif
    }
}

private enum MetricInsightError: Error {
    case notAvailable
}
