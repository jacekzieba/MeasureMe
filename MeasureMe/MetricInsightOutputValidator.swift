import Foundation

/// Post-generation gate for AI insights. Mirrors `AINotificationOutputValidator`: rejects empty,
/// over-long, unsafe, or hallucinated output so a deterministic fallback can take over.
/// Rejection is intentional — we never silently ship model text that fails a check.
nonisolated enum MetricInsightOutputValidator {

    enum MetricResult {
        case valid(MetricInsightPair)
        case invalid(AIInsightFallbackReason)
    }

    enum TextResult {
        case valid(String)
        case invalid(AIInsightFallbackReason)
    }

    // Generous upper bounds: the model is steered to be short via @Guide, but languages vary in
    // length, so we only block runaway output, not normal-but-long sentences.
    private static let maxHeadlineLength = 120
    private static let maxDetailLength = 600

    // MARK: - Metric

    static func validate(_ pair: MetricInsightPair, input: MetricInsightInput) -> MetricResult {
        let headline = pair.shortText.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = pair.detailedText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !headline.isEmpty, !detail.isEmpty else {
            return .invalid(.validationEmpty)
        }
        guard headline.count <= maxHeadlineLength, detail.count <= maxDetailLength else {
            return .invalid(.validationLength)
        }
        guard !containsDisallowedLanguage(headline), !containsDisallowedLanguage(detail) else {
            return .invalid(.validationDisallowedLanguage)
        }

        // Anti-generic: a headline with no number is the hallmark of filler ("Keep up the good work").
        guard containsDigit(headline) else {
            return .invalid(.validationNoSpecifics)
        }

        // Anti-hallucination: every number in the output must be traceable to the input
        // (or a structural window/count number we always allow).
        let allowed = allowedNumbers(for: input)
        let used = numericTokens(in: "\(headline) \(detail)")
        guard used.isSubset(of: allowed) else {
            return .invalid(.validationHallucinatedNumber)
        }

        // Anti-contradiction: the stated direction must match the sign of the strongest delta.
        // Direction lexicon is English-only, so this check is skipped for other languages.
        if InsightTextProcessor.responseLanguageCode == "en",
           contradictsTrend(text: "\(headline) \(detail)", input: input) {
            return .invalid(.validationContradiction)
        }

        return .valid(MetricInsightPair(shortText: headline, detailedText: detail))
    }

    // MARK: - Plain text (health / section)

    static func validateText(_ text: String, maxLength: Int) -> TextResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid(.validationEmpty) }
        guard trimmed.count <= maxLength else { return .invalid(.validationLength) }
        guard !containsDisallowedLanguage(trimmed) else { return .invalid(.validationDisallowedLanguage) }
        return .valid(trimmed)
    }

    // MARK: - Helpers

    private static func containsDisallowedLanguage(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let disallowed = [
            "diagnosis", "disease", "mortality", "supplement", "medication",
            "diagnoza", "choroba", "śmiertelność", "suplement", "lek"
        ]
        return disallowed.contains { lowercased.contains($0) }
    }

    private static func containsDigit(_ text: String) -> Bool {
        text.contains { $0.isNumber }
    }

    /// Numbers we always permit even if not in the input: trend-window sizes and small counts
    /// the model naturally references ("next 7 days", "three sessions").
    private static let structuralNumbers: Set<String> = ["1", "2", "3", "7", "14", "30", "90"]

    private static func allowedNumbers(for input: MetricInsightInput) -> Set<String> {
        var sources: [String] = [input.latestValueText]
        sources.append(contentsOf: [
            input.delta7DaysText, input.delta14DaysText,
            input.delta30DaysText, input.delta90DaysText,
            input.goalStatusText
        ].compactMap { $0 })
        return numericTokens(in: sources.joined(separator: " ")).union(structuralNumbers)
    }

    /// Extracts numeric tokens, normalized so "+1,2", "1.2", "-1.2" all compare equal on
    /// magnitude. Comma is treated as a decimal separator (Polish/German formatting).
    private static func numericTokens(in text: String) -> Set<String> {
        let pattern = #"\d+(?:[.,]\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Set(regex.matches(in: text, range: range).compactMap { match -> String? in
            guard let r = Range(match.range, in: text) else { return nil }
            return normalizeNumber(String(text[r]))
        })
    }

    private static func normalizeNumber(_ raw: String) -> String {
        var value = raw.replacingOccurrences(of: ",", with: ".")
        // Drop a trailing ".0" and trailing zeros so "1.20" == "1.2" and "30.0" == "30".
        if value.contains(".") {
            while value.hasSuffix("0") { value.removeLast() }
            if value.hasSuffix(".") { value.removeLast() }
        }
        return value
    }

    private static func contradictsTrend(text: String, input: MetricInsightInput) -> Bool {
        let strongestDelta = input.delta30DaysText ?? input.delta90DaysText
            ?? input.delta14DaysText ?? input.delta7DaysText
        guard let delta = strongestDelta, let sign = deltaSign(delta) else { return false }

        let lower = text.lowercased()
        let saysUp = ["increas", "trending up", " up ", "rising", "gaining", "higher", "went up"]
            .contains { lower.contains($0) }
        let saysDown = ["decreas", "trending down", " down ", "dropp", "falling", "lower", "losing", " lost ", "went down"]
            .contains { lower.contains($0) }

        if sign > 0 && saysDown && !saysUp { return true }
        if sign < 0 && saysUp && !saysDown { return true }
        return false
    }

    /// Returns +1, -1, or 0 for a delta string like "+1.2 kg" / "-0.5 cm" / "0 %".
    private static func deltaSign(_ delta: String) -> Int? {
        if delta.contains("+") { return 1 }
        if delta.contains("-") || delta.contains("−") { return -1 }
        // No explicit sign: treat a non-zero leading number as ambiguous → skip the check.
        return 0
    }
}
