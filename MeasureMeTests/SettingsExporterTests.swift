/// Cel testow: Weryfikuje logike budowania CSV i JSON eksportu danych (SettingsExporter).
/// Dlaczego to wazne: Blad w formacie CSV lub JSON cicho niszczy eksport uzytkownika.
///   Testy pokrywaja RFC-4180 escaping, format kolumn, licznosc wierszy, JSON structure.
/// Kryteria zaliczenia: Wszystkie nonisolated static func zwracaja deterministyczny wynik
///   dla danego wejscia — zero zaleznosci od UI, SwiftData ani HealthKit.

import XCTest
@testable import MeasureMe

// MARK: - Helpers

private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

/// Zwraca datę z określonego ISO-8601 stringa (zawsze non-nil w testach — crashuje dla błędnego stringa).
private func iso(_ string: String) -> Date {
    isoFormatter.date(from: string)!
}

// MARK: - csvField RFC-4180 Escaping

final class CSVFieldEscapingTests: XCTestCase {

    /// Co sprawdza: Proste pole bez znaków specjalnych nie jest owijane cudzysłowami.
    func testPlainValueNotQuoted() {
        XCTAssertEqual(SettingsExporter.csvField("weight"), "weight")
        XCTAssertEqual(SettingsExporter.csvField("80.5000"), "80.5000")
    }

    /// Co sprawdza: Pole z przecinkiem jest owijane cudzysłowami.
    func testFieldWithCommaIsQuoted() {
        XCTAssertEqual(SettingsExporter.csvField("Lean Body Mass, Metric"), "\"Lean Body Mass, Metric\"")
    }

    /// Co sprawdza: Pole z cudzysłowem — cudzysłów jest podwajany i całość owijana.
    func testFieldWithDoubleQuoteIsEscaped() {
        XCTAssertEqual(SettingsExporter.csvField("say \"hello\""), "\"say \"\"hello\"\"\"")
    }

    /// Co sprawdza: Pole z nową linią \n jest owijane cudzysłowami.
    func testFieldWithNewlineIsQuoted() {
        XCTAssertEqual(SettingsExporter.csvField("line1\nline2"), "\"line1\nline2\"")
    }

    /// Co sprawdza: Pole z \r jest owijane cudzysłowami.
    func testFieldWithCarriageReturnIsQuoted() {
        XCTAssertEqual(SettingsExporter.csvField("line1\rline2"), "\"line1\rline2\"")
    }

    /// Co sprawdza: Pusty string nie jest owijany (brak znaków specjalnych).
    func testEmptyStringNotQuoted() {
        XCTAssertEqual(SettingsExporter.csvField(""), "")
    }

    /// Co sprawdza: Pole zawierające tylko spacje nie wymaga owijania.
    func testSpacesOnlyNotQuoted() {
        XCTAssertEqual(SettingsExporter.csvField("   "), "   ")
    }

    /// Co sprawdza: Wszystkie znaki specjalne razem — poprawne podwojenie i owijanie.
    func testFieldWithAllSpecialChars() {
        let input = "a,\"b\"\nc"
        let output = SettingsExporter.csvField(input)
        // Powinno być owiane cudzysłowami, z podwójnym cudzysłowem
        XCTAssertTrue(output.hasPrefix("\""))
        XCTAssertTrue(output.hasSuffix("\""))
        XCTAssertTrue(output.contains("\"\""))
        XCTAssertTrue(output.contains(","))
    }
}

// MARK: - buildMetricsCSV

final class MetricsCSVBuilderTests: XCTestCase {

    private let metricsHeader = "metric_id,metric,value_metric,unit_metric,value,unit,timestamp"

    /// Co sprawdza: Pusta lista wierszy → tylko linia nagłówka.
    func testEmptyRowsReturnsHeaderOnly() {
        let csv = SettingsExporter.buildMetricsCSV(from: [])
        XCTAssertEqual(csv, metricsHeader)
    }

