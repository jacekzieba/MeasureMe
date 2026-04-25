import SwiftData
import XCTest
@testable import MeasureMe

@MainActor
final class SettingsTransferCoordinatorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([MetricSample.self, MetricGoal.self, PhotoEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        SettingsTransferCoordinator.resetDependencies()
    }

    override func tearDownWithError() throws {
        SettingsTransferCoordinator.resetDependencies()
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    func testExportDataSetsStateAndPresentsShareSheetForNonEmptyOutput() async {
        let cases: [(SettingsExporter.ExportFormat, String, String, String)] = [
            (.csv, "Preparing data export...", "csv-item", "CSV Subject"),
            (.json, "Preparing JSON export...", "json-item", "JSON Subject"),
            (.pdf, "Generating PDF report...", "pdf-item", "PDF Subject")
        ]

        for (format, expectedMessage, item, subject) in cases {
            var exportMessage: String?
            var exportingStates: [Bool] = []
            var shareItems: [Any] = []
            var shareSubject: String?
            var isPresentingShareSheet = false
            let presented = expectation(description: "presented \(format.rawValue)")

            var dependencies = SettingsTransferCoordinator.Dependencies()
            let output = SettingsExporter.ExportOutput(items: [item], subject: subject)
            dependencies.exportMetrics = { _, _ in output }
            dependencies.exportMetricsJSON = { _, _ in output }
            dependencies.exportMetricsPDF = { _, _, _ in output }
            SettingsTransferCoordinator.dependencies = dependencies

            SettingsTransferCoordinator.exportData(
                format: format,
                context: context,
                unitsSystem: "metric",
                setExportMessage: { exportMessage = $0 },
                setIsExporting: { exportingStates.append($0) },
                setShareItems: { shareItems = $0 },
                setShareSubject: { shareSubject = $0 },
                setIsPresentingShareSheet: {
                    isPresentingShareSheet = $0
                    presented.fulfill()
                }
            )

            await fulfillment(of: [presented], timeout: 1)
            XCTAssertEqual(exportMessage, expectedMessage)
            XCTAssertEqual(exportingStates, [true, false])
            XCTAssertEqual(shareItems.first as? String, item)
            XCTAssertEqual(shareSubject, subject)
            XCTAssertTrue(isPresentingShareSheet)
        }
    }

    func testExportDataDoesNotPresentShareSheetForEmptyOutput() async {
        var isPresentingShareSheet = true
        let finished = expectation(description: "empty export completed")
        var dependencies = SettingsTransferCoordinator.Dependencies()
        dependencies.exportMetrics = { _, _ in SettingsExporter.ExportOutput(items: [], subject: "") }
        SettingsTransferCoordinator.dependencies = dependencies

        SettingsTransferCoordinator.exportData(
            format: .csv,
            context: context,
            unitsSystem: "metric",
            setExportMessage: { _ in },
            setIsExporting: { _ in },
            setShareItems: { _ in },
            setShareSubject: { _ in },
            setIsPresentingShareSheet: {
                isPresentingShareSheet = $0
                finished.fulfill()
            }
        )

        await fulfillment(of: [finished], timeout: 1)
        XCTAssertFalse(isPresentingShareSheet)
    }

    func testExportDiagnosticsSetsStateAndPresentsShareSheet() async {
        var exportMessage: String?
        var exportingStates: [Bool] = []
        var shareItems: [Any] = []
        var shareSubject: String?
        var isPresentingShareSheet = false
        let presented = expectation(description: "diagnostics presented")
        var dependencies = SettingsTransferCoordinator.Dependencies()
        dependencies.exportDiagnostics = { _, isSyncEnabled, timestamp in
            XCTAssertTrue(isSyncEnabled)
            XCTAssertEqual(timestamp, 123.0)
            return SettingsExporter.ExportOutput(items: ["diagnostics"], subject: "Diagnostics")
        }
        SettingsTransferCoordinator.dependencies = dependencies

        SettingsTransferCoordinator.exportDiagnostics(
            context: context,
            isSyncEnabled: true,
            lastHealthImportTimestamp: 123.0,
            setExportMessage: { exportMessage = $0 },
            setIsExporting: { exportingStates.append($0) },
            setShareItems: { shareItems = $0 },
            setShareSubject: { shareSubject = $0 },
            setIsPresentingShareSheet: {
                isPresentingShareSheet = $0
                presented.fulfill()
            }
        )

        await fulfillment(of: [presented], timeout: 1)
        XCTAssertEqual(exportMessage, "Generating diagnostics...")
        XCTAssertEqual(exportingStates, [true, false])
        XCTAssertEqual(shareItems.first as? String, "diagnostics")
        XCTAssertEqual(shareSubject, "Diagnostics")
        XCTAssertTrue(isPresentingShareSheet)
    }

    func testShareAppUsesMessageURLSubjectAndPresentsSheet() {
        var shareItems: [Any] = []
        var shareSubject: String?
        var isPresentingShareSheet = false

        SettingsTransferCoordinator.shareApp(
            setShareItems: { shareItems = $0 },
            setShareSubject: { shareSubject = $0 },
            setIsPresentingShareSheet: { isPresentingShareSheet = $0 }
        )

        XCTAssertEqual(shareItems.count, 2)
        XCTAssertTrue((shareItems.first as? String)?.contains(LegalLinks.appStore.absoluteString) == true)
        XCTAssertEqual(shareItems.last as? URL, LegalLinks.appStore)
        XCTAssertEqual(shareSubject, "MeasureMe – Body Tracker")
        XCTAssertTrue(isPresentingShareSheet)
    }

    func testPerformImportWithEmptyURLsIsNoOp() {
        var importingStates: [Bool] = []
        var clearedPendingURLs = false
        var activeAlert: SettingsAlert?
        var importWasCalled = false
        var dependencies = SettingsTransferCoordinator.Dependencies()
        dependencies.importData = { _, _, _ in
            importWasCalled = true
            return "Unexpected"
        }
        SettingsTransferCoordinator.dependencies = dependencies

        SettingsTransferCoordinator.performImport(
            urls: [],
            strategy: .merge,
            context: context,
            setIsImporting: { importingStates.append($0) },
            clearPendingImportURLs: { clearedPendingURLs = true },
            setActiveAlert: { activeAlert = $0 }
        )

        XCTAssertFalse(importWasCalled)
        XCTAssertTrue(importingStates.isEmpty)
        XCTAssertFalse(clearedPendingURLs)
        XCTAssertNil(activeAlert)
    }

    func testPerformImportSuccessClearsPendingURLsAndShowsResult() async {
        var importingStates: [Bool] = []
        var clearedPendingURLCount = 0
        var activeAlert: SettingsAlert?
        var successHaptics = 0
        let finished = expectation(description: "import success")
        var dependencies = SettingsTransferCoordinator.Dependencies()
        dependencies.importData = { urls, strategy, _ in
            XCTAssertEqual(urls, [URL(fileURLWithPath: "/tmp/measureme.csv")])
            switch strategy {
            case .merge:
                break
            case .replace:
                XCTFail("Expected merge import")
            }
            return "Imported 1 row"
        }
        dependencies.hapticSuccess = { successHaptics += 1 }
        dependencies.hapticError = { XCTFail("Did not expect error haptic") }
        SettingsTransferCoordinator.dependencies = dependencies

        SettingsTransferCoordinator.performImport(
            urls: [URL(fileURLWithPath: "/tmp/measureme.csv")],
            strategy: .merge,
            context: context,
            setIsImporting: { importingStates.append($0) },
            clearPendingImportURLs: { clearedPendingURLCount += 1 },
            setActiveAlert: {
                activeAlert = $0
                finished.fulfill()
            }
        )

        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(importingStates, [true, false])
        XCTAssertEqual(clearedPendingURLCount, 1)
        XCTAssertEqual(successHaptics, 1)
        assertImportResult(activeAlert, message: "Imported 1 row")
    }

    func testPerformImportFailureShowsErrorAndResetsState() async {
        var importingStates: [Bool] = []
        var clearedPendingURLCount = 0
        var activeAlert: SettingsAlert?
        var errorHaptics = 0
        let finished = expectation(description: "import failure")
        var dependencies = SettingsTransferCoordinator.Dependencies()
        dependencies.importData = { _, _, _ in
            throw NSError(domain: "SettingsTransferCoordinatorTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Bad import"
            ])
        }
        dependencies.hapticSuccess = { XCTFail("Did not expect success haptic") }
        dependencies.hapticError = { errorHaptics += 1 }
        SettingsTransferCoordinator.dependencies = dependencies

        SettingsTransferCoordinator.performImport(
            urls: [URL(fileURLWithPath: "/tmp/bad.csv")],
            strategy: .replace,
            context: context,
            setIsImporting: { importingStates.append($0) },
            clearPendingImportURLs: { clearedPendingURLCount += 1 },
            setActiveAlert: {
                activeAlert = $0
                finished.fulfill()
            }
        )

        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(importingStates, [true, false])
        XCTAssertEqual(clearedPendingURLCount, 1)
        XCTAssertEqual(errorHaptics, 1)
        assertImportResult(activeAlert, message: "Bad import")
    }

    private func assertImportResult(_ alert: SettingsAlert?, message: String, file: StaticString = #filePath, line: UInt = #line) {
        guard case let .importResult(actualMessage) = alert else {
            return XCTFail("Expected import result alert", file: file, line: line)
        }
        XCTAssertEqual(actualMessage, message, file: file, line: line)
    }
}
