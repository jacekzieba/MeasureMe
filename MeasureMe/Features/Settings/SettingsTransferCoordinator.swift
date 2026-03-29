import Foundation
import SwiftData

@MainActor
enum SettingsTransferCoordinator {
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
                output = await SettingsExporter.exportMetrics(context: context, unitsSystem: unitsSystem)
            case .json:
                output = await SettingsExporter.exportMetricsJSON(context: context, unitsSystem: unitsSystem)
            case .pdf:
                output = await SettingsExporter.exportMetricsPDF(
                    context: context,
                    unitsSystem: unitsSystem,
                    startDate: pdfStartDate
                )
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
            let output = await SettingsExporter.exportDiagnostics(
                context: context,
                isSyncEnabled: isSyncEnabled,
                lastHealthImportTimestamp: lastHealthImportTimestamp
            )
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
                message = try await SettingsImporter.importData(
                    urls: urls,
                    strategy: strategy,
                    context: context
                )
                Haptics.success()
            } catch {
                message = error.localizedDescription
                Haptics.error()
            }

            setIsImporting(false)
            clearPendingImportURLs()
            setActiveAlert(.importResult(message))
        }
    }
}
