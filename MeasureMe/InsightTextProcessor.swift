import Foundation

nonisolated enum InsightTextProcessor {

    // MARK: - Parse

    static func parse(_ raw: String) -> MetricInsightPair {
        let trimmed = sanitize(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.components(separatedBy: "\n<SEP>\n")

        var short = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var detail = parts.dropFirst().joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)

        if short.isEmpty { short = trimmed }
        if detail.isEmpty { detail = trimmed }

        if short.isEmpty {
            short = "Your trend is being analyzed."
        }

        if detail.isEmpty {
            detail = "Keep logging consistently to get a clearer trend signal."
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
        lines.append("Write the two-paragraph insight using second person.")

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

        return lines.joined(separator: "\n")
    }
}
