import XCTest
@testable import MeasureMe

final class InsightTextProcessorTests: XCTestCase {

    // MARK: - parse()

    /// Co sprawdza: Poprawny split na short + detail z separatorem <SEP>
    /// Dlaczego: To glowny format odpowiedzi AI
    /// Kryteria: shortText i detailedText zawieraja odpowiednie czesci
    func testParse_withSEP() {
        let raw = "Weight trending down.\n<SEP>\nYou lost 0.8 kg in 30 days."
        let result = InsightTextProcessor.parse(raw)
        XCTAssertEqual(result.shortText, "Weight trending down.")
        XCTAssertEqual(result.detailedText, "You lost 0.8 kg in 30 days.")
    }

    /// Co sprawdza: Brak separatora — oba pola = caly tekst
    /// Dlaczego: AI moze nie uzyc separatora
    /// Kryteria: Oba pola identyczne
    func testParse_withoutSEP() {
        let raw = "Your weight is stable and consistent."
        let result = InsightTextProcessor.parse(raw)
        XCTAssertEqual(result.shortText, "Your weight is stable and consistent.")
        XCTAssertEqual(result.detailedText, "Your weight is stable and consistent.")
    }

    /// Co sprawdza: Pusty string daje fallback
    /// Dlaczego: Zabezpieczenie przed pustym wynikiem AI
    /// Kryteria: Fallback teksty ustawione
    func testParse_emptyString() {
        let result = InsightTextProcessor.parse("")
        XCTAssertEqual(result.shortText, "Your trend is being analyzed.")
        XCTAssertEqual(result.detailedText, "Keep logging consistently to get a clearer trend signal.")
    }

    /// Co sprawdza: Wiele separatorow
    /// Dlaczego: AI moze wstawic wiecej niz jeden <SEP>
    /// Kryteria: Short = pierwsza czesc, detail = reszta polaczona
    func testParse_multipleSEP() {
        let raw = "Headline.\n<SEP>\nPart one.\n<SEP>\nPart two."
        let result = InsightTextProcessor.parse(raw)
        XCTAssertEqual(result.shortText, "Headline.")
        XCTAssertTrue(result.detailedText.contains("Part one."))
        XCTAssertTrue(result.detailedText.contains("Part two."))
    }

    // MARK: - sanitize()

    /// Co sprawdza: Usuwanie markdown z tekstu
    /// Dlaczego: AI moze dodac formatowanie mimo instrukcji
    /// Kryteria: Brak znakow markdown w wyniku
    func testSanitize_removesMarkdown() {
        let input = "### Heading\n## Subheading\n**bold** __underline__ `code`"
        let result = InsightTextProcessor.sanitize(input)
        XCTAssertFalse(result.contains("###"))
        XCTAssertFalse(result.contains("##"))
        XCTAssertFalse(result.contains("**"))
        XCTAssertFalse(result.contains("__"))
        XCTAssertFalse(result.contains("`"))
    }

    /// Co sprawdza: Usuwanie bullet points
    /// Dlaczego: Instrukcje zabraniaja list — trzeba je usunac
    /// Kryteria: Bullets zamienione na newline bez markera
    func testSanitize_removesBullets() {
        let input = "Items:\n- first\n* second\n• third"
        let result = InsightTextProcessor.sanitize(input)
        XCTAssertFalse(result.contains("\n- "))
        XCTAssertFalse(result.contains("\n* "))
        XCTAssertFalse(result.contains("\n• "))
        XCTAssertTrue(result.contains("first"))
        XCTAssertTrue(result.contains("second"))
        XCTAssertTrue(result.contains("third"))
    }

    /// Co sprawdza: Usuwanie AI preambles
    /// Dlaczego: AI czesto dodaje frazy wstepne mimo instrukcji
    /// Kryteria: Frazy typu "As an AI", "Certainly," usuniete
    func testSanitize_removesAIPreambles() {
        let input = "As an AI, Certainly, Here is your insight. Here's more."
        let result = InsightTextProcessor.sanitize(input)
        XCTAssertFalse(result.lowercased().contains("as an ai"))
        XCTAssertFalse(result.lowercased().contains("certainly,"))
        XCTAssertFalse(result.lowercased().contains("here is"))
        XCTAssertFalse(result.lowercased().contains("here's"))
    }

    /// Co sprawdza: Usuwanie URL-i
    /// Dlaczego: AI nie powinno generowac linkow
    /// Kryteria: URL usuniety z tekstu
    func testSanitize_stripsURLs() {
        let input = "Check out https://example.com/path for more info."
        let result = InsightTextProcessor.sanitize(input)
        XCTAssertFalse(result.contains("https://"))
        XCTAssertTrue(result.contains("Check out"))
    }

