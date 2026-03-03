/// Cel testow: Weryfikuje bezposrednio SettingsImporter — parseCSVLine, parseMetricsCSV,
///   parseGoalsCSV, insertSamples (merge/replace), insertGoals (upsert) i importData end-to-end.
/// Dlaczego to wazne: CSVImportTests.swift uzywalo lokalnych kopii funkcji parsujacych,
///   wiec zmiany w SettingsImporter.swift nie byly wczesniej wykrywane przez testy.
/// Kryteria zaliczenia: Kazda sciezka kodu w nonisolated i @MainActor func jest pokryta
///   testami wywolujacymi SettingsImporter bezposrednio.

import XCTest
import SwiftData
@testable import MeasureMe

// MARK: - Helpers

private func makeTempFile(name: String, content: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    try? content.write(to: url, atomically: true, encoding: .utf8)
    return url
}

private let isoFull: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

// MARK: - parseCSVLine (SettingsImporter — nie lokalna kopia)

final class ImporterParseCSVLineTests: XCTestCase {

    /// Co sprawdza: Prosta linia — wywołanie SettingsImporter.parseCSVLine (nie lokalna kopia).
    func testSimpleLineParsed() {
        XCTAssertEqual(
            SettingsImporter.parseCSVLine("weight,80.5,kg,2025-01-01T08:00:00Z"),
            ["weight", "80.5", "kg", "2025-01-01T08:00:00Z"]
        )
    }

    /// Co sprawdza: Pole w cudzysłowach z przecinkiem jest unquotowane.
    func testQuotedCommaField() {
        XCTAssertEqual(
            SettingsImporter.parseCSVLine("\"Lean, Mass\",80.5,kg"),
            ["Lean, Mass", "80.5", "kg"]
        )
    }

    /// Co sprawdza: Podwójny cudzysłów (\"\") jest unescapowany do pojedynczego.
    func testDoubleQuoteEscapedToSingle() {
        XCTAssertEqual(
            SettingsImporter.parseCSVLine("\"say \"\"hi\"\"\",test"),
            ["say \"hi\"", "test"]
        )
    }

    /// Co sprawdza: Puste pola (np. opcjonalne start_value) są parsowane jako "".
    func testEmptyFieldsAreEmpty() {
        XCTAssertEqual(
            SettingsImporter.parseCSVLine("weight,decrease,50,,"),
            ["weight", "decrease", "50", "", ""]
        )
    }

    /// Co sprawdza: \r (CR) jest pomijany — obsługa CRLF line endings.
    func testCarriageReturnIgnored() {
        XCTAssertEqual(
            SettingsImporter.parseCSVLine("weight\r,80.5"),
            ["weight", "80.5"]
        )
    }

    /// Co sprawdza: Pusty string → jeden pusty element.
    func testEmptyLineReturnsSingleEmptyField() {
        XCTAssertEqual(SettingsImporter.parseCSVLine(""), [""])
    }
}

// MARK: - parseMetricsCSV (bezpośrednie wywołanie SettingsImporter)

final class ImporterParseMetricsCSVTests: XCTestCase {

    private let header = "metric_id,metric,value_metric,unit_metric,value,unit,timestamp"

    /// Co sprawdza: Poprawny wiersz → ParsedSampleRow z kindRaw, value, date.
    func testValidRowParsed() {
        let csv = "\(header)\nweight,Weight,80.5000,kg,80.50,kg,2025-01-03T08:00:00.000Z"
        let url = makeTempFile(name: "imp-metrics-valid-\(UUID()).csv", content: csv)
        let result = SettingsImporter.parseMetricsCSV(url: url)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(result.rows[0].kindRaw, "weight")
        XCTAssertEqual(result.rows[0].value, 80.5, accuracy: 0.001)
    }

