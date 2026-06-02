import XCTest
@testable import MeasureMe

final class MetricInsightOutputValidatorTests: XCTestCase {
    private var baselineLanguage: Any?

    override func setUp() {
        super.setUp()
        baselineLanguage = UserDefaults.standard.object(forKey: "appLanguage")
        UserDefaults.standard.set("en", forKey: "appLanguage")
    }

    override func tearDown() {
        if let baselineLanguage {
            UserDefaults.standard.set(baselineLanguage, forKey: "appLanguage")
        } else {
            UserDefaults.standard.removeObject(forKey: "appLanguage")
        }
        baselineLanguage = nil
        InsightTextProcessor.modelSupportsLanguageOverride = nil
        super.tearDown()
    }

    private func makeInput(
        latest: String = "80 kg",
        delta30: String? = "-1.2 kg",
        goal: String? = "2.3 kg away from goal"
    ) -> MetricInsightInput {
        MetricInsightInput(
            userName: nil,
            metricTitle: "Weight",
            measurementContext: "body weight",
            latestValueText: latest,
            timeframeLabel: "Last 90 days",
            sampleCount: 12,
            delta7DaysText: nil,
            delta14DaysText: nil,
            delta30DaysText: delta30,
            delta90DaysText: nil,
            goalStatusText: goal,
            goalDirectionText: "decrease",
            defaultFavorableDirectionText: "decrease"
        )
    }

    private func assertInvalid(_ result: MetricInsightOutputValidator.MetricResult, _ expected: AIInsightFallbackReason, file: StaticString = #filePath, line: UInt = #line) {
        switch result {
        case .valid:
            XCTFail("Expected .invalid(\(expected)) but got .valid", file: file, line: line)
        case .invalid(let reason):
            XCTAssertEqual(reason, expected, file: file, line: line)
        }
    }

    /// Co sprawdza: Poprawny insight (liczby z inputu + cyfra w headline) przechodzi.
    func testValidMetricPasses() {
        let pair = MetricInsightPair(
            shortText: "Down 1.2 kg over 30 days.",
            detailedText: "Your 30-day drop of 1.2 kg keeps momentum. Add one walk in the next 7 days. You're 2.3 kg from goal."
        )
        switch MetricInsightOutputValidator.validate(pair, input: makeInput()) {
        case .valid(let out):
            XCTAssertEqual(out.shortText, pair.shortText)
        case .invalid(let reason):
            XCTFail("Expected valid, got \(reason)")
        }
    }

    /// Co sprawdza: Liczba spoza inputu (halucynacja) jest odrzucana.
    func testHallucinatedNumberRejected() {
        let pair = MetricInsightPair(
            shortText: "Down 1.2 kg recently.",
            detailedText: "You dropped 5.5 kg, an invented figure that never appeared in the data."
        )
        assertInvalid(MetricInsightOutputValidator.validate(pair, input: makeInput()), .validationHallucinatedNumber)
    }

    /// Co sprawdza: Headline bez liczby (generyk) jest odrzucany.
    func testGenericHeadlineRejected() {
        let pair = MetricInsightPair(
            shortText: "Keep up the great work!",
            detailedText: "You're 2.3 kg from goal and the 30-day trend looks steady."
        )
        assertInvalid(MetricInsightOutputValidator.validate(pair, input: makeInput()), .validationNoSpecifics)
    }

    /// Co sprawdza: Niedozwolone słownictwo medyczne jest odrzucane.
    func testDisallowedLanguageRejected() {
        let pair = MetricInsightPair(
            shortText: "Down 1.2 kg over 30 days.",
            detailedText: "This change lowers your disease risk over the next 7 days."
        )
        assertInvalid(MetricInsightOutputValidator.validate(pair, input: makeInput()), .validationDisallowedLanguage)
    }

    /// Co sprawdza: Pusty headline/detail jest odrzucany.
    func testEmptyRejected() {
        let pair = MetricInsightPair(shortText: "  ", detailedText: "")
        assertInvalid(MetricInsightOutputValidator.validate(pair, input: makeInput()), .validationEmpty)
    }

    /// Co sprawdza: Sprzeczność kierunku (delta ujemna, tekst mówi "up") jest odrzucana (EN).
    func testContradictionRejected() {
        let pair = MetricInsightPair(
            shortText: "Trending up 1.2 kg.",
            detailedText: "Your weight is rising over the last 30 days; keep going for the next 7 days."
        )
        assertInvalid(MetricInsightOutputValidator.validate(pair, input: makeInput(delta30: "-1.2 kg")), .validationContradiction)
    }

    /// Co sprawdza: Gdy model WSPIERA polski, wyjście jest po polsku → contradiction-check (EN-only) pomijany.
    func testContradictionSkippedWhenModelSupportsPolish() {
        UserDefaults.standard.set("pl", forKey: "appLanguage")
        InsightTextProcessor.modelSupportsLanguageOverride = { _ in true }
        let pair = MetricInsightPair(
            shortText: "Trending up 1.2 kg.",
            detailedText: "Your weight is rising over the last 30 days; keep going for the next 7 days."
        )
        switch MetricInsightOutputValidator.validate(pair, input: makeInput(delta30: "-1.2 kg")) {
        case .valid:
            break // expected: effective language is Polish, contradiction heuristic is English-only
        case .invalid(let reason):
            XCTFail("Polish output should skip contradiction check, got \(reason)")
        }
    }

    /// Co sprawdza: Reguła — gdy model NIE wspiera polskiego, efektywnym językiem jest angielski,
    /// więc tekst po angielsku jest walidowany (contradiction-check działa).
    func testUnsupportedLanguageFallsBackToEnglishValidation() {
        UserDefaults.standard.set("pl", forKey: "appLanguage")
        InsightTextProcessor.modelSupportsLanguageOverride = { _ in false }
        XCTAssertEqual(InsightTextProcessor.effectiveResponseLanguageCode, "en")
        let pair = MetricInsightPair(
            shortText: "Trending up 1.2 kg.",
            detailedText: "Your weight is rising over the last 30 days; keep going for the next 7 days."
        )
        assertInvalid(MetricInsightOutputValidator.validate(pair, input: makeInput(delta30: "-1.2 kg")), .validationContradiction)
    }

    /// Co sprawdza: validateText odrzuca pusty / za długi tekst i przepuszcza poprawny.
    func testValidateText() {
        switch MetricInsightOutputValidator.validateText("   ", maxLength: 100) {
        case .invalid(let r): XCTAssertEqual(r, .validationEmpty)
        case .valid: XCTFail("empty should be invalid")
        }

        let long = String(repeating: "a", count: 200)
        switch MetricInsightOutputValidator.validateText(long, maxLength: 100) {
        case .invalid(let r): XCTAssertEqual(r, .validationLength)
        case .valid: XCTFail("over-long should be invalid")
        }

        switch MetricInsightOutputValidator.validateText("Your waist is down 1 cm this month.", maxLength: 100) {
        case .valid(let t): XCTAssertEqual(t, "Your waist is down 1 cm this month.")
        case .invalid(let r): XCTFail("valid text rejected: \(r)")
        }
    }

    /// Co sprawdza: Fallback metryczny jest osadzony w danych wejściowych (zawiera wartość).
    func testFallbackMetricGrounded() {
        let pair = InsightTextProcessor.fallbackMetric(for: makeInput(latest: "80 kg", delta30: "-1.2 kg"))
        XCTAssertTrue(pair.shortText.contains("80 kg"))
        XCTAssertTrue(pair.detailedText.contains("80 kg"))
        XCTAssertFalse(pair.detailedText.isEmpty)
    }
}
