import SwiftUI

// MARK: - Settings Constants

fileprivate let settingsComponentsCardCornerRadius: CGFloat = 16
fileprivate let settingsComponentsRowInsets = EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

struct HealthSettingsSection: View {
    @Binding var isSyncEnabled: Bool
    let lastImportText: String?
    @Binding var hkWeight: Bool
    @Binding var hkBodyFat: Bool
    @Binding var hkHeight: Bool
    @Binding var hkLeanMass: Bool
    @Binding var hkWaist: Bool
    
    @State private var authorizationTask: Task<Void, Never>?
    @State private var isMetricsExpanded: Bool = false
    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        Section {
            SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                SettingsCardHeader(title: AppLocalization.string("Health"), systemImage: "heart.fill")
                syncRow
                SettingsRowDivider()
                metricsRow
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
        .onDisappear {
            // Anuluj task przy znikaniu widoku, aby uniknąć wycieku pamięci
            authorizationTask?.cancel()
        }
    }

    private var shouldAnimate: Bool {
        animationsEnabled && !reduceMotion
    }
    
    private var syncRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                GlassPillIcon(systemName: "heart.fill")
                Text(AppLocalization.string("Sync with Health"))
                Spacer()
                Toggle("", isOn: $isSyncEnabled)
                    .labelsHidden()
                    .tint(Color.appAccent)
                    .frame(width: 52, alignment: .trailing)
            }
            .frame(minHeight: 44)
            
            Text(AppLocalization.string("health.last.import", lastImportText ?? "—"))
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 44)
        }
        .onChange(of: isSyncEnabled) { oldValue, newValue in
            Haptics.selection()
            // Anuluj poprzedni task autoryzacji jeśli istnieje
            authorizationTask?.cancel()
            
            // Tylko gdy użytkownik włącza synchronizację
            if newValue {
                // Uruchom autoryzację z małym opóźnieniem, aby UI był responsywny
                authorizationTask = Task { @MainActor in
                    // Opóźnienie 100ms zapewnia płynne przełączenie toggle
                    try? await Task.sleep(for: .milliseconds(100))
                    
                    // Sprawdź czy task nie został anulowany
                    guard !Task.isCancelled else { return }
                    
                    do {
                        try await HealthKitManager.shared.requestAuthorization()
                    } catch {
                        AppLog.debug("⚠️ HealthKit authorization failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private var metricsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
                Button {
                    isMetricsExpanded.toggle()
                } label: {
                HStack {
                    Text(AppLocalization.string("Synced data"))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isMetricsExpanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)

                if isMetricsExpanded {
                    VStack(spacing: 0) {
                    healthMetricRow(AppLocalization.string("metric.weight"), isOn: $hkWeight)
                    rowDivider
                    healthMetricRow(AppLocalization.string("metric.bodyfat"), isOn: $hkBodyFat)
                    rowDivider
                    healthMetricRow(AppLocalization.string("metric.height"), isOn: $hkHeight)
                    rowDivider
                    healthMetricRow(AppLocalization.string("metric.leanbodymass"), isOn: $hkLeanMass)
                    rowDivider
                    healthMetricRow(AppLocalization.string("metric.waist"), isOn: $hkWaist)
                }
                .disabled(!isSyncEnabled)
                .onChange(of: hkWeight) { _, _ in HealthKitManager.shared.startObservingHealthKitUpdates() }
                .onChange(of: hkBodyFat) { _, _ in HealthKitManager.shared.startObservingHealthKitUpdates() }
                .onChange(of: hkHeight) { _, _ in HealthKitManager.shared.startObservingHealthKitUpdates() }
                .onChange(of: hkLeanMass) { _, _ in HealthKitManager.shared.startObservingHealthKitUpdates() }
                .onChange(of: hkWaist) { _, _ in HealthKitManager.shared.startObservingHealthKitUpdates() }
                .padding(.top, 6)
                }
            }
        }
    
    private var rowDivider: some View {
        Divider()
            .overlay(Color.white.opacity(0.12))
            .padding(.vertical, 4)
    }
    
    private func healthMetricRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .frame(width: 52, alignment: .trailing)
        }
        .tint(Color.appAccent)
        .onChange(of: isOn.wrappedValue) { _, _ in Haptics.selection() }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }
}

struct UnitsSettingsSection: View {
    @Binding var unitsSystem: String
    
    var body: some View {
        Section {
            SettingsCard(tint: Color.appAccent.opacity(0.12)) {
                SettingsCardHeader(title: AppLocalization.string("Units"), systemImage: "ruler")
                Picker(AppLocalization.string("Units"), selection: $unitsSystem) {
                    Text(AppLocalization.string("Metric")).tag("metric")
                    Text(AppLocalization.string("Imperial")).tag("imperial")
                }
                .pickerStyle(.segmented)
                .glassSegmentedControl(tint: Color.appAccent)
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
    }
}

struct ProfileSettingsDetailView: View {
    @Binding var userName: String
    @Binding var userGender: String
    @Binding var userAge: Int
    @Binding var manualHeight: Double
    @Binding var unitsSystem: String

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                ProfileSettingsSection(
                    userName: $userName,
                    userGender: $userGender,
                    userAge: $userAge,
                    manualHeight: $manualHeight,
                    unitsSystem: $unitsSystem
                )
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct HealthIndicatorsSettingsDetailView: View {
    @Binding var showWHtROnHome: Bool
    @Binding var showRFMOnHome: Bool
    @Binding var showBMIOnHome: Bool
    @Binding var showBodyFatOnHome: Bool
    @Binding var showLeanMassOnHome: Bool
    @Binding var showABSIOnHome: Bool
    @Binding var showConicityOnHome: Bool

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                HealthIndicatorsSettingsSection(
                    showWHtROnHome: $showWHtROnHome,
                    showRFMOnHome: $showRFMOnHome,
                    showBMIOnHome: $showBMIOnHome,
                    showBodyFatOnHome: $showBodyFatOnHome,
                    showLeanMassOnHome: $showLeanMassOnHome,
                    showABSIOnHome: $showABSIOnHome,
                    showConicityOnHome: $showConicityOnHome
                )
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Health indicators"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct HomeSettingsDetailView: View {
    @Binding var showMeasurementsOnHome: Bool
    @Binding var showLastPhotosOnHome: Bool
    @Binding var showHealthMetricsOnHome: Bool
    @Binding var showOnboardingChecklistOnHome: Bool

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                HomeSettingsSection(
                    showMeasurementsOnHome: $showMeasurementsOnHome,
                    showLastPhotosOnHome: $showLastPhotosOnHome,
                    showHealthMetricsOnHome: $showHealthMetricsOnHome,
                    showOnboardingChecklistOnHome: $showOnboardingChecklistOnHome
                )
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Home"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct ExperienceSettingsDetailView: View {
    @Binding var animationsEnabled: Bool
    @Binding var hapticsEnabled: Bool

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                Section {
                    SettingsCard(tint: Color.white.opacity(0.08)) {
                        SettingsCardHeader(title: AppLocalization.string("Animations and haptics"), systemImage: "sparkles")
                        Toggle(isOn: $animationsEnabled) {
                            Text(AppLocalization.string("Animations"))
                        }
                        .tint(Color.appAccent)
                        .onChange(of: animationsEnabled) { _, _ in Haptics.selection() }
                        .frame(minHeight: 44)

                        SettingsRowDivider()

                        Toggle(isOn: $hapticsEnabled) {
                            Text(AppLocalization.string("Haptics"))
                        }
                        .tint(Color.appAccent)
                        .onChange(of: hapticsEnabled) { _, _ in Haptics.selection() }
                        .frame(minHeight: 44)
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowInsets(settingsComponentsRowInsets)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Animations and haptics"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct LanguageSettingsDetailView: View {
    @Binding var appLanguage: String

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                Section {
                    SettingsCard(tint: Color.white.opacity(0.07)) {
                        SettingsCardHeader(title: AppLocalization.string("Language"), systemImage: "globe")
                        languageRow(title: AppLocalization.string("System"), value: "system")
                        SettingsRowDivider()
                        languageRow(title: AppLocalization.string("English"), value: "en")
                        SettingsRowDivider()
                        languageRow(title: AppLocalization.string("Polish"), value: "pl")
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowInsets(settingsComponentsRowInsets)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Language"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func languageRow(title: String, value: String) -> some View {
        Button {
            appLanguage = value
            Haptics.selection()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.white)
                Spacer()
                languageAccessory(for: value)
                    .frame(width: 16, alignment: .trailing)
            }
            .padding(.trailing, 2)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func languageAccessory(for value: String) -> some View {
        if appLanguage == value {
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.appAccent)
        } else {
            Color.clear
        }
    }
}

struct DataSettingsDetailView: View {
    let onExport: () -> Void
    let onDeleteAll: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                Section {
                    SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                        SettingsCardHeader(title: AppLocalization.string("Data"), systemImage: "square.and.arrow.up")
                        Button(action: onExport) {
                            Text(AppLocalization.string("Export data"))
                        }
                        .frame(minHeight: 44, alignment: .leading)

                        SettingsRowDivider()

                        Button(role: .destructive, action: onDeleteAll) {
                            Text(AppLocalization.string("Delete all data"))
                        }
                        .frame(minHeight: 44, alignment: .leading)
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowInsets(settingsComponentsRowInsets)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Data"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct HealthSettingsDetailView: View {
    @Binding var isSyncEnabled: Bool
    let lastImportText: String?
    @Binding var hkWeight: Bool
    @Binding var hkBodyFat: Bool
    @Binding var hkHeight: Bool
    @Binding var hkLeanMass: Bool
    @Binding var hkWaist: Bool

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                HealthSettingsSection(
                    isSyncEnabled: $isSyncEnabled,
                    lastImportText: lastImportText,
                    hkWeight: $hkWeight,
                    hkBodyFat: $hkBodyFat,
                    hkHeight: $hkHeight,
                    hkLeanMass: $hkLeanMass,
                    hkWaist: $hkWaist
                )
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Health"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct UnitsSettingsDetailView: View {
    @Binding var unitsSystem: String

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                UnitsSettingsSection(unitsSystem: $unitsSystem)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Units"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct AIInsightsSettingsDetailView: View {
    @EnvironmentObject private var premiumStore: PremiumStore
    @Binding var appleIntelligenceEnabled: Bool

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                Section {
                    SettingsCard(tint: Color.cyan.opacity(0.12)) {
                        SettingsCardHeader(title: AppLocalization.string("AI Insights"), systemImage: "sparkles")
                        if premiumStore.isPremium {
                            if AppleIntelligenceSupport.isAvailable() {
                                Toggle(isOn: $appleIntelligenceEnabled) {
                                    Text(AppLocalization.string("Enable AI Insights"))
                                }
                                .tint(Color.appAccent)
                                .onChange(of: appleIntelligenceEnabled) { _, _ in Haptics.selection() }
                                .frame(minHeight: 44)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(AppLocalization.string("AI Insights aren’t available right now."))
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
                                    premiumStore.presentPaywall(reason: .feature("AI Insights"))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.appAccent)
                                .frame(minHeight: 44)
                            }
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowInsets(settingsComponentsRowInsets)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("AI Insights"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct ProfileSettingsSection: View {
    @Binding var userName: String
    @Binding var userGender: String
    @Binding var userAge: Int
    @Binding var manualHeight: Double
    @Binding var unitsSystem: String

    @State private var ageInput: String = ""
    @State private var heightInput: String = ""

    private var genderLabel: String {
        switch userGender {
        case "male":
            return AppLocalization.string("Male")
        case "female":
            return AppLocalization.string("Female")
        default:
            return AppLocalization.string("Not specified")
        }
    }

    private var heightUnitSymbol: String {
        MetricKind.height.unitSymbol(unitsSystem: unitsSystem)
    }
    
    var body: some View {
        Section {
            SettingsCard(tint: Color.white.opacity(0.08)) {
                SettingsCardHeader(title: AppLocalization.string("Profile"), systemImage: "person.crop.circle")

                HStack(spacing: 12) {
                    GlassPillIcon(systemName: "person.fill")
                        .frame(width: 60)
                    Text(AppLocalization.string("Name"))
                    Spacer()
                    TextField(AppLocalization.string("Add name"), text: $userName)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .foregroundStyle(userName.isEmpty ? .secondary : Color.appAccent)
                        .frame(minWidth: 120)
                }

                SettingsRowDivider()

                HStack(spacing: 12) {
                    GlassPillIcon(systemName: "figure.stand.dress.line.vertical.figure")
                        .frame(width: 60)
                    Text(AppLocalization.string("Gender"))
                    Spacer()
                    Menu {
                        Button(AppLocalization.string("Not specified")) { userGender = "notSpecified" }
                        Button(AppLocalization.string("Male")) { userGender = "male" }
                        Button(AppLocalization.string("Female")) { userGender = "female" }
                    } label: {
                        HStack(spacing: 6) {
                            Text(genderLabel)
                                .foregroundStyle(Color.appAccent)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.appAccent)
                        }
                    }
                    .buttonStyle(.plain)
                }

                SettingsRowDivider()

                HStack(spacing: 12) {
                    GlassPillIcon(systemName: "calendar")
                        .frame(width: 60)
                    Text(AppLocalization.string("Age"))
                    Spacer()
                    TextField("0", text: $ageInput)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .foregroundStyle(ageInput.isEmpty ? .secondary : Color.appAccent)
                        .frame(minWidth: 48)
                    Text(AppLocalization.string("profile.unit.age"))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .onChange(of: ageInput) { _, value in
                    let digits = value.filter(\.isNumber)
                    if digits != value {
                        ageInput = digits
                        return
                    }
                    userAge = Int(digits) ?? 0
                }
                .frame(minHeight: 44)

                SettingsRowDivider()

                HStack(spacing: 12) {
                    GlassPillIcon(systemName: "figure.stand")
                        .frame(width: 60)
                    Text(AppLocalization.string("Height"))
                    Spacer()
                    TextField("0", text: $heightInput)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .foregroundStyle(heightInput.isEmpty ? .secondary : Color.appAccent)
                        .frame(minWidth: 64)
                    Text(heightUnitSymbol)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .onChange(of: heightInput) { _, value in
                    let normalized = value.replacingOccurrences(of: ",", with: ".")
                    if normalized != value {
                        heightInput = normalized
                        return
                    }
                    guard let parsed = Double(normalized), parsed > 0 else {
                        manualHeight = 0
                        return
                    }
                    manualHeight = MetricKind.height.valueToMetric(fromDisplay: parsed, unitsSystem: unitsSystem)
                }
                .onChange(of: unitsSystem) { _, _ in
                    syncHeightInput()
                }
                .frame(minHeight: 44)
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
        .onAppear {
            syncAgeInput()
            syncHeightInput()
        }
    }

    private func syncAgeInput() {
        ageInput = userAge > 0 ? "\(userAge)" : ""
    }

    private func syncHeightInput() {
        guard manualHeight > 0 else {
            heightInput = ""
            return
        }
        let displayValue = MetricKind.height.valueForDisplay(fromMetric: manualHeight, unitsSystem: unitsSystem)
        heightInput = unitsSystem == "imperial"
            ? String(format: "%.1f", displayValue)
            : String(format: "%.0f", displayValue)
    }
}

struct HomeSettingsSection: View {
    @Binding var showMeasurementsOnHome: Bool
    @Binding var showLastPhotosOnHome: Bool
    @Binding var showHealthMetricsOnHome: Bool
    @Binding var showOnboardingChecklistOnHome: Bool
    
    var body: some View {
        Section {
            SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                SettingsCardHeader(title: AppLocalization.string("Home"), systemImage: "house.fill")
                Toggle(isOn: $showMeasurementsOnHome) {
                    HStack(spacing: 12) {
                        GlassPillIcon(systemName: "chart.line.uptrend.xyaxis")
                        Text(AppLocalization.string("Show measurements on Home"))
                    }
                }
                .tint(Color.appAccent)
                .onChange(of: showMeasurementsOnHome) { _, _ in Haptics.selection() }
                SettingsRowDivider()
                Toggle(isOn: $showLastPhotosOnHome) {
                    HStack(spacing: 12) {
                        GlassPillIcon(systemName: "photo.on.rectangle")
                        Text(AppLocalization.string("Show photos on Home"))
                    }
                }
                .tint(Color.appAccent)
                .onChange(of: showLastPhotosOnHome) { _, _ in Haptics.selection() }
                SettingsRowDivider()
                Toggle(isOn: $showHealthMetricsOnHome) {
                    HStack(spacing: 12) {
                        GlassPillIcon(systemName: "heart.fill")
                        Text(AppLocalization.string("Show health summary on Home"))
                    }
                }
                .tint(Color.appAccent)
                .onChange(of: showHealthMetricsOnHome) { _, _ in Haptics.selection() }
                SettingsRowDivider()
                Toggle(isOn: $showOnboardingChecklistOnHome) {
                    HStack(spacing: 12) {
                        GlassPillIcon(systemName: "list.bullet.clipboard")
                        Text(AppLocalization.string("Show setup checklist on Home"))
                    }
                }
                .tint(Color.appAccent)
                .onChange(of: showOnboardingChecklistOnHome) { _, _ in Haptics.selection() }
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
    }
}

struct HealthIndicatorsSettingsSection: View {
    @Binding var showWHtROnHome: Bool
    @Binding var showRFMOnHome: Bool
    @Binding var showBMIOnHome: Bool
    @Binding var showBodyFatOnHome: Bool
    @Binding var showLeanMassOnHome: Bool
    @Binding var showABSIOnHome: Bool
    @Binding var showConicityOnHome: Bool

    var body: some View {
        Section {
            SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                SettingsCardHeader(title: AppLocalization.string("Health indicators"), systemImage: "heart.text.square.fill")
                VStack(spacing: 0) {
                    metricsGroupTitle("Core indicators")
                    metricToggle(AppLocalization.string("WHtR (Waist-to-Height Ratio)"), isOn: $showWHtROnHome)
                    rowDivider
                    metricToggle(AppLocalization.string("RFM (Relative Fat Mass)"), isOn: $showRFMOnHome)
                    rowDivider
                    metricToggle(AppLocalization.string("BMI (Body Mass Index)"), isOn: $showBMIOnHome)

                    metricsGroupTitle("Body composition")
                    metricToggle(AppLocalization.string("Body Fat Percentage"), isOn: $showBodyFatOnHome)
                    rowDivider
                    metricToggle(AppLocalization.string("Lean Body Mass"), isOn: $showLeanMassOnHome)

                    metricsGroupTitle("Risk signals")
                    metricToggle(AppLocalization.string("Body Shape Risk (ABSI)"), isOn: $showABSIOnHome)
                    rowDivider
                    metricToggle(AppLocalization.string("Central Fat Risk (Conicity)"), isOn: $showConicityOnHome)
                }
                .padding(.top, 6)
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
    }

    private func metricsGroupTitle(_ title: String) -> some View {
        Text(AppLocalization.string(title))
            .font(AppTypography.captionEmphasis)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
        }
        .tint(Color.appAccent)
        .onChange(of: isOn.wrappedValue) { _, _ in Haptics.selection() }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }

    private var rowDivider: some View {
        Divider()
            .overlay(Color.white.opacity(0.12))
            .padding(.vertical, 4)
    }
}

struct SettingsCard<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: Content

    init(tint: Color, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppGlassBackground(
                depth: .base,
                cornerRadius: settingsComponentsCardCornerRadius,
                tint: tint
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: settingsComponentsCardCornerRadius, style: .continuous))
    }
}

struct SettingsCardHeader: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color(hex: "#FCA311"))
            }
            Text(title)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(.white)
        }
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.white.opacity(0.12))
    }
}

struct SettingsScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