    /// Co sprawdza: value_metric z przecinkiem dziesiętnym jest akceptowany.
    func testValueMetricWithCommaDecimalIsAccepted() {
        let csv = "\(header)\nweight,Weight,\"80,5000\",kg,80.50,kg,2025-01-03T08:00:00.000Z"
        let url = makeTempFile(name: "imp-metrics-comma-decimal-\(UUID()).csv", content: csv)
        let result = SettingsImporter.parseMetricsCSV(url: url)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(result.rows[0].value, 80.5, accuracy: 0.001)
    }

    /// Co sprawdza: Nieznany metric_id → wiersz skipped, rows puste.
    func testUnknownMetricIdSkipped() {
        let csv = "\(header)\nnot_a_metric,Unknown,80.0,kg,80.0,kg,2025-01-03T08:00:00.000Z"
        let url = makeTempFile(name: "imp-metrics-unkn-\(UUID()).csv", content: csv)
        let result = SettingsImporter.parseMetricsCSV(url: url)
        XCTAssertEqual(result.rows.count, 0)
        XCTAssertEqual(result.skipped, 1)
    }

    /// Co sprawdza: Nieprawidłowy timestamp → wiersz skipped.
    func testBadTimestampSkipped() {
        let csv = "\(header)\nweight,Weight,80.0,kg,80.0,kg,not-a-date"
        let url = makeTempFile(name: "imp-metrics-badts-\(UUID()).csv", content: csv)
        let result = SettingsImporter.parseMetricsCSV(url: url)
        XCTAssertEqual(result.rows.count, 0)
        XCTAssertEqual(result.skipped, 1)
    }

    /// Co sprawdza: Nieprawidłowa wartość liczbowa → wiersz skipped.
    func testNonNumericValueSkipped() {
        let csv = "\(header)\nweight,Weight,abc,kg,abc,kg,2025-01-03T08:00:00.000Z"
        let url = makeTempFile(name: "imp-metrics-badval-\(UUID()).csv", content: csv)
        let result = SettingsImporter.parseMetricsCSV(url: url)
        XCTAssertEqual(result.rows.count, 0)
        XCTAssertEqual(result.skipped, 1)
    }

    /// Co sprawdza: Tylko nagłówek → zero wierszy, zero skipped.
    func testHeaderOnlyFile() {
        let url = makeTempFile(name: "imp-metrics-hdr-\(UUID()).csv", content: header)
        let result = SettingsImporter.parseMetricsCSV(url: url)
        XCTAssertEqual(result.rows.count, 0)
        XCTAssertEqual(result.skipped, 0)
    }

    /// Co sprawdza: Brak kolumny metric_id w nagłówku → pusty wynik (guard header columns).
    func testMissingMetricIdColumnReturnsEmpty() {
        let csv = "metric,value_metric,unit_metric,value,unit,timestamp\nWeight,80.0,kg,80.0,kg,2025-01-03T08:00:00.000Z"
        let url = makeTempFile(name: "imp-metrics-noid-\(UUID()).csv", content: csv)
        let result = SettingsImporter.parseMetricsCSV(url: url)
        XCTAssertEqual(result.rows.count, 0)
        XCTAssertEqual(result.skipped, 0, "Brak wymaganej kolumny → zero skipped (guard, nie pętla)")
    }

    /// Co sprawdza: ISO-8601 bez milisekund (basic) jest też akceptowany (fallback formatter).
    func testISO8601WithoutFractionalSecondsAccepted() {
        let csv = "\(header)\nweight,Weight,80.0,kg,80.0,kg,2025-01-03T08:00:00Z"
        let url = makeTempFile(name: "imp-metrics-iso-\(UUID()).csv", content: csv)
        let result = SettingsImporter.parseMetricsCSV(url: url)
        XCTAssertEqual(result.rows.count, 1, "Basic ISO-8601 (bez milisekund) powinien być akceptowany")
    }

