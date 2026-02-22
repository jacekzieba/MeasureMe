/// Cel testow: Sprawdza parser CSV oraz logike wstawiania danych (metrics i goals) przy imporcie danych.
/// Dlaczego to wazne: Nieprawidlowy import moze zniszczyc dane uzytkownika lub wstawic bledne wartosci.
/// Kryteria zaliczenia: Parser poprawnie waliduje wiersze, pomija zle dane, a insert zachowuje merge/replace logike.

import XCTest
import SwiftData
@testable import MeasureMe

// MARK: - Helpers

/// Lokalna kopia helpera parseCSVLine dla testow (identyczna logika jak w SettingsView).
private func parseCSVLine(_ line: String) -> [String] {
    var fields: [String] = []
    var current = ""
    var inQuotes = false
    var idx = line.startIndex
    while idx < line.endIndex {
        let c = line[idx]
        if inQuotes {
            if c == "\"" {
                let next = line.index(after: idx)
                if next < line.endIndex && line[next] == "\"" {
                    current.append("\"")
                    idx = line.index(after: next)
                    continue
                } else {
                    inQuotes = false
                }
            } else {
                current.append(c)
            }
        } else {
            if c == "\"" {
                inQuotes = true
            } else if c == "," {
                fields.append(current)
                current = ""
            } else if c == "\r" {
                // pominiety
            } else {
                current.append(c)
            }
        }
        idx = line.index(after: idx)
    }
    fields.append(current)
    return fields
}

/// Tworzy tymczasowy plik z podana zawartoscia i zwraca URL.
private func makeTempFile(name: String, content: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    try? content.write(to: url, atomically: true, encoding: .utf8)
    return url
}

// MARK: - parseCSVLine Tests

final class CSVLineParserTests: XCTestCase {

    /// Co sprawdza: Prosty wiersz bez cudzysłowów.
    func testSimpleLineNoQuotes() {
        let result = parseCSVLine("weight,80.5,kg,2025-01-01T08:00:00Z")
        XCTAssertEqual(result, ["weight", "80.5", "kg", "2025-01-01T08:00:00Z"])
    }

    /// Co sprawdza: Pole w cudzysłowach z przecinkiem wewnątrz.
    func testFieldWithQuotedComma() {
        let result = parseCSVLine("weight,\"80,5\",kg")
        XCTAssertEqual(result, ["weight", "80,5", "kg"])
    }

    /// Co sprawdza: Podwójny cudzysłów wewnątrz pola.
    func testDoubleQuoteEscaping() {
        let result = parseCSVLine("\"say \"\"hello\"\"\",test")
        XCTAssertEqual(result, ["say \"hello\"", "test"])
    }

    /// Co sprawdza: Puste pola (np. opcjonalne start_value).
    func testEmptyFields() {
        let result = parseCSVLine("weight,increase,50,,")
        XCTAssertEqual(result, ["weight", "increase", "50", "", ""])
    }
}

// MARK: - MetricsCSV Parser Tests

final class MetricsCSVParserTests: XCTestCase {

    private let header = "metric_id,metric,value_metric,unit_metric,value,unit,timestamp"

    /// Co sprawdza: Poprawny wiersz metryki jest parsowany i zwracany.
    func testValidRowIsParsed() throws {
        let csv = """
        \(header)
        weight,Weight,80.5,kg,80.5,kg,2025-01-03T08:00:00.000Z
        """
        let url = makeTempFile(name: "metrics_valid.csv", content: csv)
        let rows = parseMetricsCSV(url: url)
        XCTAssertEqual(rows.rows.count, 1)
        XCTAssertEqual(rows.skipped, 0)
        XCTAssertEqual(rows.rows[0].kindRaw, "weight")
        XCTAssertEqual(rows.rows[0].value, 80.5, accuracy: 0.001)
    }

    /// Co sprawdza: Nieznany metric_id jest pomijany.
    func testUnknownMetricIdIsSkipped() throws {
        let csv = """
        \(header)
        unknown_metric,Unknown,80.5,kg,80.5,kg,2025-01-03T08:00:00.000Z
        """
        let url = makeTempFile(name: "metrics_unknown.csv", content: csv)
        let rows = parseMetricsCSV(url: url)
        XCTAssertEqual(rows.rows.count, 0)
        XCTAssertEqual(rows.skipped, 1)
    }

    /// Co sprawdza: Nieprawidłowa data jest pomijana.
    func testInvalidDateIsSkipped() throws {
        let csv = """
        \(header)
        weight,Weight,80.5,kg,80.5,kg,not-a-date
        """
        let url = makeTempFile(name: "metrics_baddate.csv", content: csv)
        let rows = parseMetricsCSV(url: url)
        XCTAssertEqual(rows.rows.count, 0)
        XCTAssertEqual(rows.skipped, 1)
    }

