import Foundation

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
    let delta30DaysText: String?
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
        let enabled = UserDefaults.standard.object(forKey: "apple_intelligence_enabled") as? Bool ?? true
        guard enabled else { return false }
        let premium = UserDefaults.standard.bool(forKey: "premium_entitlement")
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
        let enabled = UserDefaults.standard.object(forKey: "apple_intelligence_enabled") as? Bool ?? true
        guard enabled else { return "AI Insights: unavailable (disabled in app)" }
        let premium = UserDefaults.standard.bool(forKey: "premium_entitlement")
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

    private var cache: [MetricInsightInput: MetricInsightPair] = [:]
    private var healthCache: [HealthInsightInput: String] = [:]
    private var inFlight: [MetricInsightInput: Task<MetricInsightPair?, Never>] = [:]
    private var healthInFlight: [HealthInsightInput: Task<String?, Never>] = [:]

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
                return nil
            }
        }
        inFlight[input] = task

        let value = await task.value
        inFlight[input] = nil
        return value
    }

    private func storeGenerated(_ insight: MetricInsightPair, for input: MetricInsightInput) {
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
                self.healthCache[input] = generated
                return generated
            } catch {
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
            Paragraph 1: 1 short sentence, max 88 characters, summarizing the recent trend.
            Paragraph 2: 1-2 short sentences, max 180 characters, ending with one specific next step for the next 7 days.
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
        let trend7d = Self.trendDirection(from: input.delta7DaysText)
        let trend30d = Self.trendDirection(from: input.delta30DaysText)
        let goalDirection = input.goalDirectionText ?? "none"

        return """
        Metric: \(input.metricTitle)
        User name: \(input.userName ?? "unknown")
        Latest value: \(input.latestValueText)
        Timeframe: \(input.timeframeLabel)
        Number of samples in timeframe: \(input.sampleCount)
        7-day change: \(input.delta7DaysText ?? "not enough data")
        30-day change: \(input.delta30DaysText ?? "not enough data")
        Goal status: \(input.goalStatusText ?? "no active goal")
        Goal direction: \(goalDirection)
        Default favorable direction (if no goal): \(input.defaultFavorableDirectionText)
        Trend direction (7 days): \(trend7d)
        Trend direction (30 days): \(trend30d)

        Write the two-paragraph insight using second person.
        """
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

        let prompt = """
        User name: \(input.userName ?? "unknown")
        User profile:
        Age: \(input.ageText ?? "unknown")
        Gender: \(input.genderText ?? "not specified")

        Latest body data:
        Weight: \(input.latestWeightText ?? "n/a")
        Waist: \(input.latestWaistText ?? "n/a")
        Body Fat: \(input.latestBodyFatText ?? "n/a")
        Lean Mass: \(input.latestLeanMassText ?? "n/a")

        Last 7 days:
        Weight change: \(input.weightDelta7dText ?? "not enough data")
        Waist change: \(input.waistDelta7dText ?? "not enough data")

        Core metrics:
        WHtR: \(input.coreWHtRText ?? "n/a")
        BMI: \(input.coreBMIText ?? "n/a")
        RFM: \(input.coreRFMText ?? "n/a")
        """

        let response = try await session.respond(to: prompt)
        let normalized = Self.sanitize(response.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized
        #else
        throw MetricInsightError.notAvailable
        #endif
    }

    private static func trendDirection(from deltaText: String?) -> String {
        guard let deltaText else { return "unknown" }
        let trimmed = deltaText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "unknown" }
        if first == "+" { return "up" }
        if first == "-" { return "down" }
        return "steady"
    }

    private static func parse(_ raw: String) -> MetricInsightPair {
        let trimmed = sanitize(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.components(separatedBy: "\n<SEP>\n")

        var short = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var detail = parts.dropFirst().joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)

        // Fallbacks without artificial truncation
        if short.isEmpty {
            short = trimmed
        }
        if detail.isEmpty {
            detail = trimmed
        }

        if short.isEmpty {
            short = "Your trend is being analyzed."
        }

        if detail.isEmpty {
            detail = "Keep logging consistently to get a clearer trend signal."
        }

        return MetricInsightPair(shortText: short, detailedText: detail)
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