    /// Co sprawdza: Usuwanie numerow telefonow
    /// Dlaczego: AI nie powinno generowac danych kontaktowych
    /// Kryteria: Numer usuniety
    func testSanitize_stripsPhoneNumbers() {
        let input = "Call +48 123 456 789 for help."
        let result = InsightTextProcessor.sanitize(input)
        XCTAssertFalse(result.contains("123 456 789"))
    }

    /// Co sprawdza: Kolaps wielokrotnych spacji
    /// Dlaczego: Sanityzacja moze zostawic podwojne spacje
    /// Kryteria: Brak podwojnych spacji i trojnych newlines
    func testSanitize_collapsesWhitespace() {
        let input = "Word   with    spaces.\n\n\nTriple newline."
        let result = InsightTextProcessor.sanitize(input)
        XCTAssertFalse(result.contains("  "))
        XCTAssertFalse(result.contains("\n\n\n"))
    }

    /// Co sprawdza: Czysty tekst bez zmian
    /// Dlaczego: Nie powinno modyfikowac poprawnego tekstu
    /// Kryteria: Wynik identyczny z wejsciem
    func testSanitize_cleanTextPassthrough() {
        let input = "Your weight is stable at 80 kg."
        let result = InsightTextProcessor.sanitize(input)
        XCTAssertEqual(result, input)
    }

    /// Co sprawdza: Usuwanie SHORT: i DETAIL: labelek
    /// Dlaczego: AI moze dodac etykiety sekcji
    /// Kryteria: Labele usuniete
    func testSanitize_removesShortDetailLabels() {
        let input = "SHORT: trending up\nDETAIL: more info here"
        let result = InsightTextProcessor.sanitize(input)
        XCTAssertFalse(result.contains("SHORT:"))
        XCTAssertFalse(result.contains("DETAIL:"))
        XCTAssertTrue(result.contains("trending up"))
        XCTAssertTrue(result.contains("more info here"))
    }

    // MARK: - sanitizeUserName()

    /// Co sprawdza: Normalne imie bez zmian
    func testSanitizeUserName_normal() {
        XCTAssertEqual(InsightTextProcessor.sanitizeUserName("Jacek"), "Jacek")
    }

    /// Co sprawdza: Imie z newlines — zamienione na spacje
    func testSanitizeUserName_withNewlines() {
        let result = InsightTextProcessor.sanitizeUserName("Jacek\nZieba")
        XCTAssertFalse(result.contains("\n"))
        XCTAssertTrue(result.contains("Jacek"))
        XCTAssertTrue(result.contains("Zieba"))
    }

