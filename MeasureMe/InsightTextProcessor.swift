import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

nonisolated enum InsightTextProcessor {
    private static let appLanguageDefaultsKey = "appLanguage"

    #if DEBUG
    /// Test hook: overrides on-device language support so prompt/validator behavior is
    /// deterministic without a real model. `nil` = query the real model.
    nonisolated(unsafe) static var modelSupportsLanguageOverride: ((String) -> Bool)?
    #endif

    // MARK: - Parse

    static func parse(_ raw: String) -> MetricInsightPair {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawParts = normalized.contains("<SEP>")
            ? normalized.components(separatedBy: "<SEP>")
            : [normalized]

        var short = sanitize(rawParts.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var detail = rawParts.dropFirst()
            .map { sanitize($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedWhole = sanitize(normalized).trimmingCharacters(in: .whitespacesAndNewlines)

        if short.isEmpty { short = sanitizedWhole }
        if detail.isEmpty { detail = sanitizedWhole }

        if short.isEmpty {
            short = localizedString("Your trend is being analyzed.")
        }

        if detail.isEmpty {
            detail = localizedString("Keep logging consistently to get a clearer trend signal.")
        }

        return MetricInsightPair(shortText: short, detailedText: detail)
    }

    // MARK: - Sanitize

    static func sanitize(_ text: String) -> String {
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
        output = output.replacingOccurrences(of: "<SEP>", with: " ")
        output = output.replacingOccurrences(of: "As an AI", with: "", options: .caseInsensitive)
        output = output.replacingOccurrences(of: "Certainly,", with: "", options: .caseInsensitive)
        output = output.replacingOccurrences(of: "Here is", with: "", options: .caseInsensitive)
        output = output.replacingOccurrences(of: "Here's", with: "", options: .caseInsensitive)
        // Localized preambles the model occasionally prepends in non-English output.
        output = output.replacingOccurrences(of: "Oczywiście,", with: "", options: .caseInsensitive)
        output = output.replacingOccurrences(of: "Oto ", with: "", options: .caseInsensitive)
        output = output.replacingOccurrences(of: "Bien sûr,", with: "", options: .caseInsensitive)
        output = output.replacingOccurrences(of: "Voici ", with: "", options: .caseInsensitive)
        output = output.replacingOccurrences(of: "Natürlich,", with: "", options: .caseInsensitive)
        output = output.replacingOccurrences(of: "Hier ist ", with: "", options: .caseInsensitive)
        // Strip URLs
        if let urlRegex = try? NSRegularExpression(pattern: "https?://\\S+", options: .caseInsensitive) {
            output = urlRegex.stringByReplacingMatches(in: output, range: NSRange(output.startIndex..., in: output), withTemplate: "")
        }
        // Strip phone numbers. Narrowed from a previous pattern that also matched ordinary
        // numeric content (e.g. "150-250", "8,000 steps", "lost 0.8 kg") and corrupted the
        // most useful part of an insight. Now requires a phone-like shape: an optional "+"
        // country prefix, or three or more digit groups in a row.
        if let phoneRegex = try? NSRegularExpression(pattern: "(?:\\+\\d{1,3}[\\s-])?\\d{2,4}(?:[\\s-]\\d{2,4}){2,}", options: []) {
            output = phoneRegex.stringByReplacingMatches(in: output, range: NSRange(output.startIndex..., in: output), withTemplate: "")
        }
        while output.contains("  ") {
            output = output.replacingOccurrences(of: "  ", with: " ")
        }
        while output.contains("\n\n\n") {
            output = output.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return output
    }

    // MARK: - Question Input

    /// Sanitize a follow-up question before passing it to the language model.
    /// Limits length and strips control characters to reduce prompt-injection surface.
    static func sanitizeQuestion(_ question: String) -> String {
        let stripped = question
            .components(separatedBy: .controlCharacters).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(stripped.prefix(500))
    }

    // MARK: - User Name

    static func sanitizeUserName(_ name: String) -> String {
        let stripped = name
            .components(separatedBy: .newlines).joined(separator: " ")
            .components(separatedBy: .controlCharacters).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(stripped.prefix(50))
    }

    // MARK: - Prompt Builders

    static func buildPrompt(for input: MetricInsightInput) -> String {
        var lines: [String] = [
            "Metric: \(input.metricTitle)",
            "Measurement type: \(input.measurementContext)",
            "Latest value: \(input.latestValueText)",
            "Aggregated analysis window: \(input.timeframeLabel)",
            "Number of samples in analysis window: \(input.sampleCount)"
        ]

        if let name = input.userName {
            lines.insert("User name: \(sanitizeUserName(name))", at: 1)
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
        lines.append("Identify the strongest trend signal first.")
        lines.append("If short-term and longer-term windows differ, mention whether momentum is accelerating, slowing, or just noisy.")
        lines.append("Treat stable data as a meaningful consistency signal when changes are small.")
        lines.append("Do not infer causes that are not supported by the data.")
        lines.append("Do not predict or mention a projected goal date. Goal prediction is handled separately.")
        lines.append("Write the insight using second person.")
        lines.append("The headline must reference at least one specific number from the data above.")
        lines.append("Only use numbers that appear in the data above; never invent values.")
        lines.append(responseLanguageDirective())

        return lines.joined(separator: "\n")
    }

    static func buildHealthPrompt(for input: HealthInsightInput) -> String {
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

        lines.append("")
        lines.append("Task:")
        lines.append("Connect the signals instead of listing them one by one.")
        lines.append("If weight, waist, body fat, and lean mass suggest body recomposition, say it clearly.")
        lines.append("If weight-based and waist-based indicators tell a different story, call that out as a subtle signal.")
        lines.append("If the pattern is mostly stable, explain why that stability is still useful.")
        lines.append("Finish with one concrete focus for the next 7 days.")
        lines.append("Only use numbers that appear in the data above; never invent values.")
        lines.append("Use 2 to 5 sentences total.")
        lines.append(responseLanguageDirective())
        return lines.joined(separator: "\n")
    }

    static func buildSectionPrompt(for input: SectionInsightInput) -> String {
        var lines: [String] = [
            "Section ID: \(input.sectionID)",
            "Section title: \(input.sectionTitle)"
        ]

        if let name = input.userName {
            lines.append("User name: \(sanitizeUserName(name))")
        }

        lines.append("")
        lines.append("Section data:")
        lines.append(contentsOf: input.contextLines)
        lines.append("")
        lines.append("Task:")
        lines.append("Lead with the strongest signal in this section.")
        lines.append("Mention one non-obvious pattern, relation, or mismatch only if the data supports it.")
        lines.append(sectionTaskHint(for: input.sectionID))
        lines.append("If the section is broadly stable, frame that stability as useful consistency rather than empty progress.")
        lines.append("Keep the tone motivating, factual, and compact.")
        lines.append("Only use numbers that appear in the section data above; never invent values.")
        lines.append("Use 2 to 5 sentences total.")
        lines.append(responseLanguageDirective())

        return lines.joined(separator: "\n")
    }

    // MARK: - Instruction Builders

    /// Shared safety block reused across every prompt's instructions.
    private static let safetyBlock = """
    Safety rules:
    Do not provide medical diagnosis or medical advice.
    Do not mention diseases, mortality, or clinical "risk of" outcomes.
    Do not recommend supplements, medications, or extreme diets.
    If some data is missing or ambiguous, do not guess; omit that detail.
    Do not repeat placeholders like "unknown", "n/a", or "not enough data".
    Do not use markdown, hashtags, bullets, quotes, or meta text (e.g., "As an AI...").
    """

    static func metricInstructions() -> String {
        """
        You are a calm, supportive health-tracking coach.
        Keep the tone non-judgmental, practical, concise, and quietly motivating.
        Address the user directly in second person. Never write in third person about the user.

        \(safetyBlock)

        Content rules:
        The prompt includes a "Measurement type" field. Use it to choose wording:
        - "body circumference" → describe size, girth, or measurements; NEVER use "tall" or height words.
        - "height (linear, vertical)" → only here may you use "tall" or similar.
        - "body weight" → describe weight in kg or lbs.
        Use the provided goal direction if present; otherwise treat the default favorable direction as a weak hint, not a certainty.
        Lead with the strongest supported signal, not a generic summary.
        A sentence that could appear unchanged in any other user's insight is too generic — rewrite it around a specific number from the data.
        If short-term and longer-term windows differ, say whether momentum is picking up, slowing, reversing, or just noisy.
        If changes are small, frame stability as meaningful consistency rather than fake urgency.
        Never claim muscle gain, fat loss, or a plateau unless the data directly supports that wording.

        Field guidance:
        headline: one punchy sentence, at most ~10 words, that names a specific number.
        detail: 2 to 4 short sentences, at most ~60 words, including one comparison across available trend windows, one concrete action for the next 7 days, and — if a goal is present — progress so far plus whether the pace looks aligned, too slow, or off-track.

        \(metricExamples())
        """
    }

    static func healthInstructions() -> String {
        """
        You are a supportive health and fitness coach.
        Address the user directly in second person. Never write in third person about the user.
        Summarize current state, recent changes, and trend direction by connecting the signals instead of listing them.
        Prefer body-composition interpretations such as weight vs waist, body fat vs lean mass, or scale weight vs waist-based indicators when the data supports that.
        If the data is broadly stable, explain why that stability is still useful.
        Include one concrete focus area and one practical next step.
        Keep it warm, factual, and non-alarming; avoid judgmental labels or appearance shaming.
        A sentence that could apply to any user unchanged is too generic — anchor it to a specific number.

        \(safetyBlock)

        Length: 3 to 4 short sentences in one paragraph, at most ~70 words.

        \(healthExamples())
        """
    }

    static func sectionInstructions() -> String {
        """
        You are a concise fitness and body-tracking coach.
        Address the user directly in second person. Never write in third person about the user.
        Summarize the current state from the provided section data.
        Connect related metrics instead of reciting them one by one.
        Lead with the strongest supported pattern.
        If the data shows a subtle relation, mismatch, or hidden signal, mention it briefly.
        If the data is broadly stable, treat that as a meaningful consistency signal.
        Mention one practical next step for the next 7 days.

        \(safetyBlock)

        Length: 2 to 4 short sentences in one paragraph, at most ~70 words.

        \(sectionExamples())
        """
    }

    // MARK: - Few-shot Examples (language-aware)

    /// Examples are given in the response language so a small on-device model isn't asked to
    /// translate English few-shots on the fly. Languages without a tailored set fall back to
    /// English examples plus the explicit "Respond in <language>" directive in the prompt.
    private static func metricExamples() -> String {
        switch effectiveResponseLanguageCode {
        case "pl":
            return """
            Przykład 1 (typowy):
            headline: Spadek o 1,2 kg w 30 dni.
            detail: 30-dniowy spadek 1,2 kg wyprzedza płaskie ostatnie 14 dni, więc tempo właśnie rośnie. Dodaj w tym tygodniu jeden dodatkowy spacer. Do celu zostało 2,3 kg, a tempo wygląda solidnie.

            Przykład 2 (plateau / mało danych):
            headline: Stabilnie w okolicy 81 kg.
            detail: Ostatnie 14 i 30 dni zmieniło się o mniej niż 0,3 kg, więc jesteś stabilny, a nie w zastoju. Utrzymaj rutynę i notuj codziennie, aby wyostrzyć sygnał.

            Unikaj tego:
            headline (zbyt ogólny): Tak trzymaj!
            Zamiast tego nazwij liczbę: "Talia mniejsza o 1 cm w 30 dni."
            """
        default:
            return """
            Example 1 (typical):
            headline: Down 1.2 kg over 30 days.
            detail: Your 30-day drop of 1.2 kg outpaces the flat last 14 days, so momentum is fresh. Add one extra walk this week. You're 2.3 kg from goal and the pace looks solid.

            Example 2 (plateau / sparse):
            headline: Holding steady near 81 kg.
            detail: The last 14 and 30 days both moved under 0.3 kg, so you're stable rather than stalled. Lock in the routine and log daily this week to sharpen the signal.

            Avoid this:
            headline (too generic): Keep up the great work!
            Instead, name the number: "Waist down 1 cm in 30 days."
            """
        }
    }

    private static func healthExamples() -> String {
        switch effectiveResponseLanguageCode {
        case "pl":
            return """
            Przykład:
            Twoja waga utrzymuje się na poziomie 82 kg, a tkanka tłuszczowa nieznacznie spadła w ostatnim tygodniu. Stosunek talii do wzrostu jest w zdrowym zakresie, a masa beztłuszczowa dobrze utrzymana. Skup się w tym tygodniu na trzech treningach siłowych i utrzymaniu kroków powyżej 8000 dziennie.
            """
        default:
            return """
            Example:
            Your weight is holding steady at 82 kg with body fat down slightly over the past week. Your waist-to-height ratio sits in a healthy range and your lean mass is well maintained. Focus on three strength sessions this week and keeping daily steps above 8,000.
            """
        }
    }

    private static func sectionExamples() -> String {
        switch effectiveResponseLanguageCode {
        case "pl":
            return """
            Przykład:
            Talia spadła o 1 cm, a waga utrzymuje się na poziomie 80 kg — to sygnał rekompozycji, a nie zwykłego spadku. Utrzymaj treningi siłowe w tym tygodniu, by podtrzymać ten kierunek.
            """
        default:
            return """
            Example:
            Your waist is down 1 cm while weight holds at 80 kg — a recomposition signal rather than plain loss. Keep your strength sessions this week to maintain that direction.
            """
        }
    }

    // MARK: - Deterministic Fallbacks
    //
    // Used when generation fails, times out, is rejected by validation, or there isn't enough
    // data yet. Text is composed only from values already present in the input, so it can never
    // hallucinate. English templates double as the localization keys and degrade gracefully.

    static func fallbackMetric(for input: MetricInsightInput) -> MetricInsightPair {
        let value = input.latestValueText
        let delta = input.delta30DaysText ?? input.delta14DaysText ?? input.delta90DaysText ?? input.delta7DaysText
        if let delta {
            let short = String(format: localizedString("Latest %@ (%@ recently)."), value, delta)
            let detail = String(format: localizedString("Your latest reading is %@, a change of %@ over the recent window. Keep logging consistently to sharpen the trend."), value, delta)
            return MetricInsightPair(shortText: short, detailedText: detail)
        }
        let short = String(format: localizedString("Latest reading: %@."), value)
        let detail = String(format: localizedString("Your latest reading is %@. Add a few more entries to reveal a reliable trend."), value)
        return MetricInsightPair(shortText: short, detailedText: detail)
    }

    static func fallbackHealth(for input: HealthInsightInput) -> String {
        var parts: [String] = []
        if let w = input.latestWeightText { parts.append(w) }
        if let wa = input.latestWaistText { parts.append(wa) }
        if let bf = input.latestBodyFatText { parts.append(bf) }
        guard !parts.isEmpty else {
            return localizedString("Keep logging your measurements to unlock a health summary.")
        }
        return String(format: localizedString("Your latest readings: %@. Keep logging consistently to reveal how they trend together."), parts.joined(separator: ", "))
    }

    static func fallbackSection(for input: SectionInsightInput) -> String {
        localizedString("Keep logging consistently to surface patterns in this section.")
    }

    private static func responseLanguageDirective() -> String {
        switch effectiveResponseLanguageCode {
        case "pl":
            return "Respond in Polish."
        case "de":
            return "Respond in German."
        case "fr":
            return "Respond in French."
        case "es":
            return "Respond in Spanish."
        case "pt-BR":
            return "Respond in Brazilian Portuguese."
        default:
            return "Respond in English."
        }
    }

    /// The language the insight is actually written in: the requested app language when the
    /// on-device model supports it, otherwise English. (Apple Intelligence doesn't cover every
    /// app language — e.g. Polish — and asking for an unsupported language degrades quality.)
    static var effectiveResponseLanguageCode: String {
        let requested = resolvedAppLanguageCode
        if requested == "en" { return "en" }
        return modelSupportsLanguage(requested) ? requested : "en"
    }

    private static func modelSupportsLanguage(_ code: String) -> Bool {
        #if DEBUG
        if let override = modelSupportsLanguageOverride { return override(code) }
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let base = languageBase(code)
            return SystemLanguageModel.default.supportedLanguages.contains { language in
                language.languageCode?.identifier.lowercased() == base
            }
        }
        #endif
        // Can't confirm support → use English for any non-English request.
        return false
    }

    /// Maps an app language code to its base ISO 639 code for matching against the model.
    private static func languageBase(_ code: String) -> String {
        code == "pt-BR" ? "pt" : code
    }

    /// Effective response language code (e.g. "en", "pl"). Exposed for the validator, whose
    /// language-specific heuristics (contradiction check) only run for English — which is also
    /// the effective language whenever the model can't write the requested one.
    static var responseLanguageCode: String { effectiveResponseLanguageCode }

    /// Resolves current app language code without touching MainActor-isolated settings/localization types.
    private static var resolvedAppLanguageCode: String {
        let raw = UserDefaults.standard.string(forKey: appLanguageDefaultsKey) ?? "system"
        if raw == "system" {
            return resolvedSystemLanguageCode
        }
        if raw == "pt" {
            return "pt-BR"
        }
        switch raw {
        case "en", "pl", "es", "de", "fr", "pt-BR":
            return raw
        default:
            return "en"
        }
    }

    private static var resolvedSystemLanguageCode: String {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        if preferred.hasPrefix("pl") { return "pl" }
        if preferred.hasPrefix("es") { return "es" }
        if preferred.hasPrefix("de") { return "de" }
        if preferred.hasPrefix("fr") { return "fr" }
        if preferred.hasPrefix("pt") { return "pt-BR" }
        return "en"
    }

    private static var currentLocalizationBundle: Bundle {
        let code = resolvedAppLanguageCode
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    private static func localizedString(_ key: String) -> String {
        currentLocalizationBundle.localizedString(forKey: key, value: key, table: nil)
    }

    private static func sectionTaskHint(for sectionID: String) -> String {
        switch sectionID {
        case "measurements.metrics":
            return "Prefer cross-metric links such as weight vs waist, body fat vs lean mass, or short-term vs 30-day momentum."
        case "measurements.health":
            return "Prefer body-composition and health-marker links, and keep wording non-alarming."
        case "measurements.physique":
            return "Describe proportions, silhouette, or visual composition neutrally and without appearance shaming."
        case "home.bottom.summary":
            return "Synthesize across sections and pick one main takeaway plus one next focus."
        default:
            return "Focus on the clearest supported pattern."
        }
    }
}