    /// Co sprawdza: Jeden wiersz → nagłówek + jedna linia danych.
    func testSingleRowProducesTwoLines() {
        let date = iso("2025-06-01T08:00:00.000Z")
        let row = SettingsExporter.MetricCSVRowSnapshot(
            kindRaw: "weight",
            metricTitle: "Weight",
            metricValue: 80.0,
            metricUnit: "kg",
            displayValue: 80.0,
            unit: "kg",
            date: date
        )
        let csv = SettingsExporter.buildMetricsCSV(from: [row])
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], metricsHeader)
    }

    /// Co sprawdza: Wartości metryczne są formatowane z dokładnością %.4f.
    func testMetricValueFormattedToFourDecimalPlaces() {
        let row = SettingsExporter.MetricCSVRowSnapshot(
            kindRaw: "weight",
            metricTitle: "Weight",
            metricValue: 80.123456789,
            metricUnit: "kg",
            displayValue: 80.12,
            unit: "kg",
            date: iso("2025-01-01T00:00:00.000Z")
        )
        let csv = SettingsExporter.buildMetricsCSV(from: [row])
        XCTAssertTrue(csv.contains("80.1235"), "Wartość metryczna powinna być zaokrąglona do 4 miejsc po przecinku")
    }

    /// Co sprawdza: Wartości display są formatowane z dokładnością %.2f.
    func testDisplayValueFormattedToTwoDecimalPlaces() {
        let row = SettingsExporter.MetricCSVRowSnapshot(
            kindRaw: "weight",
            metricTitle: "Weight",
            metricValue: 80.0,
            metricUnit: "kg",
            displayValue: 176.369785,
            unit: "lb",
            date: iso("2025-01-01T00:00:00.000Z")
        )
        let csv = SettingsExporter.buildMetricsCSV(from: [row])
        XCTAssertTrue(csv.contains("176.37"), "Wartość display powinna być zaokrąglona do 2 miejsc po przecinku")
    }

    /// Co sprawdza: Timestamp jest w formacie ISO-8601 z milisekundami i Z.
    func testTimestampIsISO8601WithFractionalSeconds() {
        let date = iso("2025-03-15T10:30:45.123Z")
        let row = SettingsExporter.MetricCSVRowSnapshot(
            kindRaw: "waist",
            metricTitle: "Waist",
            metricValue: 85.0,
            metricUnit: "cm",
            displayValue: 85.0,
            unit: "cm",
            date: date
        )
        let csv = SettingsExporter.buildMetricsCSV(from: [row])
        XCTAssertTrue(csv.contains("2025-03-15T10:30:45.123Z"), "Timestamp powinien być w formacie ISO-8601 z milisekundami")
    }

    /// Co sprawdza: Kolejność kolumn: metric_id, metric, value_metric, unit_metric, value, unit, timestamp.
    func testColumnOrderIsCorrect() {
        let date = iso("2025-01-01T00:00:00.000Z")
        let row = SettingsExporter.MetricCSVRowSnapshot(
            kindRaw: "bodyFat",
            metricTitle: "Body Fat",
            metricValue: 20.5,
            metricUnit: "%",
            displayValue: 20.5,
            unit: "%",
            date: date
        )
        let csv = SettingsExporter.buildMetricsCSV(from: [row])
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        // Parsuj drugą linię i sprawdź kolejność pól
        let fields = lines[1].components(separatedBy: ",")
        XCTAssertEqual(fields[0], "bodyFat")
        XCTAssertEqual(fields[1], "Body Fat")
        XCTAssertTrue(fields[2].hasPrefix("20."))   // value_metric
        XCTAssertEqual(fields[3], "%")               // unit_metric
        XCTAssertTrue(fields[4].hasPrefix("20."))   // value
        XCTAssertEqual(fields[5], "%")               // unit
        XCTAssertTrue(fields[6].hasPrefix("2025-")) // timestamp
    }

    /// Co sprawdza: Wiele wierszy → każdy pojawia się w CSV.
    func testMultipleRowsAllPresent() {
        let date = iso("2025-01-01T00:00:00.000Z")
        let rows = MetricKind.allCases.prefix(5).map { kind in
            SettingsExporter.MetricCSVRowSnapshot(
                kindRaw: kind.rawValue,
                metricTitle: kind.englishTitle,
                metricValue: 70.0,
                metricUnit: "kg",
                displayValue: 70.0,
                unit: "kg",
                date: date
            )
        }
        let csv = SettingsExporter.buildMetricsCSV(from: rows)
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 6, "Nagłówek + 5 wierszy danych")
    }

    /// Co sprawdza: metricTitle z przecinkiem (np. "Lean Body Mass, %") jest poprawnie cytowane.
    func testMetricTitleWithCommaIsQuoted() {
        let row = SettingsExporter.MetricCSVRowSnapshot(
            kindRaw: "leanBodyMass",
            metricTitle: "Lean, Mass",
            metricValue: 60.0,
            metricUnit: "kg",
            displayValue: 60.0,
            unit: "kg",
            date: iso("2025-01-01T00:00:00.000Z")
        )
        let csv = SettingsExporter.buildMetricsCSV(from: [row])
        XCTAssertTrue(csv.contains("\"Lean, Mass\""), "Pole z przecinkiem powinno być owinięte cudzysłowami")
    }

    /// Co sprawdza: Round-trip — CSV zbudowany z wierszy ma poprawną liczbę kolumn w każdej linii.
    func testEachDataLineHasCorrectColumnCount() {
        let date = iso("2025-01-01T00:00:00.000Z")
        let rows = [
            SettingsExporter.MetricCSVRowSnapshot(kindRaw: "weight", metricTitle: "Weight", metricValue: 80.0, metricUnit: "kg", displayValue: 176.37, unit: "lb", date: date),
            SettingsExporter.MetricCSVRowSnapshot(kindRaw: "waist",  metricTitle: "Waist",  metricValue: 85.0, metricUnit: "cm", displayValue: 33.46,  unit: "in", date: date)
        ]
        let csv = SettingsExporter.buildMetricsCSV(from: rows)
        let lines = csv.components(separatedBy: "\n")
        let headerCols = lines[0].components(separatedBy: ",").count
        for dataLine in lines.dropFirst() {
            let cols = dataLine.components(separatedBy: ",").count
            XCTAssertEqual(cols, headerCols, "Każda linia powinna mieć tę samą liczbę kolumn co nagłówek")
        }
    }
}

// MARK: - buildGoalsCSV

final class GoalsCSVBuilderTests: XCTestCase {

    private let goalsHeader = "metric_id,metric,direction,target_value_metric,target_unit_metric,target_value,target_unit,start_value_metric,start_value,start_date,created_date"

    /// Co sprawdza: Pusta lista → tylko nagłówek.
    func testEmptyGoalsReturnsHeaderOnly() {
        let csv = SettingsExporter.buildGoalsCSV(from: [])
        XCTAssertEqual(csv, goalsHeader)
    }

