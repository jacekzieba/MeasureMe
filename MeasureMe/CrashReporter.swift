import Foundation
import UIKit

/// Zbiera logi aplikacji i raporty crash/error, umożliwiając wysyłkę mailem.
///
/// **Funkcje:**
/// - Circular buffer ostatnich 200 wpisów logów
/// - Przechwytywanie NSException via NSSetUncaughtExceptionHandler
/// - Signal handlers: SIGABRT, SIGSEGV, SIGBUS, SIGFPE
/// - Zapis raportów do pliku .crash w Application Support/CrashReports/
/// - Sprawdzanie niezgłoszonych raportów przy starcie app
final class CrashReporter {
    static let shared = CrashReporter()

    // MARK: - Configuration

    private let maxLogEntries = 200
    private let reportsDirectoryName = "CrashReports"
    private let latestLogFileName = "latest_log.txt"
    private let unreportedKey = "crashreporter_has_unreported"

    // MARK: - State

    private var logBuffer: [(timestamp: Date, message: String)] = []
    private let lock = NSLock()
    private var currentScreen: String = "Unknown"
    private var isInstalled = false

    private init() {}

    // MARK: - Setup

    /// Zainstaluj handlery crash i signal. Wywołaj raz przy starcie app.
    func install() {
        guard !isInstalled else { return }
        isInstalled = true

        // NSException handler
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.shared.handleException(exception)
        }

        // Signal handlers
        signal(SIGABRT) { signal in CrashReporter.shared.handleSignal(signal) }
        signal(SIGSEGV) { signal in CrashReporter.shared.handleSignal(signal) }
        signal(SIGBUS) { signal in CrashReporter.shared.handleSignal(signal) }
        signal(SIGFPE) { signal in CrashReporter.shared.handleSignal(signal) }
    }

    // MARK: - Logging

    /// Dodaj wpis do circular buffer. Wywoływane z AppLog.
    func appendLog(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        logBuffer.append((timestamp: Date(), message: message))
        if logBuffer.count > maxLogEntries {
            logBuffer.removeFirst(logBuffer.count - maxLogEntries)
        }
    }

    /// Ustaw aktualny ekran (do kontekstu w raporcie)
    func setCurrentScreen(_ screen: String) {
        lock.lock()
        defer { lock.unlock() }
        currentScreen = screen
    }

    /// Zrzuć bufor logów do pliku (np. przy przejściu do background)
    func persistLogBuffer() {
        lock.lock()
        let snapshot = logBuffer
        lock.unlock()

        let text = formatLogEntries(snapshot)
        guard let data = text.data(using: .utf8) else { return }

        do {
            let dir = try reportsDirectory()
            let url = dir.appendingPathComponent(latestLogFileName)
            try data.write(to: url, options: .atomic)
        } catch {
            // Silent — nie chcemy rekursji logowania
        }
    }

    // MARK: - Crash Handling

    private func handleException(_ exception: NSException) {
        let info = """
        Type: NSException
        Name: \(exception.name.rawValue)
        Reason: \(exception.reason ?? "Unknown")
        Stack: \(exception.callStackSymbols.joined(separator: "\n"))
        """
        writeCrashReport(crashInfo: info)
    }

    private func handleSignal(_ sig: Int32) {
        let signalName: String
        switch sig {
        case SIGABRT: signalName = "SIGABRT"
        case SIGSEGV: signalName = "SIGSEGV"
        case SIGBUS: signalName = "SIGBUS"
        case SIGFPE: signalName = "SIGFPE"
        default: signalName = "SIGNAL(\(sig))"
        }

        let info = """
        Type: Signal
        Signal: \(signalName) (\(sig))
        Stack: \(Thread.callStackSymbols.joined(separator: "\n"))
        """
        writeCrashReport(crashInfo: info)

        // Przywróć domyślny handler i re-raise signal
        signal(sig, SIG_DFL)
        raise(sig)
    }

    private func writeCrashReport(crashInfo: String) {
        lock.lock()
        let logSnapshot = logBuffer
        let screen = currentScreen
        lock.unlock()

        let report = buildReport(crashInfo: crashInfo, logs: logSnapshot, screen: screen)
        guard let data = report.data(using: .utf8) else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "crash_\(formatter.string(from: Date())).crash"

        do {
            let dir = try reportsDirectory()
            let url = dir.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            UserDefaults.standard.set(true, forKey: unreportedKey)
        } catch {
            // Nie możemy logować — app crashuje
        }
    }

    // MARK: - Report Building

    private func buildReport(crashInfo: String, logs: [(timestamp: Date, message: String)], screen: String) -> String {
        let device = UIDevice.current
        let bundle = Bundle.main
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"

        let memoryInfo = ProcessInfo.processInfo.physicalMemory
        let memoryGB = String(format: "%.1f", Double(memoryInfo) / 1_073_741_824)

        let unitsSystem = UserDefaults.standard.string(forKey: "unitsSystem") ?? "metric"
        let language = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"

        return """
        ============================
        MeasureMe Crash Report
        ============================

        [App Info]
        Version: \(appVersion) (\(buildNumber))
        Date: \(Date().formatted(.iso8601))

        [Device Info]
        Model: \(device.model)
        System: \(device.systemName) \(device.systemVersion)
        Locale: \(Locale.current.identifier)
        RAM: \(memoryGB) GB

        [User Context]
        Current Screen: \(screen)
        Units: \(unitsSystem)
        Language: \(language)

        [Crash Info]
        \(crashInfo)

        [Recent Logs (last \(logs.count) entries)]
        \(formatLogEntries(logs))

        ============================
        End of Report
        ============================
        """
    }

    private func formatLogEntries(_ entries: [(timestamp: Date, message: String)]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return entries.map { "[\(formatter.string(from: $0.timestamp))] \($0.message)" }.joined(separator: "\n")
    }

    // MARK: - Report Access

    /// Czy jest niezgłoszony crash report?
    var hasUnreportedCrash: Bool {
        UserDefaults.standard.bool(forKey: unreportedKey)
    }

    /// Oznacz crash jako zgłoszony
    func markCrashReported() {
        UserDefaults.standard.set(false, forKey: unreportedKey)
    }

    /// Zwróć listę wszystkich raportów (najnowsze pierwsze)
    func listReports() -> [CrashReport] {
        guard let dir = try? reportsDirectory() else { return [] }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "crash" }
            .compactMap { url -> CrashReport? in
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return CrashReport(url: url, filename: url.lastPathComponent, date: created, content: content)
            }
            .sorted { $0.date > $1.date }
    }

    /// Usuń raport
    func deleteReport(_ report: CrashReport) {
        try? FileManager.default.removeItem(at: report.url)
    }

    /// Wygeneruj raport diagnostyczny (bez crash — do manualnego wysłania)
    func generateDiagnosticReport() -> String {
        lock.lock()
        let logSnapshot = logBuffer
        let screen = currentScreen
        lock.unlock()

        let diagnosticInfo = """
        Type: Diagnostic (user-initiated)
        Note: No crash detected. This report contains recent logs for debugging.
        """
        return buildReport(crashInfo: diagnosticInfo, logs: logSnapshot, screen: screen)
    }

    // MARK: - File System

    private func reportsDirectory() throws -> URL {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "CrashReporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Application Support unavailable"])
        }
        let dir = appSupport.appendingPathComponent(reportsDirectoryName)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}

// MARK: - Crash Report Model

struct CrashReport: Identifiable {
    let url: URL
    let filename: String
    let date: Date
    let content: String

    var id: String { filename }
}
