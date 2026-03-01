import SwiftUI
import SwiftData
import HealthKit

/// Serwis eksportu danych — wyekstrahowany z SettingsScreen.
/// Wzorzec: static enum (jak WidgetDataWriter) — brak stanu, czysta logika.
enum SettingsExporter {

    // MARK: - Output

    struct ExportOutput {
        let items: [Any]
        let subject: String
    }

    // MARK: - Snapshot types

    struct MetricSampleSnapshot: Sendable {
        let kindRaw: String
        let value: Double
        let date: Date
    }

    struct MetricCSVRowSnapshot: Sendable {
        let kindRaw: String           // MetricKind.rawValue — klucz do importu
        let metricTitle: String       // englishTitle — czytelna etykieta (zawsze EN)
        let metricValue: Double       // wartość w jednostkach bazowych (kg/cm/%)
        let metricUnit: String        // jednostka bazowa (kg/cm/%)
        let displayValue: Double      // wartość w jednostkach display
        let unit: String              // jednostka display
        let date: Date
    }

    struct MetricGoalSnapshot: Sendable {
        let kindRaw: String
        let metricTitle: String       // englishTitle
        let direction: String         // "increase" lub "decrease"
        let targetMetricValue: Double // wartość celu w jednostkach bazowych
        let targetMetricUnit: String  // jednostka bazowa celu
        let targetDisplayValue: Double
        let targetDisplayUnit: String
        let startMetricValue: Double? // opcjonalny punkt startowy (bazowy)
        let startDisplayValue: Double?
        let startDate: Date?
        let createdDate: Date
    }

    struct GoalFetchSnapshot: Sendable {
        let kindRaw: String
        let directionRaw: String
        let targetValue: Double
        let startMetricValue: Double?
        let startDate: Date?
        let createdDate: Date
    }

    struct DeviceSnapshot: Sendable {
        let systemName: String
        let systemVersion: String
        let model: String
    }

    // MARK: - Main export methods

    @MainActor
    static func exportMetrics(context: ModelContext, unitsSystem: String) async -> ExportOutput {
        let samplesSnapshot = fetchAllMetricSamplesSorted(context: context)
        let goalsSnapshot = fetchAllGoals(context: context)
        let csvRows: [MetricCSVRowSnapshot] = samplesSnapshot.compactMap { sample in
            guard let kind = MetricKind(rawValue: sample.kindRaw) else { return nil }
            let metricUnit: String
            switch kind.unitCategory {
            case .weight: metricUnit = "kg"
            case .length: metricUnit = "cm"
            case .percent: metricUnit = "%"
            }
            return MetricCSVRowSnapshot(
                kindRaw: sample.kindRaw,
                metricTitle: kind.englishTitle,
                metricValue: sample.value,
                metricUnit: metricUnit,
                displayValue: kind.valueForDisplay(fromMetric: sample.value, unitsSystem: unitsSystem),
                unit: kind.unitSymbol(unitsSystem: unitsSystem),
                date: sample.date
            )
        }
        let goalRows: [MetricGoalSnapshot] = goalsSnapshot.compactMap { goal in
            guard let kind = MetricKind(rawValue: goal.kindRaw) else { return nil }
            let metricUnit: String
            switch kind.unitCategory {
            case .weight: metricUnit = "kg"
            case .length: metricUnit = "cm"
            case .percent: metricUnit = "%"
            }
            let startDisplay = goal.startMetricValue.map {
                kind.valueForDisplay(fromMetric: $0, unitsSystem: unitsSystem)
            }
            return MetricGoalSnapshot(
                kindRaw: goal.kindRaw,
                metricTitle: kind.englishTitle,
                direction: goal.directionRaw,
                targetMetricValue: goal.targetValue,
                targetMetricUnit: metricUnit,
                targetDisplayValue: kind.valueForDisplay(fromMetric: goal.targetValue, unitsSystem: unitsSystem),
                targetDisplayUnit: kind.unitSymbol(unitsSystem: unitsSystem),
                startMetricValue: goal.startMetricValue,
                startDisplayValue: startDisplay,
                startDate: goal.startDate,
                createdDate: goal.createdDate
            )
        }
        let ts = timestampString()
        let (metricsCSV, goalsCSV) = await Task.detached(priority: .userInitiated) {
            (SettingsExporter.buildMetricsCSV(from: csvRows),
             SettingsExporter.buildGoalsCSV(from: goalRows))
        }.value
        let metricsURL = writeTempFile(named: "measureme-metrics-\(ts).csv", contents: metricsCSV)
        let goalsURL = writeTempFile(named: "measureme-goals-\(ts).csv", contents: goalsCSV)
        var items: [Any] = []
        if let u = metricsURL { items.append(u) }
        if let u = goalsURL { items.append(u) }
        return ExportOutput(
            items: items,
            subject: AppLocalization.string("MeasureMe data export")
        )
    }

