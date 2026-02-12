import SwiftUI

enum ProfileRoute: Hashable, Identifiable {
    case age
    case height

    var id: Self { self }
}

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
        .listRowInsets(settingsRowInsets)
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
            }
            
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
                    Text(AppLocalization.string("Metrics"))
                    Spacer()
                    Text(isSyncEnabled ? AppLocalization.string("Show") : AppLocalization.string("Disabled"))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isMetricsExpanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            
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
                .frame(maxHeight: isMetricsExpanded ? .infinity : 0, alignment: .top)
                .clipped()
                .opacity(isMetricsExpanded ? 1 : 0)
                .animation(nil, value: isMetricsExpanded)
            }
        }
    
    private var rowDivider: some View {
        Divider()
            .overlay(Color.white.opacity(0.12))
            .padding(.vertical, 4)
    }
    
    private func healthMetricRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
        }
        .tint(Color.appAccent)
        .onChange(of: isOn.wrappedValue) { _, _ in Haptics.selection() }
        .padding(.vertical, 10)
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
        .listRowInsets(settingsRowInsets)
        .listRowBackground(Color.clear)
    }
}

struct ProfileSettingsSection: View {
    @Binding var userName: String
    @Binding var userGender: String
    let currentAgeText: String?
    let currentHeightText: String?

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

                NavigationLink(value: ProfileRoute.age) {
                    HStack(spacing: 12) {
                        GlassPillIcon(systemName: "calendar")
                            .frame(width: 60)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppLocalization.string("Age"))
                            if let ageText = currentAgeText {
                                Text(ageText)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                SettingsRowDivider()

                NavigationLink(value: ProfileRoute.height) {
                    HStack(spacing: 12) {
                        GlassPillIcon(systemName: "figure.stand")
                            .frame(width: 60)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppLocalization.string("Height"))
                            if let heightText = currentHeightText {
                                Text(heightText)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsRowInsets)
        .listRowBackground(Color.clear)
    }
}

struct HomeSettingsSection: View {
    @Binding var showMeasurementsOnHome: Bool
    @Binding var showLastPhotosOnHome: Bool
    @Binding var showHealthMetricsOnHome: Bool
    
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
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsRowInsets)
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

    @State private var isExpanded: Bool = false
    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Section {
            SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                SettingsCardHeader(title: AppLocalization.string("Health indicators"), systemImage: "heart.text.square.fill")

                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 12) {
                        GlassPillIcon(systemName: "slider.horizontal.3")
                        Text(AppLocalization.string("Choose indicators to show"))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

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
                .frame(maxHeight: isExpanded ? .infinity : 0, alignment: .top)
                .clipped()
                .opacity(isExpanded ? 1 : 0)
                .animation(nil, value: isExpanded)
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsRowInsets)
        .listRowBackground(Color.clear)
    }

    private var shouldAnimate: Bool {
        animationsEnabled && !reduceMotion
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
                cornerRadius: settingsCardCornerRadius,
                tint: tint
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: settingsCardCornerRadius, style: .continuous))
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
