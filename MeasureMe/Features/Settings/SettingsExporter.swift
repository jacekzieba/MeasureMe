import SwiftUI
import SwiftData
import HealthKit

/// Serwis eksportu danych — wyekstrahowany z SettingsScreen.
/// Wzorzec: static enum (jak WidgetDataWriter) — brak stanu, czysta logika.
enum SettingsExporter {

    // MARK: - Export Format

    enum ExportFormat: String, CaseIterable, Identifiable {
        case csv, json, pdf
        var id: String { rawValue }
    }

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

    private nonisolated static let posixLocale = Locale(identifier: "en_US_POSIX")

    nonisolated static func buildMetricsCSV(from rows: [MetricCSVRowSnapshot]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // metric_id — stały klucz do importu (MetricKind.rawValue, language-agnostic)
        // value_metric / unit_metric — wartości bazowe (kg/cm/%) — determinizm przy imporcie
        // value / unit — wartości display (lb/in gdy imperial) — wygoda w Excelu
        var lines: [String] = ["metric_id,metric,value_metric,unit_metric,value,unit,timestamp"]
        for row in rows {
            let metricValueStr = String(format: "%.4f", locale: posixLocale, row.metricValue)
            let displayValueStr = String(format: "%.2f", locale: posixLocale, row.displayValue)
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
            let targetMetricStr = String(format: "%.4f", locale: posixLocale, row.targetMetricValue)
            let targetDisplayStr = String(format: "%.2f", locale: posixLocale, row.targetDisplayValue)
            let startMetricStr = row.startMetricValue.map { String(format: "%.4f", locale: posixLocale, $0) } ?? ""
            let startDisplayStr = row.startDisplayValue.map { String(format: "%.2f", locale: posixLocale, $0) } ?? ""
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

    // MARK: - JSON Export

    @MainActor
    static func exportMetricsJSON(context: ModelContext, unitsSystem: String) async -> ExportOutput {
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
        let data = await Task.detached(priority: .userInitiated) {
            SettingsExporter.buildMetricsJSON(metrics: csvRows, goals: goalRows, unitsSystem: unitsSystem)
        }.value
        guard let data, let url = writeTempFile(named: "measureme-data-\(ts).json", data: data) else {
            return ExportOutput(items: [], subject: "")
        }
        return ExportOutput(
            items: [url],
            subject: AppLocalization.string("MeasureMe data export")
        )
    }

    nonisolated static func buildMetricsJSON(
        metrics: [MetricCSVRowSnapshot],
        goals: [MetricGoalSnapshot],
        unitsSystem: String
    ) -> Data? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let bundle = Bundle.main
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"

        let metricsArray: [[String: Any]] = metrics.map { row in
            [
                "metricId": row.kindRaw,
                "metric": row.metricTitle,
                "valueMetric": Double(String(format: "%.4f", locale: posixLocale, row.metricValue))!,
                "unitMetric": row.metricUnit,
                "value": Double(String(format: "%.2f", locale: posixLocale, row.displayValue))!,
                "unit": row.unit,
                "timestamp": iso.string(from: row.date)
            ]
        }

        let goalsArray: [[String: Any]] = goals.map { row in
            var dict: [String: Any] = [
                "metricId": row.kindRaw,
                "metric": row.metricTitle,
                "direction": row.direction,
                "targetValueMetric": Double(String(format: "%.4f", locale: posixLocale, row.targetMetricValue))!,
                "targetUnitMetric": row.targetMetricUnit,
                "targetValue": Double(String(format: "%.2f", locale: posixLocale, row.targetDisplayValue))!,
                "targetUnit": row.targetDisplayUnit,
                "createdDate": iso.string(from: row.createdDate)
            ]
            if let sv = row.startMetricValue {
                dict["startValueMetric"] = Double(String(format: "%.4f", locale: posixLocale, sv))!
            }
            if let sd = row.startDisplayValue {
                dict["startValue"] = Double(String(format: "%.2f", locale: posixLocale, sd))!
            }
            if let sdate = row.startDate {
                dict["startDate"] = iso.string(from: sdate)
            }
            return dict
        }

        let payload: [String: Any] = [
            "exportVersion": "1.0",
            "exportDate": iso.string(from: AppClock.now),
            "appVersion": appVersion,
            "unitsSystem": unitsSystem,
            "metrics": metricsArray,
            "goals": goalsArray
        ]

        return try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - PDF Export

    /// Kategorie metryk do grupowania w raporcie PDF.
    nonisolated static let metricCategories: [(title: String, kinds: [MetricKind])] = [
        ("Body Composition & Size", [.weight, .bodyFat, .height, .leanBodyMass, .waist]),
        ("Upper Body", [.neck, .shoulders, .bust, .chest]),
        ("Arms", [.leftBicep, .rightBicep, .leftForearm, .rightForearm]),
        ("Lower Body", [.hips, .leftThigh, .rightThigh, .leftCalf, .rightCalf])
    ]

    struct PDFMetricSummary {
        let kind: MetricKind
        let latestValue: Double
        let latestDate: Date
        let minValue: Double
        let maxValue: Double
        let avgValue: Double
        let count: Int
    }

    @MainActor
    static func exportMetricsPDF(
        context: ModelContext,
        unitsSystem: String,
        startDate: Date?
    ) async -> ExportOutput {
        let allSamples = fetchAllMetricSamplesSorted(context: context)
        let goalsSnapshot = fetchAllGoals(context: context)

        let filtered: [MetricSampleSnapshot]
        if let startDate {
            filtered = allSamples.filter { $0.date >= startDate }
        } else {
            filtered = allSamples
        }

        let csvRows: [MetricCSVRowSnapshot] = filtered.compactMap { sample in
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

        let logoImage = UIImage(named: "BrandMark")
        let dateRange: (start: Date?, end: Date) = (startDate, AppClock.now)
        let ts = timestampString()

        let data = await Task.detached(priority: .userInitiated) {
            SettingsExporter.buildMetricsPDF(
                metrics: csvRows,
                goals: goalRows,
                unitsSystem: unitsSystem,
                dateRange: dateRange,
                logoImage: logoImage
            )
        }.value

        guard let url = writeTempFile(named: "measureme-report-\(ts).pdf", data: data) else {
            return ExportOutput(items: [], subject: "")
        }
        return ExportOutput(
            items: [url],
            subject: AppLocalization.string("MeasureMe data export")
        )
    }

    nonisolated static func buildMetricsPDF(
        metrics: [MetricCSVRowSnapshot],
        goals: [MetricGoalSnapshot],
        unitsSystem: String,
        dateRange: (start: Date?, end: Date),
        logoImage: UIImage?
    ) -> Data {
        let pageWidth: CGFloat = 595.28
        let pageHeight: CGFloat = 841.89
        let margin: CGFloat = 40
        let contentWidth = pageWidth - margin * 2
        let footerHeight: CGFloat = 30
        let maxY = pageHeight - margin - footerHeight

        let navyColor = UIColor(red: 0x14 / 255.0, green: 0x21 / 255.0, blue: 0x3D / 255.0, alpha: 1)
        let accentColor = UIColor(red: 0xFC / 255.0, green: 0xA3 / 255.0, blue: 0x11 / 255.0, alpha: 1)
        let grayColor = UIColor.secondaryLabel
        let lightGrayBg = UIColor.systemGray6

        let titleFont = UIFont.systemFont(ofSize: 22, weight: .bold)
        let subtitleFont = UIFont.systemFont(ofSize: 11, weight: .regular)
        let sectionFont = UIFont.systemFont(ofSize: 14, weight: .bold)
        let bodyFont = UIFont.systemFont(ofSize: 10, weight: .regular)
        let bodyBoldFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let footerFont = UIFont.systemFont(ofSize: 8, weight: .regular)

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        var pageNumber = 1
        var _ = 1 // Estimated, will draw footer at end

        // Build summaries grouped by metric
        let grouped = Dictionary(grouping: metrics) { $0.kindRaw }
        var summaries: [PDFMetricSummary] = []
        for (kindRaw, rows) in grouped {
            guard let kind = MetricKind(rawValue: kindRaw), !rows.isEmpty else { continue }
            let values = rows.map { $0.displayValue }
            let sorted = rows.sorted { $0.date < $1.date }
            guard let latest = sorted.last,
                  let minValue = values.min(),
                  let maxValue = values.max() else { continue }
            summaries.append(PDFMetricSummary(
                kind: kind,
                latestValue: latest.displayValue,
                latestDate: latest.date,
                minValue: minValue,
                maxValue: maxValue,
                avgValue: values.reduce(0, +) / Double(values.count),
                count: values.count
            ))
        }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            var y: CGFloat = 0

            func beginNewPage() {
                context.beginPage()
                pageNumber += 1
                y = margin
            }

            func ensureSpace(_ needed: CGFloat) {
                if y + needed > maxY {
                    drawFooter(context: context.cgContext, pageNumber: pageNumber)
                    beginNewPage()
                }
            }

            func drawFooter(context: CGContext, pageNumber: Int) {
                let footerY = pageHeight - margin - 5
                let footerText = AppLocalization.string("Generated by MeasureMe")
                let footerAttrs: [NSAttributedString.Key: Any] = [
                    .font: footerFont,
                    .foregroundColor: grayColor
                ]
                let footerStr = NSAttributedString(string: footerText, attributes: footerAttrs)
                let footerSize = footerStr.size()
                footerStr.draw(at: CGPoint(x: (pageWidth - footerSize.width) / 2, y: footerY))

                let pageText = "Page \(pageNumber)"
                let pageStr = NSAttributedString(string: pageText, attributes: footerAttrs)
                let pageSize = pageStr.size()
                pageStr.draw(at: CGPoint(x: pageWidth - margin - pageSize.width, y: footerY))
            }

            func drawText(_ text: String, font: UIFont, color: UIColor, x: CGFloat, maxWidth: CGFloat) -> CGFloat {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let rect = CGRect(x: x, y: y, width: maxWidth, height: .greatestFiniteMagnitude)
                let boundingRect = (text as NSString).boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
                (text as NSString).draw(in: CGRect(x: x, y: y, width: maxWidth, height: boundingRect.height), withAttributes: attrs)
                return boundingRect.height
            }

            // --- Page 1 ---
            context.beginPage()
            y = margin

            // Logo + Title
            let logoSize: CGFloat = 36
            if let logo = logoImage {
                logo.draw(in: CGRect(x: margin, y: y, width: logoSize, height: logoSize))
            }
            let titleX = margin + logoSize + 10
            let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: navyColor]
            let titleStr = NSAttributedString(string: AppLocalization.string("MeasureMe Report"), attributes: titleAttrs)
            let titleSize = titleStr.size()
            titleStr.draw(at: CGPoint(x: titleX, y: y + (logoSize - titleSize.height) / 2))
            y += logoSize + 8

            // Date range
            let startStr = dateRange.start.map { dateFormatter.string(from: $0) } ?? AppLocalization.string("All time")
            let endStr = dateFormatter.string(from: dateRange.end)
            let rangeText = dateRange.start != nil ? "\(startStr) — \(endStr)" : startStr
            let rangeAttrs: [NSAttributedString.Key: Any] = [.font: subtitleFont, .foregroundColor: grayColor]
            (rangeText as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: rangeAttrs)
            y += 18

            // Accent horizontal rule
            let ctx = context.cgContext
            ctx.setStrokeColor(accentColor.cgColor)
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: margin, y: y))
            ctx.addLine(to: CGPoint(x: pageWidth - margin, y: y))
            ctx.strokePath()
            y += 14

            // --- Summary Tables ---
            if summaries.isEmpty {
                ensureSpace(30)
                let h = drawText(AppLocalization.string("No data in selected range."), font: bodyFont, color: grayColor, x: margin, maxWidth: contentWidth)
                y += h + 10
            } else {
                let colWidths: [CGFloat] = [
                    contentWidth * 0.25,  // Metric
                    contentWidth * 0.15,  // Latest
                    contentWidth * 0.15,  // Min
                    contentWidth * 0.15,  // Max
                    contentWidth * 0.15,  // Avg
                    contentWidth * 0.15   // Count
                ]
                let headers = ["Metric", "Latest", "Min", "Max", "Avg", "Count"]
                let rowHeight: CGFloat = 18

                for (categoryTitle, kinds) in metricCategories {
                    let categoryRows = kinds.compactMap { kind in summaries.first { $0.kind == kind } }
                    guard !categoryRows.isEmpty else { continue }

                    // Category header
                    ensureSpace(rowHeight * 3)
                    y += 6
                    let catH = drawText(categoryTitle, font: sectionFont, color: navyColor, x: margin, maxWidth: contentWidth)
                    y += catH + 6

                    // Table header
                    ensureSpace(rowHeight)
                    var hx = margin
                    for (i, header) in headers.enumerated() {
                        let attrs: [NSAttributedString.Key: Any] = [.font: bodyBoldFont, .foregroundColor: navyColor]
                        (header as NSString).draw(in: CGRect(x: hx + 4, y: y + 2, width: colWidths[i] - 8, height: rowHeight), withAttributes: attrs)
                        hx += colWidths[i]
                    }
                    y += rowHeight

                    // Data rows
                    for (rowIndex, summary) in categoryRows.enumerated() {
                        ensureSpace(rowHeight)

                        // Alternating background
                        if rowIndex % 2 == 1 {
                            ctx.setFillColor(lightGrayBg.cgColor)
                            ctx.fill(CGRect(x: margin, y: y, width: contentWidth, height: rowHeight))
                        }

                        let unitSym = summary.kind.unitSymbol(unitsSystem: unitsSystem)
                        let vals: [String] = [
                            summary.kind.englishTitle,
                            String(format: "%.1f %@", summary.latestValue, unitSym),
                            String(format: "%.1f", summary.minValue),
                            String(format: "%.1f", summary.maxValue),
                            String(format: "%.1f", summary.avgValue),
                            "\(summary.count)"
                        ]
                        var rx = margin
                        for (i, val) in vals.enumerated() {
                            let attrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: UIColor.label]
                            (val as NSString).draw(in: CGRect(x: rx + 4, y: y + 3, width: colWidths[i] - 8, height: rowHeight), withAttributes: attrs)
                            rx += colWidths[i]
                        }
                        y += rowHeight
                    }
                }
            }