    /// Co sprawdza: Imie z control characters — usuniete
    func testSanitizeUserName_withControlChars() {
        let result = InsightTextProcessor.sanitizeUserName("Jacek\u{0000}Test")
        XCTAssertFalse(result.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }))
    }

    /// Co sprawdza: Imie >50 znakow — obciete
    func testSanitizeUserName_tooLong() {
        let longName = String(repeating: "A", count: 100)
        let result = InsightTextProcessor.sanitizeUserName(longName)
        XCTAssertEqual(result.count, 50)
    }

    /// Co sprawdza: Pusty string
    func testSanitizeUserName_empty() {
        XCTAssertEqual(InsightTextProcessor.sanitizeUserName(""), "")
    }

    // MARK: - buildPrompt()

    /// Co sprawdza: Prompt ze wszystkimi polami wypelnionymi
    /// Dlaczego: Sprawdza czy wszystkie dane trafiaja do promptu
    /// Kryteria: Prompt zawiera wszystkie pola
    func testBuildPrompt_allFields() {
        let input = MetricInsightInput(
            userName: "Jacek",
            metricTitle: "Weight",
            latestValueText: "80 kg",
            timeframeLabel: "30 days",
            sampleCount: 15,
            delta7DaysText: "-0.3 kg",
            delta14DaysText: "-0.5 kg",
            delta30DaysText: "-1.2 kg",
            delta90DaysText: "-3.0 kg",
            goalStatusText: "77 kg target",
            goalDirectionText: "decrease",
            defaultFavorableDirectionText: "decrease"
        )
        let prompt = InsightTextProcessor.buildPrompt(for: input)
        XCTAssertTrue(prompt.contains("Metric: Weight"))
        XCTAssertTrue(prompt.contains("User name: Jacek"))
        XCTAssertTrue(prompt.contains("Latest value: 80 kg"))
        XCTAssertTrue(prompt.contains("14-day change: -0.5 kg"))
        XCTAssertTrue(prompt.contains("30-day change: -1.2 kg"))
        XCTAssertTrue(prompt.contains("90-day change: -3.0 kg"))
        XCTAssertTrue(prompt.contains("Goal status: 77 kg target"))
        XCTAssertTrue(prompt.contains("Goal direction: decrease"))
    }

    /// Co sprawdza: Prompt z opcjonalnymi polami nil
    /// Dlaczego: Pominac opcjonalne dane jesli brak
    /// Kryteria: Brak linii z opcjonalnymi danymi
    func testBuildPrompt_optionalFieldsNil() {
        let input = MetricInsightInput(
            userName: nil,
            metricTitle: "Waist",
            latestValueText: "85 cm",
            timeframeLabel: "14 days",
            sampleCount: 5,
            delta7DaysText: nil,
            delta14DaysText: nil,
            delta30DaysText: nil,
            delta90DaysText: nil,
            goalStatusText: nil,
            goalDirectionText: nil,
            defaultFavorableDirectionText: "decrease"
        )
        let prompt = InsightTextProcessor.buildPrompt(for: input)
        XCTAssertTrue(prompt.contains("Metric: Waist"))
        XCTAssertFalse(prompt.contains("User name:"))
        XCTAssertFalse(prompt.contains("14-day change:"))
        XCTAssertFalse(prompt.contains("Goal status:"))
    }

    /// Co sprawdza: Fallback delta7 gdy delta14 nil
    /// Dlaczego: delta14DaysText ?? delta7DaysText logika
    /// Kryteria: 14-day change uzywa delta7 jako fallback
    func testBuildPrompt_delta7Fallback() {
        let input = MetricInsightInput(
            userName: nil,
            metricTitle: "Weight",
            latestValueText: "80 kg",
            timeframeLabel: "7 days",
            sampleCount: 3,
            delta7DaysText: "-0.2 kg",
            delta14DaysText: nil,
            delta30DaysText: nil,
            delta90DaysText: nil,
            goalStatusText: nil,
            goalDirectionText: nil,
            defaultFavorableDirectionText: "decrease"
        )
        let prompt = InsightTextProcessor.buildPrompt(for: input)
        XCTAssertTrue(prompt.contains("14-day change: -0.2 kg"))
    }

    // MARK: - buildHealthPrompt()

    /// Co sprawdza: Health prompt ze wszystkimi polami
    func testBuildHealthPrompt_allFields() {
        let input = HealthInsightInput(
            userName: "Jacek",
            ageText: "35",
            genderText: "Male",
            latestWeightText: "82 kg",
            latestWaistText: "85 cm",
            latestBodyFatText: "18%",
            latestLeanMassText: "67 kg",
            weightDelta7dText: "-0.5 kg",
            waistDelta7dText: "-1 cm",
            coreWHtRText: "0.47",
            coreBMIText: "24.2",
            coreRFMText: "21%"
        )
        let prompt = InsightTextProcessor.buildHealthPrompt(for: input)
        XCTAssertTrue(prompt.contains("User name: Jacek"))
        XCTAssertTrue(prompt.contains("Age: 35"))
        XCTAssertTrue(prompt.contains("Weight: 82 kg"))
        XCTAssertTrue(prompt.contains("WHtR: 0.47"))
    }

    /// Co sprawdza: Health prompt z czesciowymi danymi
    func testBuildHealthPrompt_partialFields() {
        let input = HealthInsightInput(
            userName: nil,
            ageText: nil,
            genderText: nil,
            latestWeightText: "80 kg",
            latestWaistText: nil,
            latestBodyFatText: nil,
            latestLeanMassText: nil,
            weightDelta7dText: nil,
            waistDelta7dText: nil,
            coreWHtRText: nil,
            coreBMIText: "24.0",
            coreRFMText: nil
        )
        let prompt = InsightTextProcessor.buildHealthPrompt(for: input)
        XCTAssertTrue(prompt.contains("Weight: 80 kg"))
        XCTAssertTrue(prompt.contains("BMI: 24.0"))
        XCTAssertFalse(prompt.contains("User name:"))
        XCTAssertFalse(prompt.contains("User profile:"))
        XCTAssertFalse(prompt.contains("Last 7 days:"))
    }

    // MARK: - buildSectionPrompt()

    /// Co sprawdza: Section prompt z danymi
    func testBuildSectionPrompt() {
        let input = SectionInsightInput(
            sectionID: "measurements",
            sectionTitle: "Body Measurements",
            userName: "Jacek",
            contextLines: ["Waist: 85 cm (-1 cm)", "Hips: 95 cm (stable)"]
        )
        let prompt = InsightTextProcessor.buildSectionPrompt(for: input)
        XCTAssertTrue(prompt.contains("Section ID: measurements"))
        XCTAssertTrue(prompt.contains("Section title: Body Measurements"))
        XCTAssertTrue(prompt.contains("User name: Jacek"))
        XCTAssertTrue(prompt.contains("Waist: 85 cm (-1 cm)"))
        XCTAssertTrue(prompt.contains("Hips: 95 cm (stable)"))
    }
}