    @MainActor
    static func exportDiagnostics(
        context: ModelContext,
        isSyncEnabled: Bool,
        lastHealthImportTimestamp: Double
    ) async -> ExportOutput {
        let sampleSnapshot = fetchAllMetricSamplesSorted(context: context)
        let photoCount = fetchPhotosCount(context: context)
        let deviceSnapshot = DeviceSnapshot(
            systemName: UIDevice.current.systemName,
            systemVersion: UIDevice.current.systemVersion,
            model: UIDevice.current.model
        )
        let data = await Task.detached(priority: .userInitiated) {
            SettingsExporter.buildDiagnosticsJSON(
                samples: sampleSnapshot,
                photosCount: photoCount,
                isSyncEnabled: isSyncEnabled,
                lastHealthImportTimestamp: lastHealthImportTimestamp,
                device: deviceSnapshot
            )
        }.value
        let fileName = "measureme-diagnostics-\(timestampString()).json"
        guard let data, let url = writeTempFile(named: fileName, data: data) else {
            return ExportOutput(items: [], subject: "")
        }
        return ExportOutput(
            items: [url, AppLocalization.string("Send diagnostics to ziebajacek@pm.me")],
            subject: AppLocalization.string("MeasureMe diagnostics")
        )
    }

    // MARK: - Fetchers

    @MainActor
    static func fetchAllMetricSamplesSorted(context: ModelContext) -> [MetricSampleSnapshot] {
        let descriptor = FetchDescriptor<MetricSample>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let samples = (try? context.fetch(descriptor)) ?? []
        return samples.map {
            MetricSampleSnapshot(kindRaw: $0.kindRaw, value: $0.value, date: $0.date)
        }
    }

    @MainActor
    static func fetchAllGoals(context: ModelContext) -> [GoalFetchSnapshot] {
        let descriptor = FetchDescriptor<MetricGoal>(
            sortBy: [SortDescriptor(\.kindRaw, order: .forward)]
        )
        let goals = (try? context.fetch(descriptor)) ?? []
        return goals.map {
            GoalFetchSnapshot(
                kindRaw: $0.kindRaw,
                directionRaw: $0.directionRaw,
                targetValue: $0.targetValue,
                startMetricValue: $0.startValue,
                startDate: $0.startDate,
                createdDate: $0.createdDate
            )
        }
    }

