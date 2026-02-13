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
    
    @AppStorage("unitsSystem") private var unitsSystem: String = "metric"
    @AppStorage("manualHeight") private var manualHeight: Double = 0.0
    @AppStorage("isSyncEnabled") private var isSyncEnabled: Bool = false
    
    @Query(sort: [SortDescriptor(\MetricSample.date, order: .reverse)])
    private var samples: [MetricSample]
    @State private var isImportingHeight = false
    @State private var healthImportMessage: String?
    
    
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
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            
            // Zawartość
            List {
                // MARK: - Current Height Section
                Section {
                    if manualHeight > 0 {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "pencil.circle.fill")
                                    .foregroundStyle(Color(hex: "#FCA311"))
                                Text(AppLocalization.string("Manual height"))
                                    .font(.system(.headline, design: .rounded))
                            }
                            
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(formattedHeight(manualHeight))
                                    .font(AppTypography.displaySmall)
                                    .monospacedDigit()
                                    .foregroundStyle(Color(hex: "#FCA311"))
                                
                                Text(heightUnit)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Text(AppLocalization.string("You've set your height manually. Health metrics will use this value."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                        .padding(.vertical, 8)
                    } else if let tracked = latestTrackedHeight {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(AppLocalization.string("Latest height"))
                                    .font(.system(.headline, design: .rounded))
                            }
                            
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(formattedHeight(tracked.value))
                                    .font(AppTypography.displaySmall)
                                    .monospacedDigit()
                                    .foregroundStyle(Color(hex: "#FCA311"))
                                
                                Text(heightUnit)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Text(AppLocalization.string("height.last.updated", tracked.date.formatted(date: .abbreviated, time: .shortened)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Text(AppLocalization.string("This height is used for health metric calculations."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                        .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(AppLocalization.string("No height set"))
                                    .font(.system(.headline, design: .rounded))
                            }
                            
                            Text(AppLocalization.string("Set your height to calculate health metrics like WHtR (Waist-to-Height Ratio)."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                } header: {
                    Text(AppLocalization.string("Current Height"))
                }
                
                // MARK: - Options Section
                Section {
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
                                    .font(.body)
                                Text(AppLocalization.string("Used for health metrics"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if isSyncEnabled {
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
                                        .font(.body)
                                    Text(AppLocalization.string("Sync height for calculations"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(isImportingHeight)

                        if let healthImportMessage {
                            Text(healthImportMessage)
                                .font(AppTypography.caption)
                                .foregroundStyle(Color.red.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } header: {
                    Text(AppLocalization.string("Options"))
                } footer: {
                    Text(AppLocalization.string("Height is stored in Settings and used to calculate health indicators like WHtR and BMI."))
                }
                
                // MARK: - Info Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(AppLocalization.string("Why is height important?"), systemImage: "info.circle")
                            .font(.system(.headline, design: .rounded))
                        
                        Text(AppLocalization.string("Height is used to calculate important health metrics:"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
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
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text(AppLocalization.string("Information"))
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .navigationTitle(AppLocalization.string("Height"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
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
    @AppStorage("manualHeight") private var manualHeight: Double = 0.0
    
    let currentHeight: Double?
    let unitsSystem: String
    
    @State private var heightInput: String = ""
    @State private var feetInput: String = ""
    @State private var inchesInput: String = ""
    @FocusState private var focusedField: Field?
    
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
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            
            // Zawartość
            List {
                Section {
                    if unitsSystem == "imperial" {
                        // Imperial: Feet and Inches
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(AppLocalization.string("Feet"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                TextField(AppLocalization.string("0"), text: $feetInput)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedField, equals: .feet)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(AppLocalization.string("Inches"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                TextField(AppLocalization.string("0"), text: $inchesInput)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedField, equals: .inches)
                            }
                        }
                        .padding(.vertical, 8)
                    } else {
                        // Metric: Centimeters
                        VStack(alignment: .leading, spacing: 8) {
                            Text(AppLocalization.string("Height (cm)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            TextField(AppLocalization.string("0.0"), text: $heightInput)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .height)
                        }
                        .padding(.vertical, 8)
                    }

                    if shouldShowValidationError, !heightValidation.isValid, let message = heightValidation.message {
                        Text(message)
                            .font(AppTypography.micro)
                            .foregroundStyle(Color.red.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text(AppLocalization.string("Enter your height"))
                } footer: {
                    Text(AppLocalization.string("This height will be used for health metric calculations like WHtR."))
                }
                
                Section {
                    Button {
                        saveHeight()
                    } label: {
                        HStack {
                            Spacer()
                            Text(AppLocalization.string("Save"))
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!isValidInput)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .navigationTitle(AppLocalization.string("Set Height"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    Button(AppLocalization.string("Done")) {
                        focusedField = nil
                    }
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
                .foregroundStyle(Color(hex: "#FCA311"))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
