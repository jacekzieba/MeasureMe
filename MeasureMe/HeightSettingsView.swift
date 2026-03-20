// HeightSettingsView.swift
//
// **HeightSettingsView**
// Widok zarządzania wzrostem użytkownika.
//
// **Funkcje:**
// - Wyświetlanie aktualnego wzrostu ze śledzonych metryk (jeśli istnieje)
// - Możliwość manualnego wprowadzenia wzrostu w ustawieniach (dla osób nieśledzących wzrostu)
// - Integracja z systemem jednostek (metric/imperial)
// - Synchronizacja z metrykami Health
//
import SwiftUI
import SwiftData

struct HeightSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    
    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"
    @AppSetting(\.profile.manualHeight) private var manualHeight: Double = 0.0
    @AppSetting(\.health.isSyncEnabled) private var isSyncEnabled: Bool = false
    
    @Query(sort: [SortDescriptor(\MetricSample.date, order: .reverse)])
    private var samples: [MetricSample]
    @State private var isImportingHeight = false
    @State private var healthImportMessage: String?
    private let theme = FeatureTheme.settings
    
    
    // Pobierz najnowszy wzrost ze śledzonych metryk
    private var latestTrackedHeight: MetricSample? {
        samples.first { $0.kindRaw == MetricKind.height.rawValue }
    }
    
    // Skuteczny wzrost do użycia w obliczeniach
    private var effectiveHeight: Double? {
        if manualHeight > 0 {
            return manualHeight
        }
        return latestTrackedHeight?.value
    }
    
    var body: some View {
        SettingsScrollDetailScaffold(title: AppLocalization.string("Height"), theme: .settings) {
                    // MARK: - Current Height hero card
                    AppGlassCard(
                        depth: .floating,
                        tint: theme.softTint,
                        contentPadding: 24
                    ) {
                        if manualHeight > 0 {
                            VStack(spacing: 8) {
                                HStack {
                                    Image(systemName: "pencil.circle.fill")
                                        .foregroundStyle(theme.accent)
                                    Text(AppLocalization.string("Manual height"))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColorRoles.textSecondary)
                                }

                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(formattedHeight(manualHeight))
                                        .font(AppTypography.dataPrimary)
                                        .foregroundStyle(theme.accent)

                                    Text(heightUnit)
                                        .font(AppTypography.headline)
                                        .foregroundStyle(AppColorRoles.textSecondary)
                                }

                                Text(AppLocalization.string("You've set your height manually. Health metrics will use this value."))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColorRoles.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 120)
                        } else if let tracked = latestTrackedHeight {
                            VStack(spacing: 8) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppColorRoles.stateSuccess)
                                    Text(AppLocalization.string("Latest height"))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColorRoles.textSecondary)
                                }

                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(formattedHeight(tracked.value))
                                        .font(AppTypography.dataPrimary)
                                        .foregroundStyle(theme.accent)

                                    Text(heightUnit)
                                        .font(AppTypography.headline)
                                        .foregroundStyle(AppColorRoles.textSecondary)
                                }

                                Text(AppLocalization.string("height.last.updated", tracked.date.formatted(date: .abbreviated, time: .shortened)))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColorRoles.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 120)
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title)
                                    .foregroundStyle(AppColorRoles.stateWarning)
                                Text(AppLocalization.string("No height set"))
                                    .font(AppTypography.bodyEmphasis)
                                Text(AppLocalization.string("Set your height to calculate health metrics like WHtR (Waist-to-Height Ratio)."))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColorRoles.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 100)
                        }
                    }

                    // MARK: - Options card
                    AppGlassCard(
                        depth: .elevated,
                        tint: AppColorRoles.surfacePrimary,
                        contentPadding: 16
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            NavigationLink {
                                ManualHeightInputView(
                                    currentHeight: effectiveHeight,
                                    unitsSystem: unitsSystem
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    GlassPillIcon(systemName: "pencil")
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(AppLocalization.string("Set height manually"))
                                                .font(AppTypography.bodyEmphasis)
                                                .foregroundStyle(AppColorRoles.textPrimary)
                                            Text(AppLocalization.string("Used for health metrics"))
                                                .font(AppTypography.caption)
                                                .foregroundStyle(AppColorRoles.textSecondary)
                                        }
                                    }
                                }

                            if isSyncEnabled {
                                Divider().overlay(Color.white.opacity(0.12))

                                Button {
                                    Task {
                                        await importLatestHeightFromHealth()
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        if isImportingHeight {
                                            ProgressView()
                                                .frame(width: 44, height: 44)
                                        } else {
                                            GlassPillIcon(systemName: "arrow.down.circle")
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(AppLocalization.string("Import latest from Health"))
                                                .font(AppTypography.bodyEmphasis)
                                                .foregroundStyle(AppColorRoles.textPrimary)
                                            Text(AppLocalization.string("Sync height for calculations"))
                                                .font(AppTypography.caption)
                                                .foregroundStyle(AppColorRoles.textSecondary)
                                        }
                                    }
                                }
                                .disabled(isImportingHeight)

                                if let healthImportMessage {
                                    Text(healthImportMessage)
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColorRoles.stateError)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    // MARK: - Help text
                    AppGlassCard(depth: .base) {
                        Text(AppLocalization.string("Height is stored in Settings and used to calculate health indicators like WHtR and BMI."))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }

                    // MARK: - Info card
                    AppGlassCard(depth: .base) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(AppLocalization.string("Why is height important?"), systemImage: "info.circle")
                                .font(AppTypography.bodyEmphasis)

                            Text(AppLocalization.string("Height is used to calculate important health metrics:"))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColorRoles.textSecondary)

                            VStack(alignment: .leading, spacing: 8) {
                                InfoRow(
                                    icon: "heart.text.square.fill",
                                    title: "WHtR",
                                    description: "Waist-to-Height Ratio"
                                )

                                InfoRow(
                                    icon: "figure.stand",
                                    title: "BMI",
                                    description: "Body Mass Index (if tracked)"
                                )
                            }
                        }
                    }
        }
    }
    
    // MARK: - Helpers
    
    private var heightUnit: String {
        MetricKind.height.unitSymbol(unitsSystem: unitsSystem)
    }
    
    private func formattedHeight(_ heightInCm: Double) -> String {
        let display = MetricKind.height.valueForDisplay(fromMetric: heightInCm, unitsSystem: unitsSystem)
        
        if unitsSystem == "imperial" {
            // Konwertuj cale na stopy i cale
            let totalInches = Int(display.rounded())
            let feet = totalInches / 12
            let inches = totalInches % 12
            return "\(feet)'\(inches)\""
        } else {
            return String(format: "%.1f", display)
        }
    }

    @MainActor
    private func importLatestHeightFromHealth() async {
        guard !isImportingHeight else { return }
        isImportingHeight = true
        healthImportMessage = nil
        defer { isImportingHeight = false }

        do {
            try await HealthKitManager.shared.importHeightFromHealthKit(to: context)
        } catch {
            healthImportMessage = AppLocalization.string("Could not import height from Health.")
            AppLog.debug("⚠️ Height import failed: \(error.localizedDescription)")
            Haptics.error()
        }
    }
}