    @MainActor
    static func fetchPhotosCount(context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<PhotoEntry>()
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    // MARK: - CSV Builders

    nonisolated static func buildMetricsCSV(from rows: [MetricCSVRowSnapshot]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // metric_id — stały klucz do importu (MetricKind.rawValue, language-agnostic)
        // value_metric / unit_metric — wartości bazowe (kg/cm/%) — determinizm przy imporcie
        // value / unit — wartości display (lb/in gdy imperial) — wygoda w Excelu
        var lines: [String] = ["metric_id,metric,value_metric,unit_metric,value,unit,timestamp"]
        for row in rows {
            let metricValueStr = String(format: "%.4f", row.metricValue)
            let displayValueStr = String(format: "%.2f", row.displayValue)
            let dateString = formatter.string(from: row.date)
            lines.append([
                csvField(row.kindRaw),
                csvField(row.metricTitle),
                metricValueStr,
                csvField(row.metricUnit),
                displayValueStr,
                csvField(row.unit),
                dateString
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    nonisolated static func buildGoalsCSV(from rows: [MetricGoalSnapshot]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lines: [String] = [
            "metric_id,metric,direction,target_value_metric,target_unit_metric,target_value,target_unit,start_value_metric,start_value,start_date,created_date"
        ]
        for row in rows {
            let targetMetricStr = String(format: "%.4f", row.targetMetricValue)
            let targetDisplayStr = String(format: "%.2f", row.targetDisplayValue)
            let startMetricStr = row.startMetricValue.map { String(format: "%.4f", $0) } ?? ""
            let startDisplayStr = row.startDisplayValue.map { String(format: "%.2f", $0) } ?? ""
            let startDateStr = row.startDate.map { formatter.string(from: $0) } ?? ""
            let createdStr = formatter.string(from: row.createdDate)
            lines.append([
                csvField(row.kindRaw),
                csvField(row.metricTitle),
                csvField(row.direction),
                targetMetricStr,
                csvField(row.targetMetricUnit),
                targetDisplayStr,
                csvField(row.targetDisplayUnit),
                startMetricStr,
                startDisplayStr,
                startDateStr,
                createdStr
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    nonisolated static func buildDiagnosticsJSON(
        samples: [MetricSampleSnapshot],
        photosCount: Int,
        isSyncEnabled: Bool,
        lastHealthImportTimestamp: Double,
        device: DeviceSnapshot
    ) -> Data? {
        let bundle = Bundle.main
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let now = AppClock.now
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let metricCounts = Dictionary(grouping: samples) { $0.kindRaw }
            .mapValues { $0.count }

        let healthKitStatus = healthKitStatusText()
        let lastSync = lastHealthImportTimestamp > 0 ? iso.string(from: Date(timeIntervalSince1970: lastHealthImportTimestamp)) : nil

        let payload: [String: Any] = [
            "timestamp": iso.string(from: now),
            "appVersion": appVersion,
            "buildNumber": buildNumber,
            "system": "\(device.systemName) \(device.systemVersion)",
            "deviceModel": device.model,
            "metricsCount": samples.count,
            "metricsByKind": metricCounts,
            "photosCount": photosCount,
            "healthKit": [
                "available": HKHealthStore.isHealthDataAvailable(),
                "syncEnabled": isSyncEnabled,
                "authorizationStatus": healthKitStatus,
                "lastSync": lastSync as Any
            ]
        ]

        return try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - Helpers

    /// Escapuje pole CSV zgodnie z RFC 4180 — otacza cudzysłowami jeśli zawiera przecinek, cudzysłów lub nową linię.
    nonisolated static func csvField(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        guard needsQuoting else { return value }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    nonisolated static func healthKitStatusText() -> String {
        guard HKHealthStore.isHealthDataAvailable() else { return "unavailable" }
        guard let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return "unknown" }
        let status = HKHealthStore().authorizationStatus(for: type)
        switch status {
        case .notDetermined: return "notDetermined"
        case .sharingDenied: return "denied"
        case .sharingAuthorized: return "authorized"
        @unknown default: return "unknown"
        }
    }

    static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: AppClock.now)
    }

    nonisolated static func writeTempFile(named name: String, contents: String) -> URL? {
        guard let data = contents.data(using: .utf8) else { return nil }
        return writeTempFile(named: name, data: data)
    }

    nonisolated static func writeTempFile(named name: String, data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            AppLog.debug("⚠️ Failed to write export file: \(error.localizedDescription)")
            return nil
        }
    }
}
