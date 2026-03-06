import SwiftUI
import SwiftData

/// Serwis importu danych CSV — wyekstrahowany z SettingsScreen.
/// Wzorzec: static enum (jak WidgetDataWriter) — brak stanu, czysta logika.
enum SettingsImporter {

    // MARK: - Types

    enum Strategy { case merge, replace }
    enum CSVKind { case metrics, goals }

    enum ImportError: LocalizedError, Equatable {
        case noSupportedCSVFiles
        case invalidCSVSchema
        case fileReadFailed
        case persistenceFailed

        var errorDescription: String? {
            switch self {
            case .noSupportedCSVFiles:
                return AppLocalization.string("import.error.no_supported_files")
            case .invalidCSVSchema:
                return AppLocalization.string("import.error.invalid_schema")
            case .fileReadFailed:
                return AppLocalization.string("import.error.file_read_failed")
            case .persistenceFailed:
                return AppLocalization.string("import.error.persistence_failed")
            }
        }
    }

    struct ImportResult {
        var samplesInserted: Int = 0
        var goalsInserted: Int = 0
        var goalsUpdated: Int = 0
        var rowsSkipped: Int = 0
    }

    struct ParsedSampleRow {
        let kindRaw: String
        let value: Double   // value_metric — wartość bazowa (kg/cm/%)
        let date: Date
    }

    struct MetricsParseResult {
        var rows: [ParsedSampleRow] = []
        var skipped: Int = 0
        nonisolated init() { rows = []; skipped = 0 }
    }

    struct ParsedGoalRow {
        let kindRaw: String
        let direction: String
        let targetValue: Double     // target_value_metric
        let startValue: Double?     // start_value_metric (opcjonalne)
        let startDate: Date?
        let createdDate: Date
    }

    struct GoalsParseResult {
        var rows: [ParsedGoalRow] = []
        var skipped: Int = 0
        nonisolated init() { rows = []; skipped = 0 }
    }

    private nonisolated static let metricsRequiredColumns: Set<String> = [
        "metric_id",
        "value_metric",
        "timestamp"
    ]

    private nonisolated static let goalsRequiredColumns: Set<String> = [
        "metric_id",
        "direction",
        "target_value_metric",
        "created_date"
    ]

    private nonisolated static let knownImportColumns: Set<String> = [
        "metric_id",
        "metric",
        "value_metric",
        "unit_metric",
        "value",
        "unit",
        "timestamp",
        "direction",
        "target_value_metric",
        "target_unit_metric",
        "target_value",
        "target_unit",
        "start_value_metric",
        "start_value",
        "start_date",
        "created_date"
    ]

    // MARK: - Main import method

    /// Importuje dane z podanych URL-i i zwraca gotowy komunikat o wyniku.
    @MainActor
    static func importData(urls: [URL], strategy: Strategy, context: ModelContext) async throws -> String {
        var result = ImportResult()
        var parsedSampleRows: [ParsedSampleRow] = []
        var parsedGoalRows: [ParsedGoalRow] = []
        var supportedFilesCount = 0

        for url in urls {
            let content = try loadCSVContent(url: url)
            guard let kind = try detectCSVKind(content: content) else { continue }
            supportedFilesCount += 1

            switch kind {
            case .metrics:
                let parseResult = await Task.detached(priority: .userInitiated) {
                    SettingsImporter.parseMetricsCSV(content: content)
                }.value
                parsedSampleRows.append(contentsOf: parseResult.rows)
                result.rowsSkipped += parseResult.skipped
            case .goals:
                let parseResult = await Task.detached(priority: .userInitiated) {
                    SettingsImporter.parseGoalsCSV(content: content)
                }.value
                parsedGoalRows.append(contentsOf: parseResult.rows)
                result.rowsSkipped += parseResult.skipped
            }
        }

        guard supportedFilesCount > 0 else {
            throw ImportError.noSupportedCSVFiles
        }

        do {
            if strategy == .replace {
                let sampleDescriptor = FetchDescriptor<MetricSample>()
                let goalDescriptor = FetchDescriptor<MetricGoal>()
                let existingSamples = try context.fetch(sampleDescriptor)
                let existingGoals = try context.fetch(goalDescriptor)
                existingSamples.forEach { context.delete($0) }
                existingGoals.forEach { context.delete($0) }
            }

            insertSamples(parsedSampleRows, strategy: strategy, context: context, result: &result)
            insertGoals(parsedGoalRows, strategy: strategy, context: context, result: &result)
            try context.save()
        } catch {
            AppLog.debug("⚠️ SettingsImporter persistence failed: \(error)")
            throw ImportError.persistenceFailed
        }

        var msg = String(format: AppLocalization.string("Imported %d measurements and %d goals."),
                         result.samplesInserted, result.goalsInserted + result.goalsUpdated)
        if result.rowsSkipped > 0 {
            msg += " " + String(format: AppLocalization.string("%d rows skipped."), result.rowsSkipped)
        }
        return msg
    }

    // MARK: - CSV Parsers

    nonisolated static func detectCSVKind(url: URL) throws -> CSVKind? {
        let content = try loadCSVContent(url: url)
        return try detectCSVKind(content: content)
    }

    nonisolated static func parseMetricsCSV(url: URL) -> MetricsParseResult {
        guard let content = try? loadCSVContent(url: url) else {
            return MetricsParseResult()
        }
        return parseMetricsCSV(content: content)
    }