    /// Co sprawdza: Wiersze mieszane (dobre i złe) → poprawne liczniki rows i skipped.
    func testMixedRowsCountedCorrectly() {
        let csv = """
        \(header)
        weight,Weight,80.0,kg,80.0,kg,2025-01-03T08:00:00.000Z
        not_a_metric,Unk,5,kg,5,kg,2025-01-03T09:00:00.000Z
        waist,Waist,85.0,cm,85.0,cm,2025-01-04T08:00:00.000Z
        """
        let url = makeTempFile(name: "imp-metrics-mixed-\(UUID()).csv", content: csv)
        let result = SettingsImporter.parseMetricsCSV(url: url)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.skipped, 1)
    }

    /// Co sprawdza: Data jest poprawnie parsowana (epoch round-trip z dokładnością 1 sekundy).
    func testDateParsedCorrectly() {
        let expectedDate = ISO8601DateFormatter().date(from: "2025-06-15T10:00:00Z")!
        let csv = "\(header)\nweight,Weight,80.0,kg,80.0,kg,2025-06-15T10:00:00.000Z"
        let url = makeTempFile(name: "imp-metrics-date-\(UUID()).csv", content: csv)
        let result = SettingsImporter.parseMetricsCSV(url: url)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0].date.timeIntervalSince1970, expectedDate.timeIntervalSince1970, accuracy: 1.0)
    }
}

// MARK: - parseGoalsCSV (bezpośrednie wywołanie SettingsImporter)

final class ImporterParseGoalsCSVTests: XCTestCase {

    private let header = "metric_id,metric,direction,target_value_metric,target_unit_metric,target_value,target_unit,start_value_metric,start_value,start_date,created_date"

    /// Co sprawdza: Poprawny cel z wszystkimi polami → ParsedGoalRow z wszystkimi wartościami.
    func testValidGoalWithAllFieldsParsed() {
        let csv = "\(header)\nweight,Weight,decrease,75.0000,kg,75.00,kg,80.0000,80.00,2024-12-01T08:00:00.000Z,2025-01-01T08:00:00.000Z"
        let url = makeTempFile(name: "imp-goals-valid-\(UUID()).csv", content: csv)
        let result = SettingsImporter.parseGoalsCSV(url: url)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0].kindRaw, "weight")
        XCTAssertEqual(result.rows[0].direction, "decrease")
        XCTAssertEqual(result.rows[0].targetValue, 75.0, accuracy: 0.001)
        XCTAssertEqual(result.rows[0].startValue, 80.0)
        XCTAssertNotNil(result.rows[0].startDate)
    }

    /// Co sprawdza: target/start_value_metric z przecinkiem dziesiętnym są akceptowane.
    func testGoalMetricValuesWithCommaDecimalAreAccepted() {
        let csv = "\(header)\nweight,Weight,decrease,\"75,0000\",kg,75.00,kg,\"80,0000\",80.00,2024-12-01T08:00:00.000Z,2025-01-01T08:00:00.000Z"
        let url = makeTempFile(name: "imp-goals-comma-decimal-\(UUID()).csv", content: csv)
        let result = SettingsImporter.parseGoalsCSV(url: url)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(result.rows[0].targetValue, 75.0, accuracy: 0.001)
        XCTAssertEqual(result.rows[0].startValue, 80.0, accuracy: 0.001)
    }

    /// Co sprawdza: Cel bez pól opcjonalnych (puste start) → startValue i startDate są nil.
    func testGoalWithoutOptionalFieldsParsed() {
        let csv = "\(header)\nwaist,Waist,decrease,80.0000,cm,80.00,cm,,,,2025-01-01T08:00:00.000Z"
        let url = makeTempFile(name: "imp-goals-noopt-\(UUID()).csv", content: csv)
        let result = SettingsImporter.parseGoalsCSV(url: url)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertNil(result.rows[0].startValue)
        XCTAssertNil(result.rows[0].startDate)
    }

    /// Co sprawdza: Nieprawidłowy direction ("sideways") → wiersz skipped.
    func testInvalidDirectionSkipped() {
        let csv = "\(header)\nweight,Weight,sideways,75.0,kg,75.0,kg,,,,2025-01-01T08:00:00.000Z"
        let url = makeTempFile(name: "imp-goals-baddir-\(UUID()).csv", content: csv)
        let result = SettingsImporter.parseGoalsCSV(url: url)
        XCTAssertEqual(result.rows.count, 0)
        XCTAssertEqual(result.skipped, 1)
    }

    /// Co sprawdza: Nieznany metric_id w goals → wiersz skipped.
    func testUnknownMetricIdInGoalSkipped() {
        let csv = "\(header)\nunknown_metric,Unknown,decrease,75.0,kg,75.0,kg,,,,2025-01-01T08:00:00.000Z"
        let url = makeTempFile(name: "imp-goals-unknid-\(UUID()).csv", content: csv)
        let result = SettingsImporter.parseGoalsCSV(url: url)
        XCTAssertEqual(result.rows.count, 0)
        XCTAssertEqual(result.skipped, 1)
    }

    /// Co sprawdza: direction="increase" jest poprawnie parsowany.
    func testIncreaseDirectionParsed() {
        let csv = "\(header)\nleanBodyMass,Lean Body Mass,increase,60.0000,kg,60.00,kg,,,,2025-01-01T08:00:00.000Z"
        let url = makeTempFile(name: "imp-goals-inc-\(UUID()).csv", content: csv)
        let result = SettingsImporter.parseGoalsCSV(url: url)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0].direction, "increase")
    }

    /// Co sprawdza: Nieprawidłowa created_date → wiersz skipped.
    func testBadCreatedDateSkipped() {
        let csv = "\(header)\nweight,Weight,decrease,75.0,kg,75.0,kg,,,,not-a-date"
        let url = makeTempFile(name: "imp-goals-baddate-\(UUID()).csv", content: csv)
        let result = SettingsImporter.parseGoalsCSV(url: url)
        XCTAssertEqual(result.rows.count, 0)
        XCTAssertEqual(result.skipped, 1)
    }

    /// Co sprawdza: Brak kolumny created_date w nagłówku → pusty wynik.
    func testMissingCreatedDateColumnReturnsEmpty() {
        let csv = "metric_id,metric,direction,target_value_metric,target_unit_metric,target_value,target_unit\nweight,Weight,decrease,75.0,kg,75.0,kg"
        let url = makeTempFile(name: "imp-goals-nocd-\(UUID()).csv", content: csv)
        let result = SettingsImporter.parseGoalsCSV(url: url)
        XCTAssertEqual(result.rows.count, 0)
        XCTAssertEqual(result.skipped, 0, "Brak wymaganej kolumny → guard, nie pętla")
    }
}