// MARK: - Manual Height Input View

struct ManualHeightInputView: View {
    @Environment(\.dismiss) private var dismiss
    @AppSetting(\.profile.manualHeight) private var manualHeight: Double = 0.0
    
    let currentHeight: Double?
    let unitsSystem: String
    
    @State private var heightInput: String = ""
    @State private var feetInput: String = ""
    @State private var inchesInput: String = ""
    @FocusState private var focusedField: Field?
    private let theme = FeatureTheme.settings
    
    enum Field {
        case height, feet, inches
    }
    
    init(currentHeight: Double?, unitsSystem: String) {
        self.currentHeight = currentHeight
        self.unitsSystem = unitsSystem
        
        if let height = currentHeight {
            let display = MetricKind.height.valueForDisplay(fromMetric: height, unitsSystem: unitsSystem)
            
            if unitsSystem == "imperial" {
                let totalInches = Int(display.rounded())
                _feetInput = State(initialValue: "\(totalInches / 12)")
                _inchesInput = State(initialValue: "\(totalInches % 12)")
            } else {
                _heightInput = State(initialValue: String(format: "%.1f", display))
            }
        }
    }
    
    var body: some View {
        SettingsScrollDetailScaffold(title: AppLocalization.string("Set Height"), theme: .settings) {
                    // MARK: - Height input card
                    AppGlassCard(
                        depth: .floating,
                        tint: theme.softTint,
                        contentPadding: 24
                    ) {
                        VStack(spacing: 12) {
                            Text(AppLocalization.string("Enter your height"))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColorRoles.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if unitsSystem == "imperial" {
                                // Imperialne: stopy i cale
                                HStack(spacing: 16) {
                                    VStack(spacing: 4) {
                                        TextField("0", text: $feetInput)
                                            .keyboardType(.numberPad)
                                            .multilineTextAlignment(.center)
                                            .font(AppTypography.dataPrimary)
                                            .fixedSize()
                                            .focused($focusedField, equals: .feet)

                                        Text(AppLocalization.string("Feet"))
                                            .font(AppTypography.caption)
                                            .foregroundStyle(AppColorRoles.textSecondary)
                                    }

                                    Text("'")
                                        .font(AppTypography.displaySection)
                                        .foregroundStyle(AppColorRoles.textSecondary)

                                    VStack(spacing: 4) {
                                        TextField("0", text: $inchesInput)
                                            .keyboardType(.numberPad)
                                            .multilineTextAlignment(.center)
                                            .font(AppTypography.dataPrimary)
                                            .fixedSize()
                                            .focused($focusedField, equals: .inches)

                                        Text(AppLocalization.string("Inches"))
                                            .font(AppTypography.caption)
                                            .foregroundStyle(AppColorRoles.textSecondary)
                                    }

                                    Text("\"")
                                        .font(AppTypography.displaySection)
                                        .foregroundStyle(AppColorRoles.textSecondary)
                                }
                            } else {
                                // Metric: Centimeters hero value
                                HStack(spacing: 4) {
                                    TextField("0", text: $heightInput)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .font(AppTypography.dataPrimary)
                                        .fixedSize()
                                        .focused($focusedField, equals: .height)

                                    Text("cm")
                                        .font(AppTypography.headline)
                                        .foregroundStyle(AppColorRoles.textSecondary)
                                }
                            }

                            if focusedField == nil {
                                Text(AppLocalization.string("metric.input.tap_to_edit"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColorRoles.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 140)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if unitsSystem == "imperial" {
                                focusedField = .feet
                            } else {
                                focusedField = .height
                            }
                        }
                    }

                    // Walidacja pod kartą
                    if shouldShowValidationError, !heightValidation.isValid, let message = heightValidation.message {
                        Text(message)
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColorRoles.stateError)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // MARK: - Przycisk zapisu
                    Button {
                        saveHeight()
                    } label: {
                        Text(AppLocalization.string("Save"))
                            .font(AppTypography.buttonLabel)
                    }
                    .buttonStyle(LiquidCapsuleButtonStyle())
                    .disabled(!isValidInput)

                    // MARK: - Help text card
                    AppGlassCard(depth: .base) {
                        Text(AppLocalization.string("This height will be used for health metric calculations like WHtR."))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }
        }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                Button(AppLocalization.string("Done")) {
                    focusedField = nil
                }
            }
        }
    }
    