    /// Co sprawdza: Cel z wszystkimi polami opcjonalnymi (start) jest poprawnie budowany.
    func testGoalWithAllFieldsBuiltCorrectly() {
        let created = iso("2025-01-01T08:00:00.000Z")
        let start   = iso("2024-12-01T08:00:00.000Z")
        let row = SettingsExporter.MetricGoalSnapshot(
            kindRaw: "weight",
            metricTitle: "Weight",
            direction: "decrease",
            targetMetricValue: 75.0,
            targetMetricUnit: "kg",
            targetDisplayValue: 75.0,
            targetDisplayUnit: "kg",
            startMetricValue: 85.0,
            startDisplayValue: 85.0,
            startDate: start,
            createdDate: created
        )
        let csv = SettingsExporter.buildGoalsCSV(from: [row])
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains("weight"))
        XCTAssertTrue(lines[1].contains("decrease"))
        XCTAssertTrue(lines[1].contains("75.0000"))   // target_value_metric %.4f
        XCTAssertTrue(lines[1].contains("85.0000"))   // start_value_metric %.4f
        XCTAssertTrue(lines[1].contains("2024-12-01")) // start_date
        XCTAssertTrue(lines[1].contains("2025-01-01")) // created_date
    }

    /// Co sprawdza: Cel bez pól opcjonalnych (start) generuje puste pola w CSV.
    func testGoalWithoutOptionalFieldsHasEmptyStartColumns() {
        let created = iso("2025-01-01T08:00:00.000Z")
        let row = SettingsExporter.MetricGoalSnapshot(
            kindRaw: "waist",
            metricTitle: "Waist",
            direction: "decrease",
            targetMetricValue: 80.0,
            targetMetricUnit: "cm",
            targetDisplayValue: 80.0,
            targetDisplayUnit: "cm",
            startMetricValue: nil,
            startDisplayValue: nil,
            startDate: nil,
            createdDate: created
        )
        let csv = SettingsExporter.buildGoalsCSV(from: [row])
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        // start_value_metric, start_value, start_date powinny być puste
        // Linia zawiera ",,," dla tych 3 pól
        let dataLine = lines[1]
        let fields = dataLine.components(separatedBy: ",")
        XCTAssertEqual(fields.count, 11, "Cel powinien mieć 11 kolumn")
        XCTAssertEqual(fields[7], "", "start_value_metric powinno być puste")
        XCTAssertEqual(fields[8], "", "start_value powinno być puste")
        XCTAssertEqual(fields[9], "", "start_date powinno być puste")
    }

    /// Co sprawdza: direction="increase" poprawnie trafia do CSV.
    func testIncreaseDirectionInCSV() {
        let row = SettingsExporter.MetricGoalSnapshot(
            kindRaw: "leanBodyMass",
            metricTitle: "Lean Body Mass",
            direction: "increase",
            targetMetricValue: 65.0,
            targetMetricUnit: "kg",
            targetDisplayValue: 65.0,
            targetDisplayUnit: "kg",
            startMetricValue: nil,
            startDisplayValue: nil,
            startDate: nil,
            createdDate: iso("2025-01-01T00:00:00.000Z")
        )
        let csv = SettingsExporter.buildGoalsCSV(from: [row])
        XCTAssertTrue(csv.contains("increase"))
    }

    /// Co sprawdza: target_value_metric jest formatowane z %.4f (4 miejsca po przecinku).
    func testTargetValueFormattedToFourDecimalPlaces() {
        let row = SettingsExporter.MetricGoalSnapshot(
            kindRaw: "weight",
            metricTitle: "Weight",
            direction: "decrease",
            targetMetricValue: 70.123456,
            targetMetricUnit: "kg",
            targetDisplayValue: 70.12,
            targetDisplayUnit: "kg",
            startMetricValue: nil,
            startDisplayValue: nil,
            startDate: nil,
            createdDate: iso("2025-01-01T00:00:00.000Z")
        )
        let csv = SettingsExporter.buildGoalsCSV(from: [row])
        XCTAssertTrue(csv.contains("70.1235"), "target_value_metric powinno być %.4f")
    }

    /// Co sprawdza: Nagłówek ma dokładnie 11 kolumn.
    func testGoalsHeaderHasElevenColumns() {
        let csv = SettingsExporter.buildGoalsCSV(from: [])
        let headerCols = csv.components(separatedBy: ",").count
        XCTAssertEqual(headerCols, 11)
    }

    /// Co sprawdza: Wiele celów — wszystkie wiersze obecne.
    func testMultipleGoalsAllPresent() {
        let date = iso("2025-01-01T00:00:00.000Z")
        let rows = [
            SettingsExporter.MetricGoalSnapshot(kindRaw: "weight", metricTitle: "Weight", direction: "decrease", targetMetricValue: 75, targetMetricUnit: "kg", targetDisplayValue: 75, targetDisplayUnit: "kg", startMetricValue: nil, startDisplayValue: nil, startDate: nil, createdDate: date),
            SettingsExporter.MetricGoalSnapshot(kindRaw: "waist",  metricTitle: "Waist",  direction: "decrease", targetMetricValue: 80, targetMetricUnit: "cm", targetDisplayValue: 80, targetDisplayUnit: "cm", startMetricValue: nil, startDisplayValue: nil, startDate: nil, createdDate: date),
            SettingsExporter.MetricGoalSnapshot(kindRaw: "bodyFat", metricTitle: "Body Fat", direction: "decrease", targetMetricValue: 15, targetMetricUnit: "%",  targetDisplayValue: 15, targetDisplayUnit: "%",  startMetricValue: nil, startDisplayValue: nil, startDate: nil, createdDate: date)
        ]
        let csv = SettingsExporter.buildGoalsCSV(from: rows)
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 4, "Nagłówek + 3 wiersze celów")
    }
}