// MARK: - insertSamples — merge/replace logic

@MainActor
final class InsertSamplesTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([MetricSample.self, MetricGoal.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    private func row(kindRaw: String = "weight", value: Double = 80.0, epochOffset: Double = 0) -> SettingsImporter.ParsedSampleRow {
        SettingsImporter.ParsedSampleRow(
            kindRaw: kindRaw,
            value: value,
            date: Date(timeIntervalSince1970: 1_700_000_000 + epochOffset)
        )
    }

    // MARK: Merge

    /// Co sprawdza: Merge — nowy sample jest wstawiany gdy nie ma go w bazie.
    func testMergeInsertsNewSample() throws {
        let context = ModelContext(try makeContainer())
        var result = SettingsImporter.ImportResult()

        SettingsImporter.insertSamples([row()], strategy: .merge, context: context, result: &result)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricSample>()), 1)
        XCTAssertEqual(result.samplesInserted, 1)
    }

    /// Co sprawdza: Merge — duplikat (ten sam kindRaw + sekunda epoch) jest pomijany.
    func testMergeSkipsDuplicateByKindAndEpoch() throws {
        let context = ModelContext(try makeContainer())
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        context.insert(MetricSample(kind: .weight, value: 80.0, date: fixedDate))
        try context.save()

        var result = SettingsImporter.ImportResult()
        // Ten sam kindRaw + ta sama sekunda epoch → duplikat
        SettingsImporter.insertSamples([row(epochOffset: 0)], strategy: .merge, context: context, result: &result)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricSample>()), 1, "Duplikat nie powinien być wstawiony")
        XCTAssertEqual(result.samplesInserted, 0)
    }

    /// Co sprawdza: Merge — różny kindRaw, ten sam epoch → NIE jest duplikatem (klucz = kindRaw_epoch).
    func testMergeDifferentKindSameEpochIsNotDuplicate() throws {
        let context = ModelContext(try makeContainer())

        context.insert(MetricSample(kind: .weight, value: 80.0, date: Date(timeIntervalSince1970: 1_700_000_000)))
        try context.save()

        var result = SettingsImporter.ImportResult()
        let waistRow = SettingsImporter.ParsedSampleRow(kindRaw: "waist", value: 85.0, date: Date(timeIntervalSince1970: 1_700_000_000))
        SettingsImporter.insertSamples([waistRow], strategy: .merge, context: context, result: &result)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricSample>()), 2, "Inny kindRaw → nie jest duplikatem")
        XCTAssertEqual(result.samplesInserted, 1)
    }

    /// Co sprawdza: Merge — ten sam kindRaw, różna sekunda epoch → NIE jest duplikatem.
    func testMergeSameKindDifferentEpochIsNotDuplicate() throws {
        let context = ModelContext(try makeContainer())

        context.insert(MetricSample(kind: .weight, value: 80.0, date: Date(timeIntervalSince1970: 1_700_000_000)))
        try context.save()

        var result = SettingsImporter.ImportResult()
        SettingsImporter.insertSamples([row(epochOffset: 1)], strategy: .merge, context: context, result: &result)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricSample>()), 2, "Różna sekunda → nie jest duplikatem")
        XCTAssertEqual(result.samplesInserted, 1)
    }

    /// Co sprawdza: Merge — wśród kilku wierszy tylko nowe są wstawiane.
    func testMergeInsertsOnlyNewRows() throws {
        let context = ModelContext(try makeContainer())
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        context.insert(MetricSample(kind: .weight, value: 80.0, date: date))
        try context.save()

        var result = SettingsImporter.ImportResult()
        let rows = [
            row(epochOffset: 0),           // duplikat
            row(kindRaw: "waist", epochOffset: 0),  // nowy (inny kind)
            row(epochOffset: 1)            // nowy (inny epoch)
        ]
        SettingsImporter.insertSamples(rows, strategy: .merge, context: context, result: &result)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricSample>()), 3)
        XCTAssertEqual(result.samplesInserted, 2)
    }

    // MARK: Replace

    /// Co sprawdza: Replace — insertSamples wstawia wszystkie wiersze bez dedup (replace czyści w importData).
    func testReplaceInsertsAllRowsIncludingDuplicateEpochs() throws {
        let context = ModelContext(try makeContainer())
        var result = SettingsImporter.ImportResult()

        // 3 wiersze z tym samym kindRaw i epochem — replace nie sprawdza duplikatów
        let rows = [row(), row(), row()]
        SettingsImporter.insertSamples(rows, strategy: .replace, context: context, result: &result)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricSample>()), 3, "Replace wstawia wszystkie bez dedup")
        XCTAssertEqual(result.samplesInserted, 3)
    }

    // MARK: samplesInserted counter

    /// Co sprawdza: Nieznany kindRaw jest pomijany przez insertSamples (guard MetricKind).
    func testUnknownKindRawIsSkippedDuringInsert() throws {
        let context = ModelContext(try makeContainer())
        var result = SettingsImporter.ImportResult()

        let badRow = SettingsImporter.ParsedSampleRow(kindRaw: "not_a_kind", value: 80.0, date: .now)
        SettingsImporter.insertSamples([badRow], strategy: .merge, context: context, result: &result)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricSample>()), 0)
        XCTAssertEqual(result.samplesInserted, 0)
    }
}

