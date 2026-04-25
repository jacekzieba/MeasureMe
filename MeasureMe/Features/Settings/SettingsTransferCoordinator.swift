import Foundation
import SwiftData

@MainActor
enum SettingsTransferCoordinator {
    struct Dependencies {
        var exportMetrics: (ModelContext, String) async -> SettingsExporter.ExportOutput = { context, unitsSystem in
            await SettingsExporter.exportMetrics(context: context, unitsSystem: unitsSystem)
        }
        var exportMetricsJSON: (ModelContext, String) async -> SettingsExporter.ExportOutput = { context, unitsSystem in
            await SettingsExporter.exportMetricsJSON(context: context, unitsSystem: unitsSystem)
        }
        var exportMetricsPDF: (ModelContext, String, Date?) async -> SettingsExporter.ExportOutput = { context, unitsSystem, startDate in
            await SettingsExporter.exportMetricsPDF(context: context, unitsSystem: unitsSystem, startDate: startDate)
        }
        var exportDiagnostics: (ModelContext, Bool, Double) async -> SettingsExporter.ExportOutput = { context, isSyncEnabled, lastHealthImportTimestamp in
            await SettingsExporter.exportDiagnostics(
                context: context,
                isSyncEnabled: isSyncEnabled,
                lastHealthImportTimestamp: lastHealthImportTimestamp
            )
        }
        var importData: ([URL], SettingsImporter.Strategy, ModelContext) async throws -> String = { urls, strategy, context in
            try await SettingsImporter.importData(urls: urls, strategy: strategy, context: context)
        }
        var hapticSuccess: () -> Void = { Haptics.success() }
        var hapticError: () -> Void = { Haptics.error() }
    }

    static var dependencies = Dependencies()

    static func resetDependencies() {
        dependencies = Dependencies()
    }

    static func exportData(
        format: SettingsExporter.ExportFormat,
        context: ModelContext,
        unitsSystem: String,
        setExportMessage: (String) -> Void,
        setIsExporting: @escaping (Bool) -> Void,
        setShareItems: @escaping ([Any]) -> Void,
        setShareSubject: @escaping (String?) -> Void,
        setIsPresentingShareSheet: @escaping (Bool) -> Void,
        pdfStartDate: Date? = nil
    ) {
        switch format {
        case .csv:
            setExportMessage(AppLocalization.string("Preparing data export..."))
        case .json:
            setExportMessage(AppLocalization.string("Preparing JSON export..."))
        case .pdf:
            setExportMessage(AppLocalization.string("Generating PDF report..."))
        }

        setIsExporting(true)
        Task {
            let output: SettingsExporter.ExportOutput
            switch format {
            case .csv:
                output = await dependencies.exportMetrics(context, unitsSystem)
            case .json:
                output = await dependencies.exportMetricsJSON(context, unitsSystem)
            case .pdf:
                output = await dependencies.exportMetricsPDF(context, unitsSystem, pdfStartDate)
            }

            setShareItems(output.items)
            setShareSubject(output.subject)
            setIsExporting(false)
            setIsPresentingShareSheet(!output.items.isEmpty)
        }
    }

    static func exportDiagnostics(
        context: ModelContext,
        isSyncEnabled: Bool,
        lastHealthImportTimestamp: Double,
        setExportMessage: (String) -> Void,
        setIsExporting: @escaping (Bool) -> Void,
        setShareItems: @escaping ([Any]) -> Void,
        setShareSubject: @escaping (String?) -> Void,
        setIsPresentingShareSheet: @escaping (Bool) -> Void
    ) {
        setExportMessage(AppLocalization.string("Generating diagnostics..."))
        setIsExporting(true)
        Task {
            let output = await dependencies.exportDiagnostics(context, isSyncEnabled, lastHealthImportTimestamp)
            setShareItems(output.items)
            setShareSubject(output.subject)
            setIsExporting(false)
            setIsPresentingShareSheet(!output.items.isEmpty)
        }
    }

    static func shareApp(
        setShareItems: ([Any]) -> Void,
        setShareSubject: (String?) -> Void,
        setIsPresentingShareSheet: (Bool) -> Void
    ) {
        let appName = "MeasureMe – Body Tracker"
        let shareText = AppLocalization.string(
            "share.app.message",
            appName,
            LegalLinks.appStore.absoluteString
        )
        setShareItems([shareText, LegalLinks.appStore])
        setShareSubject(appName)
        setIsPresentingShareSheet(true)
    }

    static func performImport(
        urls: [URL],
        strategy: SettingsImporter.Strategy,
        context: ModelContext,
        setIsImporting: @escaping (Bool) -> Void,
        clearPendingImportURLs: @escaping () -> Void,
        setActiveAlert: @escaping (SettingsAlert) -> Void
    ) {
        guard !urls.isEmpty else { return }
        setIsImporting(true)
        Task {
            let message: String
            do {
                message = try await dependencies.importData(urls, strategy, context)
                dependencies.hapticSuccess()
            } catch {
                message = error.localizedDescription
                dependencies.hapticError()
            }

            setIsImporting(false)
            clearPendingImportURLs()
            setActiveAlert(.importResult(message))
        }
    }
}
