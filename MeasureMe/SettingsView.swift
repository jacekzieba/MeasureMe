import SwiftUI
import SwiftData
import HealthKit
import UIKit

/// **SettingsView**
/// Widok ustawień aplikacji. Odpowiada za:
/// - Włączanie/wyłączanie synchronizacji z HealthKit
/// - Wybór systemu jednostek (metryczny/imperialny)
/// - Nawigację do zarządzania śledzonymi metrykami
/// - Sekcję informacyjną "About"
///
/// **Optymalizacje wydajności:**
/// - Autoryzacja HealthKit uruchamiana asynchronicznie z opóźnieniem
/// - Task anulowany przy znikaniu widoku, aby uniknąć memory leaks
/// - Brak blokowania głównego wątku podczas żądania uprawnień
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var premiumStore: PremiumStore
    @AppStorage("isSyncEnabled") private var isSyncEnabled: Bool = false
    @AppStorage("unitsSystem") private var unitsSystem: String = "metric"
    @AppStorage("showLastPhotosOnHome") private var showLastPhotosOnHome: Bool = true
    @AppStorage("showMeasurementsOnHome") private var showMeasurementsOnHome: Bool = true
    @AppStorage("showHealthMetricsOnHome") private var showHealthMetricsOnHome: Bool = true
    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("appLanguage") private var appLanguage: String = "system"
    
    // Core Metrics visibility
    @AppStorage("showWHtROnHome") private var showWHtROnHome: Bool = true
    @AppStorage("showRFMOnHome") private var showRFMOnHome: Bool = true
    @AppStorage("showBMIOnHome") private var showBMIOnHome: Bool = true
    
    // Body Composition visibility
    @AppStorage("showBodyFatOnHome") private var showBodyFatOnHome: Bool = true
    @AppStorage("showLeanMassOnHome") private var showLeanMassOnHome: Bool = true
    
    // Risk Indicators visibility
    @AppStorage("showABSIOnHome") private var showABSIOnHome: Bool = true
    @AppStorage("showConicityOnHome") private var showConicityOnHome: Bool = true
    
    @AppStorage("userGender") private var userGender: String = "notSpecified"
    @AppStorage("manualHeight") private var manualHeight: Double = 0.0
    @AppStorage("userAge") private var userAge: Int = 0
    @AppStorage("healthkit_last_import") private var lastHealthImportTimestamp: Double = 0.0
    @AppStorage("apple_intelligence_enabled") private var appleIntelligenceEnabled: Bool = true
    
    @AppStorage("healthkit_sync_weight") private var hkWeight: Bool = true
    @AppStorage("healthkit_sync_bodyFat") private var hkBodyFat: Bool = true
    @AppStorage("healthkit_sync_height") private var hkHeight: Bool = true
    @AppStorage("healthkit_sync_leanBodyMass") private var hkLeanMass: Bool = true
    @AppStorage("healthkit_sync_waist") private var hkWaist: Bool = true

    @Query(
        filter: #Predicate<MetricSample> { sample in
            sample.kindRaw == "height"
        },
        sort: [SortDescriptor(\MetricSample.date, order: .reverse)]
    )
    private var heightSamples: [MetricSample]
    @State private var scrollOffset: CGFloat = 0
    @State private var shareItems: [Any] = []
    @State private var shareSubject: String? = nil
    @State private var isPresentingShareSheet = false
    @State private var isExporting = false
    @State private var exportMessage: String = ""
    
    // MARK: - Helpers for Height
    
    /// Pobiera najnowszy wzrost ze śledzonych metryk
    private var latestTrackedHeight: MetricSample? {
        heightSamples.first
    }
    
    /// Zwraca skuteczny wzrost (tracked lub manual)
    private var effectiveHeight: Double? {
        if manualHeight > 0 {
            return manualHeight
        }
        return latestTrackedHeight?.value
    }
    
    /// Formatuje wzrost do wyświetlenia
    private var currentHeightText: String? {
        guard let height = effectiveHeight else { return nil }
        
        let display = MetricKind.height.valueForDisplay(fromMetric: height, unitsSystem: unitsSystem)
        
        if unitsSystem == "imperial" {
            let totalInches = Int(display.rounded())
            let feet = totalInches / 12
            let inches = totalInches % 12
            return "\(feet)'\(inches)\""
        } else {
            return String(format: "%.0f cm", display)
        }
    }
    
    // MARK: - Helpers for Age
    
    /// Formatuje wiek do wyświetlenia
    private var currentAgeText: String? {
        guard userAge > 0 else { return nil }
        return AppLocalization.plural("age.years.old", userAge)
    }
    
    private var lastImportText: String? {
        guard lastHealthImportTimestamp > 0 else { return nil }
        let date = Date(timeIntervalSince1970: lastHealthImportTimestamp)
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AppScreenBackground(
                    topHeight: 380,
                    scrollOffset: scrollOffset,
                    tint: Color.cyan.opacity(0.22)
                )
                
                // Zawartość
                List {
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: SettingsScrollOffsetKey.self,
                            value: proxy.frame(in: .named("settingsScroll")).minY
                        )
                }
                .frame(height: 0)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                ScreenTitleHeader(title: AppLocalization.string("Settings"), topPadding: 6, bottomPadding: 4)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                Section {
                    SettingsCard(tint: Color.appAccent.opacity(0.12)) {
                        SettingsCardHeader(title: AppLocalization.string("Premium Edition"), systemImage: "star.fill")
                        HStack {
                            Text(premiumStore.isPremium ? AppLocalization.string("Active") : AppLocalization.string("Not active"))
                                .font(AppTypography.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(premiumStore.isPremium ? AppLocalization.string("Manage") : AppLocalization.string("Upgrade")) {
                                if premiumStore.isPremium {
                                    premiumStore.openManageSubscriptions()
                                } else {
                                    premiumStore.presentPaywall(reason: .settings)
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.appAccent)
                        }
                        Button(AppLocalization.string("Restore purchases")) {
                            Task { await premiumStore.restorePurchases() }
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(settingsRowInsets)

                ProfileSettingsSection(
                    userName: $userName,
                    userGender: $userGender,
                    currentAgeText: currentAgeText,
                    currentHeightText: currentHeightText
                )
                .listRowBackground(Color.clear)
                .listRowInsets(settingsRowInsets)

                Section {
                    SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                        SettingsCardHeader(title: AppLocalization.string("Tracked"), systemImage: "list.bullet.clipboard")
                        NavigationLink {
                            TrackedMeasurementsView()
                        } label: {
                            Text(AppLocalization.string("Tracked measurements"))
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(settingsRowInsets)

                HealthSettingsSection(
                    isSyncEnabled: $isSyncEnabled,
                    lastImportText: lastImportText,
                    hkWeight: $hkWeight,
                    hkBodyFat: $hkBodyFat,
                    hkHeight: $hkHeight,
                    hkLeanMass: $hkLeanMass,
                    hkWaist: $hkWaist
                )
                .listRowBackground(Color.clear)
                .listRowInsets(settingsRowInsets)

                HealthIndicatorsSettingsSection(
                    showWHtROnHome: $showWHtROnHome,
                    showRFMOnHome: $showRFMOnHome,
                    showBMIOnHome: $showBMIOnHome,
                    showBodyFatOnHome: $showBodyFatOnHome,
                    showLeanMassOnHome: $showLeanMassOnHome,
                    showABSIOnHome: $showABSIOnHome,
                    showConicityOnHome: $showConicityOnHome
                )
                .listRowBackground(Color.clear)
                .listRowInsets(settingsRowInsets)

                Section {
                    SettingsCard(tint: Color.white.opacity(0.07)) {
                        SettingsCardHeader(title: AppLocalization.string("Notifications"), systemImage: "bell.badge")
                        NavigationLink {
                            NotificationSettingsView()
                        } label: {
                            Text(AppLocalization.string("Manage reminders"))
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(settingsRowInsets)

                HomeSettingsSection(
                    showMeasurementsOnHome: $showMeasurementsOnHome,
                    showLastPhotosOnHome: $showLastPhotosOnHome,
                    showHealthMetricsOnHome: $showHealthMetricsOnHome
                )
                .listRowBackground(Color.clear)
                .listRowInsets(settingsRowInsets)

                Section {
                    SettingsCard(tint: Color.cyan.opacity(0.12)) {
                        SettingsCardHeader(title: AppLocalization.string("Apple Intelligence"), systemImage: "sparkles")
                        if premiumStore.isPremium {
                            if AppleIntelligenceSupport.isAvailable() {
                                Toggle(isOn: $appleIntelligenceEnabled) {
                                    Text(AppLocalization.string("Enable Apple Intelligence"))
                                }
                                .tint(Color.appAccent)
                                .onChange(of: appleIntelligenceEnabled) { _, _ in Haptics.selection() }
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(AppLocalization.string("Apple Intelligence isn’t available right now."))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(.secondary)
                                    NavigationLink {
                                        FAQView()
                                    } label: {
                                        Text(AppLocalization.string("Learn more in FAQ"))
                                            .font(AppTypography.captionEmphasis)
                                            .foregroundStyle(Color.appAccent)
                                    }
                                }
                            }
                        } else {
                            HStack {
                                Text(AppLocalization.string("Premium Edition required"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(AppLocalization.string("Unlock")) {
                                    premiumStore.presentPaywall(reason: .feature("Apple Intelligence"))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.appAccent)
                            }
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(settingsRowInsets)

                UnitsSettingsSection(unitsSystem: $unitsSystem)
                    .listRowBackground(Color.clear)
                    .listRowInsets(settingsRowInsets)

                Section {
                    SettingsCard(tint: Color.white.opacity(0.08)) {
                        SettingsCardHeader(title: AppLocalization.string("Experience"), systemImage: "sparkles")
                        Toggle(isOn: $animationsEnabled) {
                            Text(AppLocalization.string("Animations"))
                        }
                        .tint(Color.appAccent)
                        .onChange(of: animationsEnabled) { _, _ in Haptics.selection() }
                        SettingsRowDivider()
                        Toggle(isOn: $hapticsEnabled) {
                            Text(AppLocalization.string("Haptics"))
                        }
                        .tint(Color.appAccent)
                        .onChange(of: hapticsEnabled) { _, _ in Haptics.selection() }
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(settingsRowInsets)

                Section {
                    SettingsCard(tint: Color.white.opacity(0.07)) {
                        SettingsCardHeader(title: AppLocalization.string("Language"), systemImage: "globe")
                        Picker(AppLocalization.string("App language"), selection: $appLanguage) {
                            Text(AppLocalization.string("System")).tag("system")
                            Text(AppLocalization.string("English")).tag("en")
                            Text(AppLocalization.string("Polish")).tag("pl")
                        }
                        .pickerStyle(.menu)
                        Text(AppLocalization.string("Restart required after changing language."))
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(settingsRowInsets)

                Section {
                    SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                        SettingsCardHeader(title: AppLocalization.string("Data"), systemImage: "square.and.arrow.up")
                        Button {
                            Haptics.light()
                            if premiumStore.isPremium {
                                exportMetricsCSV()
                            } else {
                                premiumStore.presentPaywall(reason: .feature("Data export"))
                            }
                        } label: {
                            Text(AppLocalization.string("Export data"))
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(settingsRowInsets)

                Section {
                    SettingsCard(tint: Color.white.opacity(0.07)) {
                        SettingsCardHeader(title: AppLocalization.string("FAQ"), systemImage: "questionmark.circle")
                        NavigationLink {
                            FAQView()
                        } label: {
                            Text(AppLocalization.string("Read frequently asked questions"))
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(settingsRowInsets)

                Section {
                    SettingsCard(tint: Color.cyan.opacity(0.12)) {
                        SettingsCardHeader(title: AppLocalization.string("Diagnostics"), systemImage: "stethoscope")
                        Button {
                            Haptics.light()
                            exportDiagnosticsJSON()
                        } label: {
                            Text(AppLocalization.string("Generate diagnostics"))
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(settingsRowInsets)

                Section {
                    SettingsCard(tint: Color.white.opacity(0.07)) {
                        SettingsCardHeader(title: AppLocalization.string("App"), systemImage: "info.circle")
                        Button {
                            if let url = URL(string: "https://jacekzieba.pl/measureme") {
                                openURL(url)
                            }
                        } label: {
                            HStack {
                                Text(AppLocalization.string("About"))
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        SettingsRowDivider()
                        Button {
                            if let url = URL(string: "https://measureme.userjot.com/") {
                                openURL(url)
                            }
                        } label: {
                            HStack {
                                Text(AppLocalization.string("Feature request"))
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(settingsRowInsets)
            }
            .tint(Color.appAccent)
            .coordinateSpace(name: "settingsScroll")
            .onPreferenceChange(SettingsScrollOffsetKey.self) { value in
                scrollOffset = value
            }
            .scrollContentBackground(.hidden) // Ukryj domyślne tło List
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowSeparatorTint(.clear)
            .listSectionSeparatorTint(.clear)
            .listStyle(.plain)
            .padding(.top, -12)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(scrollOffset < -18 ? .visible : .hidden, for: .navigationBar)
            .sheet(isPresented: $isPresentingShareSheet) {
                ShareSheet(items: shareItems, subject: shareSubject)
            }
            if isExporting {
                exportOverlay
            }
            }
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .age:
                    AgeSettingsView()
                case .height:
                    HeightSettingsView()
                }
            }
        }
    }

    // MARK: - Exports

    private struct MetricSampleSnapshot: Sendable {
        let kindRaw: String
        let value: Double
        let date: Date
    }

    private func exportMetricsCSV() {
        let snapshot = fetchAllMetricSamplesSorted()
        let currentUnitsSystem = unitsSystem
        exportMessage = AppLocalization.string("Preparing data export...")
        isExporting = true
        Task {
            let csv = await Task.detached(priority: .userInitiated) {
                SettingsView.buildMetricsCSV(from: snapshot, unitsSystem: currentUnitsSystem)
            }.value
            let fileName = "measureme-metrics-\(timestampString()).csv"
            let url = writeTempFile(named: fileName, contents: csv)
            await MainActor.run {
                isExporting = false
                guard let url else { return }
                shareItems = [url]
                shareSubject = AppLocalization.string("MeasureMe data export")
                isPresentingShareSheet = true
            }
        }
    }

    private func exportDiagnosticsJSON() {
        let sampleSnapshot = fetchAllMetricSamplesSorted()
        let photoCount = fetchPhotosCount()
        let syncEnabled = isSyncEnabled
        let lastImport = lastHealthImportTimestamp
        exportMessage = AppLocalization.string("Generating diagnostics...")
        isExporting = true
        Task {
            let data = await Task.detached(priority: .userInitiated) {
                SettingsView.buildDiagnosticsJSON(
                    samples: sampleSnapshot,
                    photosCount: photoCount,
                    isSyncEnabled: syncEnabled,
                    lastHealthImportTimestamp: lastImport
                )
            }.value
            let fileName = "measureme-diagnostics-\(timestampString()).json"
            let url = data.flatMap { writeTempFile(named: fileName, data: $0) }
            await MainActor.run {
                isExporting = false
                guard let url else { return }
                shareItems = [
                    url,
                    AppLocalization.string("Send diagnostics to ziebajacek@pm.me")
                ]
                shareSubject = AppLocalization.string("MeasureMe diagnostics")
                isPresentingShareSheet = true
            }
        }
    }

    private func fetchAllMetricSamplesSorted() -> [MetricSampleSnapshot] {
        let descriptor = FetchDescriptor<MetricSample>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let samples = (try? modelContext.fetch(descriptor)) ?? []
        return samples.map {
            MetricSampleSnapshot(kindRaw: $0.kindRaw, value: $0.value, date: $0.date)
        }
    }

    private func fetchPhotosCount() -> Int {
        let descriptor = FetchDescriptor<PhotoEntry>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private static func buildMetricsCSV(from samples: [MetricSampleSnapshot], unitsSystem: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lines: [String] = ["metric,value,unit,timestamp"]
        for sample in samples {
            guard let kind = MetricKind(rawValue: sample.kindRaw) else { continue }
            let displayValue = kind.valueForDisplay(fromMetric: sample.value, unitsSystem: unitsSystem)
            let unit = kind.unitSymbol(unitsSystem: unitsSystem)
            let valueString = String(format: "%.2f", displayValue)
            let dateString = formatter.string(from: sample.date)
            lines.append("\(kind.title),\(valueString),\(unit),\(dateString)")
        }
        return lines.joined(separator: "\n")
    }

    private static func buildDiagnosticsJSON(
        samples: [MetricSampleSnapshot],
        photosCount: Int,
        isSyncEnabled: Bool,
        lastHealthImportTimestamp: Double
    ) -> Data? {
        let bundle = Bundle.main
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let device = UIDevice.current
        let now = Date()
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

    private static func healthKitStatusText() -> String {
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

    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func writeTempFile(named name: String, contents: String) -> URL? {
        guard let data = contents.data(using: .utf8) else { return nil }
        return writeTempFile(named: name, data: data)
    }

    private func writeTempFile(named name: String, data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            AppLog.debug("⚠️ Failed to write export file: \(error.localizedDescription)")
            return nil
        }
    }

    private var exportOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(Color.appAccent)
                Text(exportMessage)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.white)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
    }
}

// MARK: - Sections