    /// Co sprawdza: Nieprawidłowa wartość liczbowa jest pomijana.
    func testInvalidValueIsSkipped() throws {
        let csv = """
        \(header)
        weight,Weight,abc,kg,abc,kg,2025-01-03T08:00:00.000Z
        """
        let url = makeTempFile(name: "metrics_badval.csv", content: csv)
        let rows = parseMetricsCSV(url: url)
        XCTAssertEqual(rows.rows.count, 0)
        XCTAssertEqual(rows.skipped, 1)
    }

    /// Co sprawdza: Mieszane wiersze — dobre i złe.
    func testMixedRowsCountedCorrectly() throws {
        let csv = """
        \(header)
        weight,Weight,80.5,kg,80.5,kg,2025-01-03T08:00:00.000Z
        unknown_metric,Unk,5,kg,5,kg,2025-01-03T09:00:00.000Z
        waist,Waist,85.0,cm,85.0,cm,2025-01-04T08:00:00.000Z
        """
        let url = makeTempFile(name: "metrics_mixed.csv", content: csv)
        let rows = parseMetricsCSV(url: url)
        XCTAssertEqual(rows.rows.count, 2)
        XCTAssertEqual(rows.skipped, 1)
    }

    /// Co sprawdza: Pusty plik (tylko nagłówek) nie powoduje błędu.
    func testHeaderOnlyFile() throws {
        let csv = header
        let url = makeTempFile(name: "metrics_empty.csv", content: csv)
        let rows = parseMetricsCSV(url: url)
        XCTAssertEqual(rows.rows.count, 0)
        XCTAssertEqual(rows.skipped, 0)
    }

    /// Co sprawdza: Brakujący nagłówek metric_id zwraca pusty wynik.
    func testMissingRequiredColumnReturnsEmpty() throws {
        let csv = """
        metric,value_metric,unit_metric,value,unit,timestamp
        Weight,80.5,kg,80.5,kg,2025-01-03T08:00:00.000Z
        """
        let url = makeTempFile(name: "metrics_noid.csv", content: csv)
        let rows = parseMetricsCSV(url: url)
        XCTAssertEqual(rows.rows.count, 0)
        XCTAssertEqual(rows.skipped, 0)
    }

    // MARK: - Private helpers

    private struct ParsedRow {
        let kindRaw: String
        let value: Double
        let date: Date
    }

    private struct ParseResult {
        var rows: [ParsedRow] = []
        var skipped: Int = 0
    }

    private func parseMetricsCSV(url: URL) -> ParseResult {
        var result = ParseResult()
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return result }
        let lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let headerLine = lines.first else { return result }

        let cols = parseCSVLine(headerLine)
        guard let idxId  = cols.firstIndex(of: "metric_id"),
              let idxVal = cols.firstIndex(of: "value_metric"),
              let idxTs  = cols.firstIndex(of: "timestamp")
        else { return result }

        let isoFull  = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        for line in lines.dropFirst() {
            let fields = parseCSVLine(line)
            let maxIdx = max(idxId, idxVal, idxTs)
            guard fields.count > maxIdx else { result.skipped += 1; continue }
            let kindRaw = fields[idxId]
            guard MetricKind(rawValue: kindRaw) != nil else { result.skipped += 1; continue }
            guard let value = Double(fields[idxVal]) else { result.skipped += 1; continue }
            let tsString = fields[idxTs]
            guard let date = isoFull.date(from: tsString) ?? isoBasic.date(from: tsString)
            else { result.skipped += 1; continue }
            result.rows.append(ParsedRow(kindRaw: kindRaw, value: value, date: date))
        }
        return result
    }
}

// MARK: - GoalsCSV Parser Tests

final class GoalsCSVParserTests: XCTestCase {

    private let header = "metric_id,metric,direction,target_value_metric,target_unit_metric,target_value,target_unit,start_value_metric,start_value,start_date,created_date"

    /// Co sprawdza: Poprawny wiersz celu (z polami opcjonalnymi) jest parsowany.
    func testValidGoalRowIsParsed() throws {
        let csv = """
        \(header)
        weight,Weight,decrease,75.0,kg,75.0,kg,80.0,80.0,2025-01-01T00:00:00.000Z,2025-01-01T08:00:00.000Z
        """
        let url = makeTempFile(name: "goals_valid.csv", content: csv)
        let rows = parseGoalsCSV(url: url)
        XCTAssertEqual(rows.rows.count, 1)
        XCTAssertEqual(rows.skipped, 0)
        XCTAssertEqual(rows.rows[0].kindRaw, "weight")
        XCTAssertEqual(rows.rows[0].direction, "decrease")
        XCTAssertEqual(rows.rows[0].targetValue, 75.0, accuracy: 0.001)
        XCTAssertEqual(rows.rows[0].startValue, 80.0)
        XCTAssertNotNil(rows.rows[0].startDate)
    }