// MARK: - buildDiagnosticsJSON

final class DiagnosticsJSONBuilderTests: XCTestCase {

    private let device = SettingsExporter.DeviceSnapshot(
        systemName: "iOS",
        systemVersion: "17.4",
        model: "iPhone"
    )

    private func buildJSON(
        samples: [SettingsExporter.MetricSampleSnapshot] = [],
        photosCount: Int = 0,
        isSyncEnabled: Bool = false,
        lastHealthImportTimestamp: Double = 0
    ) -> [String: Any]? {
        guard let data = SettingsExporter.buildDiagnosticsJSON(
            samples: samples,
            photosCount: photosCount,
            isSyncEnabled: isSyncEnabled,
            lastHealthImportTimestamp: lastHealthImportTimestamp,
            device: device
        ) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Co sprawdza: Metoda zwraca niepusty Data.
    func testReturnsNonNilData() {
        let data = SettingsExporter.buildDiagnosticsJSON(
            samples: [],
            photosCount: 0,
            isSyncEnabled: false,
            lastHealthImportTimestamp: 0,
            device: device
        )
        XCTAssertNotNil(data)
        XCTAssertFalse(data!.isEmpty)
    }

    /// Co sprawdza: Zwrócony Data jest poprawnym JSONem.
    func testReturnedDataIsValidJSON() {
        let data = SettingsExporter.buildDiagnosticsJSON(
            samples: [],
            photosCount: 0,
            isSyncEnabled: false,
            lastHealthImportTimestamp: 0,
            device: device
        )!
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }

    /// Co sprawdza: JSON zawiera oczekiwane klucze najwyższego poziomu.
    func testTopLevelKeysPresent() {
        let json = buildJSON()!
        let expectedKeys = ["timestamp", "appVersion", "buildNumber", "system", "deviceModel",
                            "metricsCount", "metricsByKind", "photosCount", "healthKit"]
        for key in expectedKeys {
            XCTAssertNotNil(json[key], "Brak klucza: \(key)")
        }
    }

    /// Co sprawdza: metricsCount odpowiada liczbie podanych sampli.
    func testMetricsCountMatchesSampleCount() {
        let samples = [
            SettingsExporter.MetricSampleSnapshot(kindRaw: "weight", value: 80.0, date: .now),
            SettingsExporter.MetricSampleSnapshot(kindRaw: "waist",  value: 85.0, date: .now),
            SettingsExporter.MetricSampleSnapshot(kindRaw: "weight", value: 81.0, date: .now)
        ]
        let json = buildJSON(samples: samples)!
        XCTAssertEqual(json["metricsCount"] as? Int, 3)
    }

    /// Co sprawdza: metricsByKind grupuje poprawnie (np. 2x weight, 1x waist).
    func testMetricsByKindGroupedCorrectly() {
        let samples = [
            SettingsExporter.MetricSampleSnapshot(kindRaw: "weight", value: 80.0, date: .now),
            SettingsExporter.MetricSampleSnapshot(kindRaw: "weight", value: 81.0, date: .now),
            SettingsExporter.MetricSampleSnapshot(kindRaw: "waist",  value: 85.0, date: .now)
        ]
        let json = buildJSON(samples: samples)!
        let byKind = json["metricsByKind"] as? [String: Int]
        XCTAssertEqual(byKind?["weight"], 2)
        XCTAssertEqual(byKind?["waist"],  1)
    }

    /// Co sprawdza: photosCount jest poprawnie odzwierciedlony w JSON.
    func testPhotosCountIsCorrect() {
        let json = buildJSON(photosCount: 42)!
        XCTAssertEqual(json["photosCount"] as? Int, 42)
    }

    /// Co sprawdza: isSyncEnabled=true jest poprawnie zapisane w sekcji healthKit.
    func testSyncEnabledTrueReflectedInJSON() {
        let json = buildJSON(isSyncEnabled: true)!
        let healthKit = json["healthKit"] as? [String: Any]
        XCTAssertEqual(healthKit?["syncEnabled"] as? Bool, true)
    }

    /// Co sprawdza: isSyncEnabled=false jest poprawnie zapisane w sekcji healthKit.
    func testSyncEnabledFalseReflectedInJSON() {
        let json = buildJSON(isSyncEnabled: false)!
        let healthKit = json["healthKit"] as? [String: Any]
        XCTAssertEqual(healthKit?["syncEnabled"] as? Bool, false)
    }

    /// Co sprawdza: lastHealthImportTimestamp=0 → lastSync jest null/nil w JSON.
    func testLastSyncNilWhenTimestampIsZero() {
        let json = buildJSON(lastHealthImportTimestamp: 0)!
        let healthKit = json["healthKit"] as? [String: Any]
        // lastSync powinien być NSNull lub nieobecny gdy timestamp == 0
        let lastSync = healthKit?["lastSync"]
        let isNullOrNil = lastSync == nil || lastSync is NSNull
        XCTAssertTrue(isNullOrNil, "lastSync powinno być nil dla timestamp=0")
    }

    /// Co sprawdza: lastHealthImportTimestamp > 0 → lastSync jest ISO-8601 stringiem.
    func testLastSyncPresentWhenTimestampNonZero() {
        let ts = Date(timeIntervalSince1970: 1_700_000_000).timeIntervalSince1970
        let json = buildJSON(lastHealthImportTimestamp: ts)!
        let healthKit = json["healthKit"] as? [String: Any]
        let lastSync = healthKit?["lastSync"] as? String
        XCTAssertNotNil(lastSync, "lastSync powinno być stringiem dla niezerowego timestamp")
        XCTAssertTrue(lastSync!.hasPrefix("2023-"), "lastSync powinno być datą ISO-8601")
    }

    /// Co sprawdza: system zawiera systemName i systemVersion z DeviceSnapshot.
    func testSystemFieldContainsDeviceInfo() {
        let json = buildJSON()!
        let system = json["system"] as? String
        XCTAssertEqual(system, "iOS 17.4")
    }

    /// Co sprawdza: deviceModel jest poprawnie przekazany z DeviceSnapshot.
    func testDeviceModelIsCorrect() {
        let json = buildJSON()!
        XCTAssertEqual(json["deviceModel"] as? String, "iPhone")
    }

    /// Co sprawdza: Puste dane (brak sampli, photosCount=0) — JSON jest nadal poprawny.
    func testEmptyDataProducesValidJSON() {
        let json = buildJSON(samples: [], photosCount: 0)!
        XCTAssertEqual(json["metricsCount"] as? Int, 0)
        XCTAssertEqual(json["photosCount"] as? Int, 0)
        let byKind = json["metricsByKind"] as? [String: Int]
        XCTAssertTrue(byKind?.isEmpty ?? true)
    }
}

// MARK: - writeTempFile

final class TempFileWriterTests: XCTestCase {

