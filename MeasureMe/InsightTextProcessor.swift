import Foundation

nonisolated enum InsightTextProcessor {

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
            short = AppLocalization.string("Your trend is being analyzed.")
        }

        if detail.isEmpty {
            detail = AppLocalization.string("Keep logging consistently to get a clearer trend signal.")
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
        // Strip URLs
        if let urlRegex = try? NSRegularExpression(pattern: "https?://\\S+", options: .caseInsensitive) {
            output = urlRegex.stringByReplacingMatches(in: output, range: NSRange(output.startIndex..., in: output), withTemplate: "")
        }
        // Strip phone numbers (7+ digits with optional separators/prefix)
        if let phoneRegex = try? NSRegularExpression(pattern: "(?:\\+\\d{1,3}[\\s-]?)?(?:\\(?\\d{2,4}\\)?[\\s-]?){1,3}\\d{3,4}", options: []) {
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
        lines.append("Write the insight using second person. Use 2 to 5 sentences total.")
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
        lines.append("Use 2 to 5 sentences total.")
        lines.append(responseLanguageDirective())

        return lines.joined(separator: "\n")
    }

    private static func responseLanguageDirective() -> String {
        switch AppLocalization.currentLanguage {
        case .pl:
            return "Respond in Polish."
        case .de:
            return "Respond in German."
        case .fr:
            return "Respond in French."
        case .system:
            switch AppLanguage.resolvedSystemLanguage {
            case .pl:
                return "Respond in Polish."
            case .de:
                return "Respond in German."
            case .fr:
                return "Respond in French."
            case .en, .es, .ptBR, .system:
                return "Respond in English."
            }
        case .en, .es, .ptBR:
            return "Respond in English."
        }
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