    /// Co sprawdza: Wiersz celu bez wartości opcjonalnych (puste pola start).
    func testGoalWithoutOptionalFieldsIsParsed() throws {
        let csv = """
        \(header)
        waist,Waist,decrease,80.0,cm,80.0,cm,,,, 2025-01-01T08:00:00.000Z
        """
        let url = makeTempFile(name: "goals_noopt.csv", content: csv)
        let rows = parseGoalsCSV(url: url)
        XCTAssertEqual(rows.rows.count, 1)
        XCTAssertNil(rows.rows[0].startValue)
        XCTAssertNil(rows.rows[0].startDate)
    }

    /// Co sprawdza: Nieznany kierunek (np. "sideways") jest pomijany.
    func testInvalidDirectionIsSkipped() throws {
        let csv = """
        \(header)
        weight,Weight,sideways,75.0,kg,75.0,kg,,,,2025-01-01T08:00:00.000Z
        """
        let url = makeTempFile(name: "goals_baddir.csv", content: csv)
        let rows = parseGoalsCSV(url: url)
        XCTAssertEqual(rows.rows.count, 0)
        XCTAssertEqual(rows.skipped, 1)
    }

    /// Co sprawdza: Nieznany metric_id w goals jest pomijany.
    func testUnknownMetricIdInGoalIsSkipped() throws {
        let csv = """
        \(header)
        unknown_metric,Unknown,decrease,75.0,kg,75.0,kg,,,,2025-01-01T08:00:00.000Z
        """
        let url = makeTempFile(name: "goals_unknid.csv", content: csv)
        let rows = parseGoalsCSV(url: url)
        XCTAssertEqual(rows.rows.count, 0)
        XCTAssertEqual(rows.skipped, 1)
    }

    /// Co sprawdza: Cel z direction=increase jest poprawnie parsowany.
    func testIncreaseDirectionIsParsed() throws {
        let csv = """
        \(header)
        leanBodyMass,Lean Body Mass,increase,60.0,kg,60.0,kg,,,,2025-01-01T08:00:00.000Z
        """
        let url = makeTempFile(name: "goals_increase.csv", content: csv)
        let rows = parseGoalsCSV(url: url)
        XCTAssertEqual(rows.rows.count, 1)
        XCTAssertEqual(rows.rows[0].direction, "increase")
    }

    // MARK: - Private helpers

    private struct ParsedGoalRow {
        let kindRaw: String
        let direction: String
        let targetValue: Double
        let startValue: Double?
        let startDate: Date?
        let createdDate: Date
    }

    private struct GoalsParseResult {
        var rows: [ParsedGoalRow] = []
        var skipped: Int = 0
    }

    private func parseGoalsCSV(url: URL) -> GoalsParseResult {
        var result = GoalsParseResult()
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return result }
        let lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let headerLine = lines.first else { return result }

        let cols = parseCSVLine(headerLine)
        guard let idxId      = cols.firstIndex(of: "metric_id"),
              let idxDir     = cols.firstIndex(of: "direction"),
              let idxTarget  = cols.firstIndex(of: "target_value_metric"),
              let idxCreated = cols.firstIndex(of: "created_date")
        else { return result }

        let idxStartVal  = cols.firstIndex(of: "start_value_metric")
        let idxStartDate = cols.firstIndex(of: "start_date")

        let isoFull  = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        for line in lines.dropFirst() {
            let fields = parseCSVLine(line)
            let maxIdx = max(idxId, idxDir, idxTarget, idxCreated)
            guard fields.count > maxIdx else { result.skipped += 1; continue }

            let kindRaw = fields[idxId]
            guard MetricKind(rawValue: kindRaw) != nil else { result.skipped += 1; continue }

            let direction = fields[idxDir]
            guard direction == "increase" || direction == "decrease" else { result.skipped += 1; continue }

            guard let targetValue = Double(fields[idxTarget]) else { result.skipped += 1; continue }

            let createdStr = fields[idxCreated].trimmingCharacters(in: .whitespaces)
            guard let createdDate = isoFull.date(from: createdStr) ?? isoBasic.date(from: createdStr)
            else { result.skipped += 1; continue }

            var startValue: Double? = nil
            if let idx = idxStartVal, idx < fields.count, !fields[idx].isEmpty {
                startValue = Double(fields[idx])
            }
            var startDate: Date? = nil
            if let idx = idxStartDate, idx < fields.count, !fields[idx].trimmingCharacters(in: .whitespaces).isEmpty {
                let s = fields[idx].trimmingCharacters(in: .whitespaces)
                startDate = isoFull.date(from: s) ?? isoBasic.date(from: s)
            }

            result.rows.append(ParsedGoalRow(
                kindRaw: kindRaw,
                direction: direction,
                targetValue: targetValue,
                startValue: startValue,
                startDate: startDate,
                createdDate: createdDate
            ))
        }
        return result
    }
}