    /// Co sprawdza: Zapis stringa UTF-8 zwraca URL do istniejącego pliku.
    func testWriteStringReturnsTempURL() throws {
        let url = SettingsExporter.writeTempFile(named: "test-export-\(UUID()).csv", contents: "hello,world")
        XCTAssertNotNil(url, "writeTempFile powinno zwrócić URL")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url!.path), "Plik powinien istnieć na dysku")
    }

    /// Co sprawdza: Zawartość zapisanego pliku odpowiada wejściowemu stringowi.
    func testWrittenContentMatchesInput() throws {
        let content = "metric_id,value\nweight,80.0"
        let url = try XCTUnwrap(SettingsExporter.writeTempFile(named: "test-content-\(UUID()).csv", contents: content))
        let read = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(read, content)
    }

    /// Co sprawdza: Zapis Data zwraca URL do pliku z identyczną zawartością.
    func testWriteDataReturnsTempURLWithCorrectContent() throws {
        let payload = "test-data".data(using: .utf8)!
        let url = try XCTUnwrap(SettingsExporter.writeTempFile(named: "test-data-\(UUID()).bin", data: payload))
        let read = try Data(contentsOf: url)
        XCTAssertEqual(read, payload)
    }

    /// Co sprawdza: Plik jest zapisywany w katalogu tymczasowym systemu.
    func testFileWrittenToTemporaryDirectory() throws {
        let url = try XCTUnwrap(SettingsExporter.writeTempFile(named: "test-tmpdir-\(UUID()).csv", contents: "x"))
        let tmpDir = FileManager.default.temporaryDirectory.standardized
        XCTAssertTrue(url.standardized.path.hasPrefix(tmpDir.path), "Plik powinien być w katalogu tymczasowym")
    }
}

// MARK: - buildMetricsJSON

final class MetricsJSONBuilderTests: XCTestCase {

    private func sampleRow(kindRaw: String = "weight", title: String = "Weight", metricValue: Double = 80.1234, metricUnit: String = "kg", displayValue: Double = 80.12, unit: String = "kg", date: Date = iso("2026-03-15T10:30:00.000Z")) -> SettingsExporter.MetricCSVRowSnapshot {
        SettingsExporter.MetricCSVRowSnapshot(
            kindRaw: kindRaw,
            metricTitle: title,
            metricValue: metricValue,
            metricUnit: metricUnit,
            displayValue: displayValue,
            unit: unit,
            date: date
        )
    }

    private func goalRow(kindRaw: String = "weight", title: String = "Weight", direction: String = "decrease", targetMetricValue: Double = 75.0, targetMetricUnit: String = "kg", targetDisplayValue: Double = 75.0, targetDisplayUnit: String = "kg", startMetricValue: Double? = 85.0, startDisplayValue: Double? = 85.0, startDate: Date? = iso("2025-01-01T08:00:00.000Z"), createdDate: Date = iso("2025-01-01T08:00:00.000Z")) -> SettingsExporter.MetricGoalSnapshot {
        SettingsExporter.MetricGoalSnapshot(
            kindRaw: kindRaw,
            metricTitle: title,
            direction: direction,
            targetMetricValue: targetMetricValue,
            targetMetricUnit: targetMetricUnit,
            targetDisplayValue: targetDisplayValue,
            targetDisplayUnit: targetDisplayUnit,
            startMetricValue: startMetricValue,
            startDisplayValue: startDisplayValue,
            startDate: startDate,
            createdDate: createdDate
        )
    }

    private func parseJSON(_ data: Data) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    /// Co sprawdza: Pusty zestaw danych produkuje poprawny JSON z pustymi tablicami.
    func testEmptyDataReturnsValidJSON() throws {
        let data = try XCTUnwrap(SettingsExporter.buildMetricsJSON(metrics: [], goals: [], unitsSystem: "metric"))
        let json = try parseJSON(data)
        let metrics = json["metrics"] as? [[String: Any]]
        let goals = json["goals"] as? [[String: Any]]
        XCTAssertNotNil(metrics)
        XCTAssertNotNil(goals)
        XCTAssertEqual(metrics?.count, 0)
        XCTAssertEqual(goals?.count, 0)
    }