    nonisolated static func parseGoalsCSV(url: URL) -> GoalsParseResult {
        guard let content = try? loadCSVContent(url: url) else {
            return GoalsParseResult()
        }
        return parseGoalsCSV(content: content)
    }

    nonisolated static func parseCSVNumber(_ raw: String) -> Double? {
        if let value = Double(raw) {
            return value
        }

        if raw.contains(","), !raw.contains(".") {
            return Double(raw.replacingOccurrences(of: ",", with: "."))
        }

        return nil
    }

    // MARK: - Internal parser implementations

    private nonisolated static func parseMetricsCSV(content: String) -> MetricsParseResult {
        var result = MetricsParseResult()
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
            guard let value = parseCSVNumber(fields[idxVal]) else { result.skipped += 1; continue }
            let tsString = fields[idxTs]
            guard let date = isoFull.date(from: tsString) ?? isoBasic.date(from: tsString)
            else { result.skipped += 1; continue }
            result.rows.append(ParsedSampleRow(kindRaw: kindRaw, value: value, date: date))
        }
        return result
    }

    private nonisolated static func parseGoalsCSV(content: String) -> GoalsParseResult {
        var result = GoalsParseResult()
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

            guard let targetValue = parseCSVNumber(fields[idxTarget]) else { result.skipped += 1; continue }

            let createdStr = fields[idxCreated]
            guard let createdDate = isoFull.date(from: createdStr) ?? isoBasic.date(from: createdStr)
            else { result.skipped += 1; continue }

            var startValue: Double? = nil
            if let idx = idxStartVal, idx < fields.count, !fields[idx].isEmpty {
                startValue = parseCSVNumber(fields[idx])
            }
            var startDate: Date? = nil
            if let idx = idxStartDate, idx < fields.count, !fields[idx].isEmpty {
                startDate = isoFull.date(from: fields[idx]) ?? isoBasic.date(from: fields[idx])
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

    /// RFC 4180 CSV line splitter — obsługuje pola w cudzysłowach i podwójne cudzysłowy.
    nonisolated static func parseCSVLine(_ line: String) -> [String] {
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
                    // pomiń CR w CRLF
                } else {
                    current.append(c)
                }
            }
            idx = line.index(after: idx)
        }
        fields.append(current)
        return fields
    }

    private nonisolated static func loadCSVContent(url: URL) throws -> String {
        guard url.startAccessingSecurityScopedResource() else {
            throw ImportError.fileReadFailed
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ImportError.fileReadFailed
        }
    }

    private nonisolated static func detectCSVKind(content: String) throws -> CSVKind? {
        guard let headerLine = firstNonEmptyLine(in: content) else { return nil }
        let columns = Set(parseCSVLine(headerLine).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        if metricsRequiredColumns.isSubset(of: columns) {
            return .metrics
        }
        if goalsRequiredColumns.isSubset(of: columns) {
            return .goals
        }
        if !columns.isDisjoint(with: knownImportColumns) {
            throw ImportError.invalidCSVSchema
        }
        return nil
    }

    private nonisolated static func firstNonEmptyLine(in content: String) -> String? {
        content
            .components(separatedBy: "\n")
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - SwiftData Insert helpers

    @MainActor
    static func insertSamples(
        _ rows: [ParsedSampleRow],
        strategy: Strategy,
        context: ModelContext,
        result: inout ImportResult
    ) {
        var existingKeys = Set<String>()
        if strategy == .merge {
            let descriptor = FetchDescriptor<MetricSample>()
            let existing = (try? context.fetch(descriptor)) ?? []
            for s in existing {
                let epoch = Int(s.date.timeIntervalSince1970)
                existingKeys.insert("\(s.kindRaw)_\(epoch)")
            }
        }
        for row in rows {
            if strategy == .merge {
                let epoch = Int(row.date.timeIntervalSince1970)
                let key = "\(row.kindRaw)_\(epoch)"
                if existingKeys.contains(key) { continue }
                existingKeys.insert(key)
            }
            guard let kind = MetricKind(rawValue: row.kindRaw) else { continue }
            context.insert(MetricSample(kind: kind, value: row.value, date: row.date))
            result.samplesInserted += 1
        }
    }

    @MainActor
    static func insertGoals(
        _ rows: [ParsedGoalRow],
        strategy: Strategy,
        context: ModelContext,
        result: inout ImportResult
    ) {
        let descriptor = FetchDescriptor<MetricGoal>()
        let existing = (try? context.fetch(descriptor)) ?? []
        var existingByKind = Dictionary(uniqueKeysWithValues: existing.map { ($0.kindRaw, $0) })

        for row in rows {
            guard let kind = MetricKind(rawValue: row.kindRaw),
                  let direction = MetricGoal.Direction(rawValue: row.direction)
            else { continue }

            if let existingGoal = existingByKind[row.kindRaw] {
                existingGoal.targetValue = row.targetValue
                existingGoal.directionRaw = row.direction
                existingGoal.startValue = row.startValue
                existingGoal.startDate = row.startDate
                existingGoal.createdDate = row.createdDate
                result.goalsUpdated += 1
            } else {
                let newGoal = MetricGoal(
                    kind: kind,
                    targetValue: row.targetValue,
                    direction: direction,
                    createdDate: row.createdDate,
                    startValue: row.startValue,
                    startDate: row.startDate
                )
                context.insert(newGoal)
                existingByKind[row.kindRaw] = newGoal
                result.goalsInserted += 1
            }
        }
    }
}