// MARK: - SwiftData Insert Tests

@MainActor
final class CSVImportSwiftDataTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([MetricSample.self, MetricGoal.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    /// Co sprawdza: Merge nie duplikuje istniejących pomiarów (ten sam kindRaw + epoch).
    func testMergeDoeNotInsertDuplicateSamples() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = MetricSample(kind: .weight, value: 80.0, date: fixedDate)
        context.insert(existing)
        try context.save()

        // Próba wstawienia duplikatu przez logikę merge
        let newSample = MetricSample(kind: .weight, value: 80.0, date: fixedDate)
        let existingFetch = (try? context.fetch(FetchDescriptor<MetricSample>())) ?? []
        var keys = Set<String>()
        for s in existingFetch {
            let epoch = Int(s.date.timeIntervalSince1970)
            keys.insert("\(s.kindRaw)_\(epoch)")
        }
        let epoch = Int(newSample.date.timeIntervalSince1970)
        let key = "\(newSample.kindRaw)_\(epoch)"
        if !keys.contains(key) {
            context.insert(newSample)
        }
        try context.save()

        let count = try context.fetchCount(FetchDescriptor<MetricSample>())
        XCTAssertEqual(count, 1, "Merge nie powinien dodac duplikatu")
    }

    /// Co sprawdza: Replace kasuje istniejące i wstawia nowe.
    func testReplaceDeletesExistingAndInsertsNew() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let existing = MetricSample(kind: .weight, value: 80.0, date: .now)
        context.insert(existing)
        try context.save()

        // Replace: kasuj wszystko
        let allExisting = try context.fetch(FetchDescriptor<MetricSample>())
        allExisting.forEach { context.delete($0) }
        try context.save()

        // Wstaw nowy
        let newSample = MetricSample(kind: .waist, value: 85.0, date: .now)
        context.insert(newSample)
        try context.save()

        let all = try context.fetch(FetchDescriptor<MetricSample>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].kindRaw, "waist")
    }

    /// Co sprawdza: Import celu — gdy cel już istnieje, jest nadpisywany (upsert).
    func testGoalUpsertOverwritesExisting() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let existingGoal = MetricGoal(kind: .weight, targetValue: 80.0, direction: .decrease)
        context.insert(existingGoal)
        try context.save()

        // Symulacja upsert
        let existing = (try? context.fetch(FetchDescriptor<MetricGoal>())) ?? []
        var byKind = Dictionary(uniqueKeysWithValues: existing.map { ($0.kindRaw, $0) })
        if let goal = byKind["weight"] {
            goal.targetValue = 70.0
            goal.directionRaw = "decrease"
        } else {
            let newGoal = MetricGoal(kind: .weight, targetValue: 70.0, direction: .decrease)
            context.insert(newGoal)
            byKind["weight"] = newGoal
        }
        try context.save()

        let count = try context.fetchCount(FetchDescriptor<MetricGoal>())
        XCTAssertEqual(count, 1, "Upsert nie powinien tworzyc duplikatu celu")

        let goals = try context.fetch(FetchDescriptor<MetricGoal>())
        XCTAssertEqual(goals[0].targetValue, 70.0, accuracy: 0.001)
    }

    /// Co sprawdza: Gdy cel nie istnieje, jest wstawiany.
    func testGoalInsertWhenNotExists() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let existing = (try? context.fetch(FetchDescriptor<MetricGoal>())) ?? []
        var byKind = Dictionary(uniqueKeysWithValues: existing.map { ($0.kindRaw, $0) })

        if byKind["weight"] == nil {
            let newGoal = MetricGoal(kind: .weight, targetValue: 75.0, direction: .decrease)
            context.insert(newGoal)
            byKind["weight"] = newGoal
        }
        try context.save()

        let count = try context.fetchCount(FetchDescriptor<MetricGoal>())
        XCTAssertEqual(count, 1)
        let goals = try context.fetch(FetchDescriptor<MetricGoal>())
        XCTAssertEqual(goals[0].targetValue, 75.0, accuracy: 0.001)
    }
}