    /// Co sprawdza: Klucze top-level są obecne.
    func testTopLevelKeysPresent() throws {
        let data = try XCTUnwrap(SettingsExporter.buildMetricsJSON(metrics: [], goals: [], unitsSystem: "metric"))
        let json = try parseJSON(data)
        XCTAssertNotNil(json["exportVersion"])
        XCTAssertNotNil(json["exportDate"])
        XCTAssertNotNil(json["appVersion"])
        XCTAssertNotNil(json["unitsSystem"])
        XCTAssertNotNil(json["metrics"])
        XCTAssertNotNil(json["goals"])
    }

    /// Co sprawdza: unitsSystem jest zapisywany poprawnie.
    func testUnitsSystemStored() throws {
        let data = try XCTUnwrap(SettingsExporter.buildMetricsJSON(metrics: [], goals: [], unitsSystem: "imperial"))
        let json = try parseJSON(data)
        XCTAssertEqual(json["unitsSystem"] as? String, "imperial")
    }

    /// Co sprawdza: Liczba elementów w tablicy metrics odpowiada wejściu.
    func testMetricsArrayMatchesInputCount() throws {
        let rows = [
            sampleRow(kindRaw: "weight"),
            sampleRow(kindRaw: "bodyFat", title: "Body fat", metricUnit: "%", unit: "%"),
            sampleRow(kindRaw: "waist", title: "Waist", metricUnit: "cm", unit: "cm")
        ]
        let data = try XCTUnwrap(SettingsExporter.buildMetricsJSON(metrics: rows, goals: [], unitsSystem: "metric"))
        let json = try parseJSON(data)
        let metrics = json["metrics"] as? [[String: Any]]
        XCTAssertEqual(metrics?.count, 3)
    }

    /// Co sprawdza: Pole metricId odpowiada kindRaw z wejścia.
    func testMetricIdFieldMatchesKindRaw() throws {
        let rows = [sampleRow(kindRaw: "leftBicep", title: "Left bicep")]
        let data = try XCTUnwrap(SettingsExporter.buildMetricsJSON(metrics: rows, goals: [], unitsSystem: "metric"))
        let json = try parseJSON(data)
        let metrics = json["metrics"] as? [[String: Any]]
        XCTAssertEqual(metrics?.first?["metricId"] as? String, "leftBicep")
    }

    /// Co sprawdza: Liczba elementów w tablicy goals odpowiada wejściu.
    func testGoalsArrayMatchesInputCount() throws {
        let goals = [goalRow(), goalRow(kindRaw: "waist", title: "Waist", direction: "decrease")]
        let data = try XCTUnwrap(SettingsExporter.buildMetricsJSON(metrics: [], goals: goals, unitsSystem: "metric"))
        let json = try parseJSON(data)
        let goalsArr = json["goals"] as? [[String: Any]]
        XCTAssertEqual(goalsArr?.count, 2)
    }

    /// Co sprawdza: Opcjonalne pola celu (startValueMetric, startDate) są pomijane gdy nil.
    func testGoalOptionalFieldsAbsentWhenNil() throws {
        let goal = goalRow(startMetricValue: nil, startDisplayValue: nil, startDate: nil)
        let data = try XCTUnwrap(SettingsExporter.buildMetricsJSON(metrics: [], goals: [goal], unitsSystem: "metric"))
        let json = try parseJSON(data)
        let goalsArr = json["goals"] as? [[String: Any]]
        let firstGoal = try XCTUnwrap(goalsArr?.first)
        XCTAssertNil(firstGoal["startValueMetric"])
        XCTAssertNil(firstGoal["startValue"])
        XCTAssertNil(firstGoal["startDate"])
    }

    /// Co sprawdza: exportVersion jest "1.0".
    func testExportVersionIs1_0() throws {
        let data = try XCTUnwrap(SettingsExporter.buildMetricsJSON(metrics: [], goals: [], unitsSystem: "metric"))
        let json = try parseJSON(data)
        XCTAssertEqual(json["exportVersion"] as? String, "1.0")
    }

    /// Co sprawdza: Pole timestamp w metryce jest poprawnym ISO 8601 z milisekundami.
    func testTimestampFieldIsISO8601() throws {
        let inputDate = iso("2026-03-15T10:30:45.123Z")
        let rows = [sampleRow(date: inputDate)]
        let data = try XCTUnwrap(SettingsExporter.buildMetricsJSON(metrics: rows, goals: [], unitsSystem: "metric"))
        let json = try parseJSON(data)
        let metrics = try XCTUnwrap(json["metrics"] as? [[String: Any]])
        let timestamp = try XCTUnwrap(metrics.first?["timestamp"] as? String)
        // Musi parsować się z powrotem do tej samej daty
        let parsed = isoFormatter.date(from: timestamp)
        XCTAssertNotNil(parsed, "timestamp powinien być poprawnym ISO 8601")
        XCTAssertEqual(parsed!.timeIntervalSince1970, inputDate.timeIntervalSince1970, accuracy: 0.01)
    }

    /// Co sprawdza: valueMetric jest zaokrąglone do 4 miejsc po przecinku.
    func testMetricValueRoundedTo4Decimals() throws {
        let rows = [sampleRow(metricValue: 80.12345678)]
        let data = try XCTUnwrap(SettingsExporter.buildMetricsJSON(metrics: rows, goals: [], unitsSystem: "metric"))
        let json = try parseJSON(data)
        let metrics = try XCTUnwrap(json["metrics"] as? [[String: Any]])
        let value = try XCTUnwrap(metrics.first?["valueMetric"] as? Double)
        XCTAssertEqual(value, 80.1235, accuracy: 0.00001, "valueMetric powinno być zaokrąglone do 4 miejsc")
    }

