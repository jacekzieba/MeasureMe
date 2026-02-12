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
        guard enabled else { return "Apple Intelligence: unavailable (disabled in app)" }
        let premium = UserDefaults.standard.bool(forKey: "premium_entitlement")
        guard premium else { return AppLocalization.string("Apple Intelligence: unavailable (Premium Edition required)") }
        #if targetEnvironment(simulator)
        return "Apple Intelligence: unavailable (not supported in Simulator)"
        #else
        guard #available(iOS 26.0, *) else {
            return "Apple Intelligence: unavailable (requires iOS 26+)"
        }
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return "Apple Intelligence: available"
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "Apple Intelligence: unavailable (device not eligible)"
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence: unavailable (disabled in Settings)"
            case .modelNotReady:
                return "Apple Intelligence: unavailable (model not ready)"
            }
        }
        #else
        return "Apple Intelligence: unavailable (FoundationModels missing)"
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
            Do not provide medical diagnosis.
            Do not use markdown, hashtags, bullets, or bold markers.
            Do not add greetings, preambles, or framing phrases.
            Return exactly two paragraphs separated by a single line containing only: <SEP>
            Paragraph 1: 1-2 short sentences, max 140 characters.
            Paragraph 2: 2-4 short sentences, max 360 characters.
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
        """
        Metric: \(input.metricTitle)
        User name: \(input.userName ?? "unknown")
        Latest value: \(input.latestValueText)
        Timeframe: \(input.timeframeLabel)
        Number of samples in timeframe: \(input.sampleCount)
        7-day change: \(input.delta7DaysText ?? "not enough data")
        30-day change: \(input.delta30DaysText ?? "not enough data")
        Goal status: \(input.goalStatusText ?? "no active goal")

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
            Summarize current state, recent changes, trend direction, and one practical next-step advice.
            Keep it warm, encouraging, and non-alarming.
            Use positive framing and gentle reassurance.
            Do not use markdown, hashtags, bullets, or bold markers.
            Do not add greetings, preambles, or framing phrases.
            Output 3-5 short sentences in one or two short paragraphs, max 480 characters.
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
        return String(normalized.prefix(520))
        #else
        throw MetricInsightError.notAvailable
        #endif
    }

    private static func parse(_ raw: String) -> MetricInsightPair {
        let trimmed = sanitize(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.components(separatedBy: "\n<SEP>\n")

        var short = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var detail = parts.dropFirst().joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)

        if short.isEmpty { short = String(trimmed.prefix(220)).trimmingCharacters(in: .whitespacesAndNewlines) }
        if detail.isEmpty { detail = trimmed }

        if short.count > 140 {
            short = String(short.prefix(140)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if detail.count > 420 {
            detail = String(detail.prefix(420)).trimmingCharacters(in: .whitespacesAndNewlines)
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
        output = output.replacingOccurrences(of: "Certainly,", with: "", options: .caseInsensitive)
        output = output.replacingOccurrences(of: "Here is", with: "", options: .caseInsensitive)
        output = output.replacingOccurrences(of: "Here's", with: "", options: .caseInsensitive)
        while output.contains("\n\n\n") {
            output = output.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return output
    }
}

private enum MetricInsightError: Error {
    case notAvailable
}
