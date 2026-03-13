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

actor MetricInsightService {
    static let shared = MetricInsightService()

    private static let logger = Logger(subsystem: "com.jacek.measureme", category: "AIInsights")
    private static let cacheLimit = 50

    private var cache: [MetricInsightInput: MetricInsightPair] = [:]
    private var healthCache: [HealthInsightInput: String] = [:]
    private var inFlight: [MetricInsightInput: Task<MetricInsightPair?, Never>] = [:]
    private var healthInFlight: [HealthInsightInput: Task<String?, Never>] = [:]

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
            let context = buildPrompt(for: input) + "\n\nYour previous insight:\n" + originalInsight
            _ = try await session.respond(to: context)
            conversationSession = session
        }

        let response = try await conversationSession!.respond(to: question)
        let cleaned = Self.sanitize(response.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.truncateAtSentence(cleaned, maxLength: 280)
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
    }

    func invalidateHealth() {
        healthCache.removeAll()
    }

    func generateInsight(for input: MetricInsightInput) async -> MetricInsightPair? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestLongInsight") {
            return MetricInsightPair(
                shortText: "UI_TEST_LONG_INSIGHT_MARKER You are moving in a positive direction with stable momentum across recent entries and better consistency.",
                detailedText: "UI_TEST_LONG_INSIGHT_MARKER Keep this pace for the next 7 days by logging at the same time every day and adding one more structured check-in before the week ends."
            )
        }
        #endif
        guard await MainActor.run(body: { AppleIntelligenceSupport.isAvailable() }) else { return nil }

        if let cached = cache[input] {
            return cached
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
    }

    func generateHealthInsight(for input: HealthInsightInput) async -> String? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestLongHealthInsight") {
            return "UI_TEST_LONG_HEALTH_INSIGHT_MARKER You’re trending in a steady direction with consistent entries and balanced changes across your core indicators. Keep momentum by logging at the same time, aiming for three strength sessions, and a daily 8–10k step target this week. Focus on regular meals and hydration to support recovery and energy."
        }
        #endif
        guard await MainActor.run(body: { AppleIntelligenceSupport.isAvailable() }) else { return nil }

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

    private func generate(input: MetricInsightInput) async throws -> MetricInsightPair {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            throw MetricInsightError.notAvailable
        }

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
            Paragraph 1: 1 short sentence, max 96 characters, summarizing the overall trend.
            Paragraph 2: 2-4 short sentences, max 420 characters.
            Paragraph 2 must include:
            - one comparison across short, mid, and long trend windows when available (14/30/90 days),
            - one concrete recommendation for the next 7 days,
            - goal context if present.

            Example output:
            Your weight is gradually trending down over the past month.
            <SEP>
            You have lost 0.8 kg in the last 30 days while your 90-day trend stays flat. Try adding one extra walk this week to keep the momentum going. You are on track toward your goal of reaching 80 kg.
            """
        )

        let prompt = buildPrompt(for: input)
        let response = try await session.respond(to: prompt)
        return Self.parse(response.content)
        #else
        throw MetricInsightError.notAvailable
        #endif
    }

    private func buildPrompt(for input: MetricInsightInput) -> String {
        var lines: [String] = [
            "Metric: \(input.metricTitle)",
            "Latest value: \(input.latestValueText)",
            "Aggregated analysis window: \(input.timeframeLabel)",
            "Number of samples in analysis window: \(input.sampleCount)"
        ]

        if let name = input.userName {
            lines.insert("User name: \(Self.sanitizeUserName(name))", at: 1)
        }
        if let d14 = input.delta14DaysText ?? input.delta7DaysText {
            lines.append("14-day change: \(d14)")
        }
        if let d30 = input.delta30DaysText {
            lines.append("30-day change: \(d30)")
        }
        if let d90 = input.delta90DaysText {
            lines.append("90-day change: \(d90)")
        }
        if let goal = input.goalStatusText {
            lines.append("Goal status: \(goal)")
        }
        if let dir = input.goalDirectionText {
            lines.append("Goal direction: \(dir)")
        }
        lines.append("Default favorable direction (if no goal): \(input.defaultFavorableDirectionText)")
        lines.append("")
        lines.append("Ignore any UI chart range and write the insight from these aggregated windows only.")
        lines.append("Write the two-paragraph insight using second person.")

        return lines.joined(separator: "\n")
    }

    private func generateHealth(input: HealthInsightInput) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            throw MetricInsightError.notAvailable
        }

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
            """
        )

        let prompt = Self.buildHealthPrompt(for: input)

        let response = try await session.respond(to: prompt)
        let normalized = Self.sanitize(response.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized
        #else
        throw MetricInsightError.notAvailable
        #endif
    }

    private static func buildHealthPrompt(for input: HealthInsightInput) -> String {
        var lines: [String] = []

        if let name = input.userName {
            lines.append("User name: \(sanitizeUserName(name))")
        }

        var profile: [String] = []
        if let age = input.ageText { profile.append("Age: \(age)") }
        if let gender = input.genderText { profile.append("Gender: \(gender)") }
        if !profile.isEmpty {
            lines.append("User profile:")
            lines.append(contentsOf: profile)
        }

        var body: [String] = []
        if let w = input.latestWeightText { body.append("Weight: \(w)") }
        if let wa = input.latestWaistText { body.append("Waist: \(wa)") }
        if let bf = input.latestBodyFatText { body.append("Body Fat: \(bf)") }
        if let lm = input.latestLeanMassText { body.append("Lean Mass: \(lm)") }
        if !body.isEmpty {
            lines.append("")
            lines.append("Latest body data:")
            lines.append(contentsOf: body)
        }

        var deltas: [String] = []
        if let wd = input.weightDelta7dText { deltas.append("Weight change: \(wd)") }
        if let wad = input.waistDelta7dText { deltas.append("Waist change: \(wad)") }
        if !deltas.isEmpty {
            lines.append("")
            lines.append("Last 7 days:")
            lines.append(contentsOf: deltas)
        }

        var core: [String] = []
        if let whr = input.coreWHtRText { core.append("WHtR: \(whr)") }
        if let bmi = input.coreBMIText { core.append("BMI: \(bmi)") }
        if let rfm = input.coreRFMText { core.append("RFM: \(rfm)") }
        if !core.isEmpty {
            lines.append("")
            lines.append("Core metrics:")
            lines.append(contentsOf: core)
        }

        return lines.joined(separator: "\n")
    }

    private static func sanitizeUserName(_ name: String) -> String {
        let stripped = name
            .components(separatedBy: .newlines).joined(separator: " ")
            .components(separatedBy: .controlCharacters).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(stripped.prefix(50))
    }

    private static func parse(_ raw: String) -> MetricInsightPair {
        let trimmed = sanitize(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.components(separatedBy: "\n<SEP>\n")

        var short = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var detail = parts.dropFirst().joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)

        if short.isEmpty { short = trimmed }
        if detail.isEmpty { detail = trimmed }

        short = truncateAtSentence(short, maxLength: 96)
        detail = truncateAtSentence(detail, maxLength: 420)

        if short.isEmpty {
            short = "Your trend is being analyzed."
        }

        if detail.isEmpty {
            detail = "Keep logging consistently to get a clearer trend signal."
        }

        return MetricInsightPair(shortText: short, detailedText: detail)
    }

    private static func truncateAtSentence(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let prefix = String(text.prefix(maxLength))
        if let lastDot = prefix.lastIndex(of: ".") {
            return String(prefix[...lastDot])
        }
        return prefix
    }

    private static func sanitize(_ text: String) -> String {
        var output = text
        output = output.replacingOccurrences(of: "###", with: "")
        output = output.replacingOccurrences(of: "##", with: "")
        output = output.replacingOccurrences(of: "#", with: "")
        output = output.replacingOccurrences(of: "**", with: "")
        output = output.replacingOccurrences(of: "__", with: "")
        output = output.replacingOccurrences(of: "`", with: "")
        output = output.replacingOccurrences(of: "\n- ", with: "\n")
        output = output.replacingOccurrences(of: "\n* ", with: "\n")
        output = output.replacingOccurrences(of: "\n• ", with: "\n")
        output = output.replacingOccurrences(of: "SHORT:", with: "", options: .caseInsensitive)
        output = output.replacingOccurrences(of: "DETAIL:", with: "", options: .caseInsensitive)
        output = output.replacingOccurrences(of: "As an AI", with: "", options: .caseInsensitive)
        output = output.replacingOccurrences(of: "Certainly,", with: "", options: .caseInsensitive)
        output = output.replacingOccurrences(of: "Here is", with: "", options: .caseInsensitive)
        output = output.replacingOccurrences(of: "Here's", with: "", options: .caseInsensitive)
        while output.contains("  ") {
            output = output.replacingOccurrences(of: "  ", with: " ")
        }
        while output.contains("\n\n\n") {
            output = output.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return output
    }
}

private enum MetricInsightError: Error {
    case notAvailable
}