    /// Co sprawdza: value (display) jest zaokrąglone do 2 miejsc po przecinku.
    func testDisplayValueRoundedTo2Decimals() throws {
        let rows = [sampleRow(displayValue: 176.456)]
        let data = try XCTUnwrap(SettingsExporter.buildMetricsJSON(metrics: rows, goals: [], unitsSystem: "metric"))
        let json = try parseJSON(data)
        let metrics = try XCTUnwrap(json["metrics"] as? [[String: Any]])
        let value = try XCTUnwrap(metrics.first?["value"] as? Double)
        XCTAssertEqual(value, 176.46, accuracy: 0.001, "value powinno być zaokrąglone do 2 miejsc")
    }

    /// Co sprawdza: Gdy opcjonalne pola celu nie są nil, są obecne w JSON.
    func testGoalWithAllOptionalFieldsPresent() throws {
        let goal = goalRow(startMetricValue: 85.0, startDisplayValue: 85.0, startDate: iso("2025-06-01T00:00:00.000Z"))
        let data = try XCTUnwrap(SettingsExporter.buildMetricsJSON(metrics: [], goals: [goal], unitsSystem: "metric"))
        let json = try parseJSON(data)
        let goalsArr = try XCTUnwrap(json["goals"] as? [[String: Any]])
        let firstGoal = try XCTUnwrap(goalsArr.first)
        XCTAssertNotNil(firstGoal["startValueMetric"], "startValueMetric powinno być obecne gdy nie nil")
        XCTAssertNotNil(firstGoal["startValue"], "startValue powinno być obecne gdy nie nil")
        XCTAssertNotNil(firstGoal["startDate"], "startDate powinno być obecne gdy nie nil")
    }
}

// MARK: - buildMetricsPDF

final class MetricsPDFBuilderTests: XCTestCase {

    private func sampleRow(kindRaw: String = "weight", title: String = "Weight", displayValue: Double = 80.0, unit: String = "kg", date: Date = iso("2026-03-15T10:30:00.000Z")) -> SettingsExporter.MetricCSVRowSnapshot {
        SettingsExporter.MetricCSVRowSnapshot(
            kindRaw: kindRaw,
            metricTitle: title,
            metricValue: displayValue,
            metricUnit: "kg",
            displayValue: displayValue,
            unit: unit,
            date: date
        )
    }

    /// Co sprawdza: PDF builder zwraca niepuste dane.
    func testPDFDataIsNonEmpty() {
        let data = SettingsExporter.buildMetricsPDF(
            metrics: [sampleRow()],
            goals: [],
            unitsSystem: "metric",
            dateRange: (start: nil, end: Date()),
            logoImage: nil
        )
        XCTAssertFalse(data.isEmpty)
    }

    /// Co sprawdza: Dane zaczynają się od magic bytes %PDF.
    func testPDFDataStartsWithPDFMagicBytes() {
        let data = SettingsExporter.buildMetricsPDF(
            metrics: [sampleRow()],
            goals: [],
            unitsSystem: "metric",
            dateRange: (start: nil, end: Date()),
            logoImage: nil
        )
        let prefix = String(data: data.prefix(5), encoding: .ascii) ?? ""
        XCTAssertTrue(prefix.hasPrefix("%PDF"), "PDF data should start with %PDF magic bytes")
    }

    /// Co sprawdza: Puste dane produkują poprawny PDF (nie crash).
    func testEmptyDataProducesValidPDF() {
        let data = SettingsExporter.buildMetricsPDF(
            metrics: [],
            goals: [],
            unitsSystem: "metric",
            dateRange: (start: nil, end: Date()),
            logoImage: nil
        )
        XCTAssertFalse(data.isEmpty)
        let prefix = String(data: data.prefix(5), encoding: .ascii) ?? ""
        XCTAssertTrue(prefix.hasPrefix("%PDF"))
    }

    /// Co sprawdza: nil logoImage nie powoduje crash.
    func testPDFWithNilLogoDoesNotCrash() {
        let data = SettingsExporter.buildMetricsPDF(
            metrics: [sampleRow(), sampleRow(kindRaw: "waist", title: "Waist", displayValue: 82.5, unit: "cm")],
            goals: [],
            unitsSystem: "metric",
            dateRange: (start: Date.distantPast, end: Date()),
            logoImage: nil
        )
        XCTAssertFalse(data.isEmpty)
    }

    /// Co sprawdza: PDF z wieloma kategoriami danych i celami produkuje dane > 1KB.
    func testPDFWithGoalsProducesLargerFile() {
        let goal = SettingsExporter.MetricGoalSnapshot(
            kindRaw: "weight",
            metricTitle: "Weight",
            direction: "decrease",
            targetMetricValue: 75.0,
            targetMetricUnit: "kg",
            targetDisplayValue: 75.0,
            targetDisplayUnit: "kg",
            startMetricValue: 85.0,
            startDisplayValue: 85.0,
            startDate: iso("2025-01-01T08:00:00.000Z"),
            createdDate: iso("2025-01-01T08:00:00.000Z")
        )
        let data = SettingsExporter.buildMetricsPDF(
            metrics: [sampleRow()],
            goals: [goal],
            unitsSystem: "metric",
            dateRange: (start: nil, end: Date()),
            logoImage: nil
        )
        XCTAssertGreaterThan(data.count, 1000, "PDF with goals should be larger than 1KB")
    }