            // --- Goals Section ---
            let goalsWithData = goals.filter { !$0.kindRaw.isEmpty }
            if !goalsWithData.isEmpty {
                y += 10
                ensureSpace(40)
                let goalH = drawText(AppLocalization.string("Goals"), font: sectionFont, color: navyColor, x: margin, maxWidth: contentWidth)
                y += goalH + 6

                let goalColWidths: [CGFloat] = [
                    contentWidth * 0.25,  // Metric
                    contentWidth * 0.20,  // Direction
                    contentWidth * 0.25,  // Target
                    contentWidth * 0.30   // Created
                ]
                let goalHeaders = ["Metric", "Direction", "Target", "Created"]
                let rowHeight: CGFloat = 18

                ensureSpace(rowHeight)
                var hx = margin
                for (i, header) in goalHeaders.enumerated() {
                    let attrs: [NSAttributedString.Key: Any] = [.font: bodyBoldFont, .foregroundColor: navyColor]
                    (header as NSString).draw(in: CGRect(x: hx + 4, y: y + 2, width: goalColWidths[i] - 8, height: rowHeight), withAttributes: attrs)
                    hx += goalColWidths[i]
                }
                y += rowHeight

                for (rowIndex, goal) in goalsWithData.enumerated() {
                    ensureSpace(rowHeight)
                    if rowIndex % 2 == 1 {
                        ctx.setFillColor(lightGrayBg.cgColor)
                        ctx.fill(CGRect(x: margin, y: y, width: contentWidth, height: rowHeight))
                    }
                    let vals: [String] = [
                        goal.metricTitle,
                        goal.direction.capitalized,
                        String(format: "%.1f %@", goal.targetDisplayValue, goal.targetDisplayUnit),
                        dateFormatter.string(from: goal.createdDate)
                    ]
                    var rx = margin
                    for (i, val) in vals.enumerated() {
                        let attrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: UIColor.label]
                        (val as NSString).draw(in: CGRect(x: rx + 4, y: y + 3, width: goalColWidths[i] - 8, height: rowHeight), withAttributes: attrs)
                        rx += goalColWidths[i]
                    }
                    y += rowHeight
                }
            }

            // Draw footer on the last page
            drawFooter(context: context.cgContext, pageNumber: pageNumber)
        }

        return data
    }
}