// MARK: - insertGoals — upsert logic

@MainActor
final class InsertGoalsTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([MetricSample.self, MetricGoal.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    private func goalRow(
        kindRaw: String = "weight",
        direction: String = "decrease",
        targetValue: Double = 75.0,
        startValue: Double? = nil,
        startDate: Date? = nil
    ) -> SettingsImporter.ParsedGoalRow {
        SettingsImporter.ParsedGoalRow(
            kindRaw: kindRaw,
            direction: direction,
            targetValue: targetValue,
            startValue: startValue,
            startDate: startDate,
            createdDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    /// Co sprawdza: Nowy cel → wstawiany (goalsInserted += 1, goalsUpdated == 0).
    func testNewGoalInserted() throws {
        let context = ModelContext(try makeContainer())
        var result = SettingsImporter.ImportResult()

        SettingsImporter.insertGoals([goalRow()], strategy: .merge, context: context, result: &result)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricGoal>()), 1)
        XCTAssertEqual(result.goalsInserted, 1)
        XCTAssertEqual(result.goalsUpdated, 0)
    }

    /// Co sprawdza: Istniejący cel (ten sam kindRaw) → upsert (goalsUpdated += 1, brak duplikatu).
    func testExistingGoalUpserted() throws {
        let context = ModelContext(try makeContainer())

        context.insert(MetricGoal(kind: .weight, targetValue: 80.0, direction: .decrease))
        try context.save()

        var result = SettingsImporter.ImportResult()
        SettingsImporter.insertGoals([goalRow(targetValue: 70.0)], strategy: .merge, context: context, result: &result)
        try context.save()

        let goals = try context.fetch(FetchDescriptor<MetricGoal>())
        XCTAssertEqual(goals.count, 1, "Upsert nie powinien tworzyć duplikatu celu")
        XCTAssertEqual(goals[0].targetValue, 70.0, accuracy: 0.001, "targetValue powinno być zaktualizowane")
        XCTAssertEqual(result.goalsInserted, 0)
        XCTAssertEqual(result.goalsUpdated, 1)
    }

    /// Co sprawdza: Wiele celów różnych metryk — każdy wstawiany oddzielnie.
    func testMultipleGoalsInserted() throws {
        let context = ModelContext(try makeContainer())
        var result = SettingsImporter.ImportResult()

        let rows = [
            goalRow(kindRaw: "weight",  targetValue: 75.0),
            goalRow(kindRaw: "waist",   targetValue: 80.0),
            goalRow(kindRaw: "bodyFat", targetValue: 15.0)
        ]
        SettingsImporter.insertGoals(rows, strategy: .merge, context: context, result: &result)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricGoal>()), 3)
        XCTAssertEqual(result.goalsInserted, 3)
        XCTAssertEqual(result.goalsUpdated, 0)
    }

    /// Co sprawdza: Cel z startValue i startDate — pola opcjonalne są zapisywane w modelu.
    func testGoalStartFieldsPersistedInModel() throws {
        let context = ModelContext(try makeContainer())
        let startDate = Date(timeIntervalSince1970: 1_690_000_000)
        var result = SettingsImporter.ImportResult()

        SettingsImporter.insertGoals([goalRow(startValue: 85.0, startDate: startDate)], strategy: .merge, context: context, result: &result)
        try context.save()

        let goals = try context.fetch(FetchDescriptor<MetricGoal>())
        XCTAssertEqual(goals[0].startValue, 85.0)
        let savedStartEpoch = try XCTUnwrap(goals[0].startDate).timeIntervalSince1970
        XCTAssertEqual(savedStartEpoch, startDate.timeIntervalSince1970, accuracy: 1.0)
    }

    /// Co sprawdza: Upsert zachowuje startValue z importowanego wiersza (nadpisuje stary start).
    func testUpsertOverwritesStartValue() throws {
        let context = ModelContext(try makeContainer())

        let existing = MetricGoal(kind: .weight, targetValue: 80.0, direction: .decrease)
        existing.startValue = 90.0
        context.insert(existing)
        try context.save()

        var result = SettingsImporter.ImportResult()
        SettingsImporter.insertGoals([goalRow(startValue: 85.0)], strategy: .merge, context: context, result: &result)
        try context.save()

        let goals = try context.fetch(FetchDescriptor<MetricGoal>())
        XCTAssertEqual(goals[0].startValue, 85.0, "Upsert powinien nadpisać startValue")
        XCTAssertEqual(result.goalsUpdated, 1)
    }

    /// Co sprawdza: Nieznany kindRaw jest pomijany przez insertGoals (guard MetricKind).
    func testUnknownKindRawSkippedInGoals() throws {
        let context = ModelContext(try makeContainer())
        var result = SettingsImporter.ImportResult()

        let badRow = SettingsImporter.ParsedGoalRow(kindRaw: "not_a_kind", direction: "decrease", targetValue: 75.0, startValue: nil, startDate: nil, createdDate: .now)
        SettingsImporter.insertGoals([badRow], strategy: .merge, context: context, result: &result)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricGoal>()), 0)
        XCTAssertEqual(result.goalsInserted, 0)
    }
}

