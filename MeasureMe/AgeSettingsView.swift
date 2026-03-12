// AgeSettingsView.swift
//
// **AgeSettingsView**
// Widok zarządzania wiekiem użytkownika.
//
// **Funkcje:**
// - Wyświetlanie aktualnego wieku
// - Import wieku z HealthKit (jeśli dostępny)
// - Manualne wprowadzenie wieku jako liczby
//
import SwiftUI

struct AgeSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppSetting(\.profile.userAge) private var userAge: Int = 0
    @AppSetting(\.health.isSyncEnabled) private var isSyncEnabled: Bool = false

    @State private var ageInput: String = ""
    @State private var isLoadingHealthKit = false
    @State private var healthKitError: String?
    private let theme = FeatureTheme.settings

    private var ageValidation: MetricInputValidator.ValidationResult {
        MetricInputValidator.validateAgeValue(Int(ageInput))
    }

    @FocusState private var isAgeFocused: Bool

    var body: some View {
        SettingsScrollDetailScaffold(title: AppLocalization.string("Age"), theme: .settings) {
                    // MARK: - Age display / hero card
                    AppGlassCard(
                        depth: .floating,
                        tint: theme.softTint,
                        contentPadding: 24
                    ) {
                        if userAge > 0 {
                            VStack(spacing: 8) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppColorRoles.stateSuccess)
                                    Text(AppLocalization.string("Current age"))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColorRoles.textSecondary)
                                }

                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(userAge)")
                                        .font(AppTypography.dataPrimary)
                                        .foregroundStyle(theme.accent)

                                    Text(AppLocalization.string("years old"))
                                        .font(AppTypography.headline)
                                        .foregroundStyle(AppColorRoles.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 120)
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title)
                                    .foregroundStyle(AppColorRoles.stateWarning)
                                Text(AppLocalization.string("No age set"))
                                    .font(AppTypography.bodyEmphasis)
                                Text(AppLocalization.string("Set your age to improve health metric accuracy."))
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
                            if isSyncEnabled {
                                Button {
                                    importFromHealthKit()
                                } label: {
                                    HStack(spacing: 12) {
                                        if isLoadingHealthKit {
                                            ProgressView()
                                                .frame(width: 44, height: 44)
                                        } else {
                                            GlassPillIcon(systemName: "heart.fill")
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(AppLocalization.string("Import from Health"))
                                                .font(AppTypography.bodyEmphasis)
                                                .foregroundStyle(isLoadingHealthKit ? AppColorRoles.textSecondary : AppColorRoles.textPrimary)
                                            Text(AppLocalization.string("Use age from HealthKit"))
                                                .font(AppTypography.caption)
                                                .foregroundStyle(AppColorRoles.textSecondary)
                                        }
                                    }
                                }
                                .disabled(isLoadingHealthKit)

                                if let error = healthKitError {
                                    Text(error)
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColorRoles.stateError)
                                }

                                Divider().overlay(AppColorRoles.borderSubtle)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text(AppLocalization.string("Enter your age"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColorRoles.textSecondary)

                                TextField(AppLocalization.string("Age in years"), text: $ageInput)
                                    .keyboardType(.numberPad)
                                    .font(AppTypography.dataValue)
                                    .focused($isAgeFocused)

                                if !ageValidation.isValid, !ageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let message = ageValidation.message {
                                    Text(message)
                                        .font(AppTypography.micro)
                                        .foregroundStyle(AppColorRoles.stateError)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Button {
                                saveAge()
                    } label: {
                        Text(AppLocalization.string("Save"))
                            .font(AppTypography.buttonLabel)
                    }
                            .buttonStyle(LiquidCapsuleButtonStyle())
                            .disabled(!ageValidation.isValid)
                            .frame(maxWidth: .infinity)
                        }
                    }

                    // MARK: - Info card
                    AppGlassCard(depth: .base) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(AppLocalization.string("Why is age important?"), systemImage: "info.circle")
                                .font(AppTypography.bodyEmphasis)

                            Text(AppLocalization.string("Age can be used for:"))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColorRoles.textSecondary)

                            VStack(alignment: .leading, spacing: 8) {
                                InfoRow(
                                    icon: "chart.bar.fill",
                                    title: "Health insights",
                                    description: "Age-based recommendations"
                                )

                                InfoRow(
                                    icon: "target",
                                    title: "Goal suggestions",
                                    description: "Age-appropriate targets"
                                )
                            }
                        }
                    }
        }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                Button(AppLocalization.string("Done")) {
                    isAgeFocused = false
                }
            }
        }
        .onAppear {
            if userAge > 0 {
                ageInput = "\(userAge)"
            }
        }
    }

    private func saveAge() {
        guard let age = Int(ageInput) else { return }
        userAge = age
        dismiss()
    }

    private func importFromHealthKit() {
        isLoadingHealthKit = true
        healthKitError = nil

        Task {
            do {
                if let birthDate = try HealthKitManager.shared.fetchDateOfBirth(),
                   let age = HealthKitManager.calculateAge(from: birthDate) {
                    await MainActor.run {
                        userAge = age
                        ageInput = "\(age)"
                        isLoadingHealthKit = false
                    }
                } else {
                    await MainActor.run {
                        healthKitError = "No age found in Health app"
                        isLoadingHealthKit = false
                    }
                }
            } catch {
                await MainActor.run {
                    healthKitError = AppLocalization.string("healthkit.import.failed", error.localizedDescription)
                    isLoadingHealthKit = false
                }
            }
        }
    }
}

// MARK: - Info Row (reused)

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