    /// Co sprawdza: Dane ze wszystkich 4 kategorii (18 metryk) nie powodują crash.
    func testPDFWithAllCategoriesProducesData() {
        let allKinds: [(String, String, String)] = [
            ("weight", "Weight", "kg"), ("bodyFat", "Body fat", "%"), ("height", "Height", "cm"),
            ("leanBodyMass", "Lean body mass", "kg"), ("waist", "Waist", "cm"),
            ("neck", "Neck", "cm"), ("shoulders", "Shoulders", "cm"),
            ("bust", "Bust", "cm"), ("chest", "Chest", "cm"),
            ("leftBicep", "Left bicep", "cm"), ("rightBicep", "Right bicep", "cm"),
            ("leftForearm", "Left forearm", "cm"), ("rightForearm", "Right forearm", "cm"),
            ("hips", "Hips", "cm"), ("leftThigh", "Left thigh", "cm"),
            ("rightThigh", "Right thigh", "cm"), ("leftCalf", "Left calf", "cm"),
            ("rightCalf", "Right calf", "cm")
        ]
        let rows = allKinds.map { sampleRow(kindRaw: $0.0, title: $0.1, displayValue: 50.0, unit: $0.2) }
        let data = SettingsExporter.buildMetricsPDF(
            metrics: rows,
            goals: [],
            unitsSystem: "metric",
            dateRange: (start: nil, end: Date()),
            logoImage: nil
        )
        XCTAssertFalse(data.isEmpty)
        let prefix = String(data: data.prefix(5), encoding: .ascii) ?? ""
        XCTAssertTrue(prefix.hasPrefix("%PDF"))
    }

    /// Co sprawdza: System imperial nie powoduje crash.
    func testPDFWithImperialUnitsDoesNotCrash() {
        let data = SettingsExporter.buildMetricsPDF(
            metrics: [sampleRow(displayValue: 176.37, unit: "lb")],
            goals: [],
            unitsSystem: "imperial",
            dateRange: (start: nil, end: Date()),
            logoImage: nil
        )
        XCTAssertFalse(data.isEmpty)
    }

    /// Co sprawdza: startDate w przyszłości → puste dane ale poprawny PDF.
    func testPDFWithFutureStartDateProducesValidEmptyPDF() {
        let futureDate = Calendar.current.date(byAdding: .year, value: 10, to: Date())!
        let data = SettingsExporter.buildMetricsPDF(
            metrics: [],
            goals: [],
            unitsSystem: "metric",
            dateRange: (start: futureDate, end: Date()),
            logoImage: nil
        )
        XCTAssertFalse(data.isEmpty)
        let prefix = String(data: data.prefix(5), encoding: .ascii) ?? ""
        XCTAssertTrue(prefix.hasPrefix("%PDF"))
    }

    /// Co sprawdza: 0 metryk + cele → poprawny PDF z sekcją celów.
    func testPDFOnlyGoalsNoMetrics() {
        let goals = (0..<3).map { i in
            SettingsExporter.MetricGoalSnapshot(
                kindRaw: "weight",
                metricTitle: "Weight",
                direction: "decrease",
                targetMetricValue: 70.0 + Double(i),
                targetMetricUnit: "kg",
                targetDisplayValue: 70.0 + Double(i),
                targetDisplayUnit: "kg",
                startMetricValue: nil,
                startDisplayValue: nil,
                startDate: nil,
                createdDate: iso("2025-01-01T08:00:00.000Z")
            )
        }
        let data = SettingsExporter.buildMetricsPDF(
            metrics: [],
            goals: goals,
            unitsSystem: "metric",
            dateRange: (start: nil, end: Date()),
            logoImage: nil
        )
        XCTAssertFalse(data.isEmpty)
    }

    /// Co sprawdza: Duży zbiór danych (200+ pomiarów) generuje większy PDF niż pusty.
    func testPDFLargeDataSetProducesLargerFile() {
        let emptyData = SettingsExporter.buildMetricsPDF(
            metrics: [],
            goals: [],
            unitsSystem: "metric",
            dateRange: (start: nil, end: Date()),
            logoImage: nil
        )
        let baseDate = iso("2026-03-15T10:30:00.000Z")
        var manyRows: [SettingsExporter.MetricCSVRowSnapshot] = []
        for i in 0..<200 {
            let isWeight = i % 2 == 0
            let row = sampleRow(
                kindRaw: isWeight ? "weight" : "waist",
                title: isWeight ? "Weight" : "Waist",
                displayValue: 70.0 + Double(i) * 0.1,
                unit: isWeight ? "kg" : "cm",
                date: baseDate.addingTimeInterval(Double(i) * 86400)
            )
            manyRows.append(row)
        }
        let largeData = SettingsExporter.buildMetricsPDF(
            metrics: manyRows,
            goals: [],
            unitsSystem: "metric",
            dateRange: (start: nil, end: Date()),
            logoImage: nil
        )
        XCTAssertGreaterThan(largeData.count, emptyData.count, "PDF z 200 pomiarami powinien być większy niż pusty")
    }
}

// MARK: - ExportFormat

final class ExportFormatTests: XCTestCase {

    /// Co sprawdza: ExportFormat.allCases zawiera dokładnie 3 elementy.
    func testExportFormatCaseIterable() {
        XCTAssertEqual(SettingsExporter.ExportFormat.allCases.count, 3)
    }

    /// Co sprawdza: rawValues to "csv", "json", "pdf".
    func testExportFormatRawValues() {
        XCTAssertEqual(SettingsExporter.ExportFormat.csv.rawValue, "csv")
        XCTAssertEqual(SettingsExporter.ExportFormat.json.rawValue, "json")
        XCTAssertEqual(SettingsExporter.ExportFormat.pdf.rawValue, "pdf")
    }
}