// MARK: - importData end-to-end

@MainActor
final class ImportDataEndToEndTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([MetricSample.self, MetricGoal.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    private let metricsHeader = "metric_id,metric,value_metric,unit_metric,value,unit,timestamp"
    private let goalsHeader   = "metric_id,metric,direction,target_value_metric,target_unit_metric,target_value,target_unit,start_value_metric,start_value,start_date,created_date"

    /// Co sprawdza: Plik z "metrics" w nazwie → parsowany jako MetricSample.
    func testMetricsFilenameRoutedToSamplesParser() async throws {
        let context = ModelContext(try makeContainer())
        let csv = "\(metricsHeader)\nweight,Weight,80.0000,kg,80.00,kg,2025-01-01T08:00:00.000Z"
        let url = makeTempFile(name: "measureme-metrics-20250101.csv", content: csv)

        _ = try await SettingsImporter.importData(urls: [url], strategy: .merge, context: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricSample>()), 1)
    }

    /// Co sprawdza: Plik z "goals" w nazwie → parsowany jako MetricGoal.
    func testGoalsFilenameRoutedToGoalsParser() async throws {
        let context = ModelContext(try makeContainer())
        let csv = "\(goalsHeader)\nweight,Weight,decrease,75.0000,kg,75.00,kg,,,,2025-01-01T08:00:00.000Z"
        let url = makeTempFile(name: "measureme-goals-20250101.csv", content: csv)

        _ = try await SettingsImporter.importData(urls: [url], strategy: .merge, context: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricGoal>()), 1)
    }

    /// Co sprawdza: Routing odbywa się po nagłówku CSV, niezależnie od nazwy pliku.
    func testHeaderRoutingWorksIndependentlyOfFilename() async throws {
        let context = ModelContext(try makeContainer())
        let csv = "\(metricsHeader)\nweight,Weight,80.0000,kg,80.00,kg,2025-01-01T08:00:00.000Z"
        let url = makeTempFile(name: "measureme-backup-20250101.csv", content: csv)

        _ = try await SettingsImporter.importData(urls: [url], strategy: .merge, context: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricSample>()), 1, "Nagłówek metrics powinien uruchomić parser metryk")
    }

    /// Co sprawdza: Strategy.replace usuwa istniejące dane przed importem.
    func testReplaceStrategyClearsAllExistingData() async throws {
        let context = ModelContext(try makeContainer())

        context.insert(MetricSample(kind: .weight, value: 90.0, date: .now))
        context.insert(MetricSample(kind: .waist,  value: 95.0, date: .now))
        try context.save()

        let csv = "\(metricsHeader)\nbodyFat,Body Fat,20.0000,%,20.00,%,2025-01-01T08:00:00.000Z"
        let url = makeTempFile(name: "measureme-metrics-replace-\(UUID()).csv", content: csv)

        _ = try await SettingsImporter.importData(urls: [url], strategy: .replace, context: context)

        let samples = try context.fetch(FetchDescriptor<MetricSample>())
        XCTAssertEqual(samples.count, 1, "Replace powinien usunąć istniejące i wstawić tylko nowe")
        XCTAssertEqual(samples[0].kindRaw, "bodyFat")
    }

    /// Co sprawdza: Strategy.merge nie kasuje istniejących danych (stare + nowe razem).
    func testMergeStrategyPreservesExistingData() async throws {
        let context = ModelContext(try makeContainer())

        let existingDate = Date(timeIntervalSince1970: 1_690_000_000)
        context.insert(MetricSample(kind: .weight, value: 90.0, date: existingDate))
        try context.save()

        let newDate = Date(timeIntervalSince1970: 1_700_000_000)
        let csv = "\(metricsHeader)\nweight,Weight,81.0000,kg,81.00,kg,\(isoFull.string(from: newDate))"
        let url = makeTempFile(name: "measureme-metrics-merge-\(UUID()).csv", content: csv)

        _ = try await SettingsImporter.importData(urls: [url], strategy: .merge, context: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricSample>()), 2, "Merge powinien zachować stare i dodać nowe")
    }

    /// Co sprawdza: Oba pliki (metrics + goals) w jednym wywołaniu → oba przetworzone.
    func testBothFilesProcessedInSingleCall() async throws {
        let context = ModelContext(try makeContainer())

        let metricsCsv = "\(metricsHeader)\nweight,Weight,80.0000,kg,80.00,kg,2025-01-01T08:00:00.000Z"
        let goalsCsv   = "\(goalsHeader)\nwaist,Waist,decrease,80.0000,cm,80.00,cm,,,,2025-01-01T08:00:00.000Z"
        let metricsURL = makeTempFile(name: "measureme-metrics-both-\(UUID()).csv", content: metricsCsv)
        let goalsURL   = makeTempFile(name: "measureme-goals-both-\(UUID()).csv",   content: goalsCsv)

        _ = try await SettingsImporter.importData(urls: [metricsURL, goalsURL], strategy: .merge, context: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricSample>()), 1, "1 MetricSample")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricGoal>()),   1, "1 MetricGoal")
    }

    /// Co sprawdza: Pusta lista URL-i zwraca błąd noSupportedCSVFiles.
    func testEmptyURLListThrowsNoSupportedFiles() async throws {
        let context = ModelContext(try makeContainer())
        do {
            _ = try await SettingsImporter.importData(urls: [], strategy: .merge, context: context)
            XCTFail("Expected noSupportedCSVFiles")
        } catch let error as SettingsImporter.ImportError {
            XCTAssertEqual(error, .noSupportedCSVFiles)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Co sprawdza: Replace + brak wspieranego CSV rzuca noSupportedCSVFiles i nie kasuje istniejących danych.
    func testReplaceWithNoSupportedFilesDoesNotDeleteExistingData() async throws {
        let context = ModelContext(try makeContainer())
        context.insert(MetricSample(kind: .weight, value: 90.0, date: .now))
        try context.save()

        let unsupportedCSV = "foo,bar\n1,2"
        let url = makeTempFile(name: "unsupported-\(UUID()).csv", content: unsupportedCSV)

        do {
            _ = try await SettingsImporter.importData(urls: [url], strategy: .replace, context: context)
            XCTFail("Expected noSupportedCSVFiles")
        } catch let error as SettingsImporter.ImportError {
            XCTAssertEqual(error, .noSupportedCSVFiles)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricSample>()), 1, "Replace nie powinien usuwać danych przy błędnym wejściu")
    }

    /// Co sprawdza: Skipped rows z parsera trafiają do rowsSkipped w ImportResult → komunikat zawiera info.
    func testSkippedRowsAppearsInResultMessage() async throws {
        let context = ModelContext(try makeContainer())

        // Plik z jednym złym wierszem (nieznany metric_id)
        let csv = "\(metricsHeader)\nnot_a_metric,Unknown,80.0,kg,80.0,kg,2025-01-01T08:00:00.000Z"
        let url = makeTempFile(name: "measureme-metrics-skip-\(UUID()).csv", content: csv)

        let msg = try await SettingsImporter.importData(urls: [url], strategy: .merge, context: context)
        XCTAssertTrue(msg.contains("1"), "Komunikat powinien informować o pominiętych wierszach")
    }
}