    private var isValidInput: Bool {
        heightValidation.isValid
    }

    private var shouldShowValidationError: Bool {
        if unitsSystem == "imperial" {
            return !feetInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !inchesInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !heightInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var heightValidation: MetricInputValidator.ValidationResult {
        if unitsSystem == "imperial" {
            return MetricInputValidator.validateHeightImperial(
                feet: Int(feetInput),
                inches: Int(inchesInput)
            )
        }
        guard let height = Double(heightInput) else {
            return MetricInputValidator.ValidationResult(
                isValid: false,
                message: AppLocalization.string("Height must be between 50 and 300 cm.")
            )
        }
        return MetricInputValidator.validateHeightMetricValue(height)
    }
    
    private func saveHeight() {
        guard heightValidation.isValid else { return }

        if unitsSystem == "imperial" {
            let feet = Int(feetInput) ?? 0
            let inches = Int(inchesInput) ?? 0
            let totalInches = Double(feet * 12 + inches)
            
            // Konwertuj na centymetry
            let heightInCm = MetricKind.height.valueToMetric(fromDisplay: totalInches, unitsSystem: unitsSystem)
            manualHeight = heightInCm
        } else {
            if let height = Double(heightInput) {
                let heightInCm = MetricKind.height.valueToMetric(fromDisplay: height, unitsSystem: unitsSystem)
                manualHeight = heightInCm
            }
        }
        
        dismiss()
    }
}

// MARK: - Info Row

private struct InfoRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppColorRoles.accentPrimary)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
            }
        }
    }
}
