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

    @AppStorage("userAge") private var userAge: Int = 0
    @AppStorage("isSyncEnabled") private var isSyncEnabled: Bool = false

    @State private var ageInput: String = ""
    @State private var isLoadingHealthKit = false
    @State private var healthKitError: String?

    private var ageValidation: MetricInputValidator.ValidationResult {
        MetricInputValidator.validateAgeValue(Int(ageInput))
    }

    @FocusState private var isAgeFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))

            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Age display / hero card
                    AppGlassCard(
                        depth: .floating,
                        tint: Color.cyan.opacity(0.12),
                        contentPadding: 24
                    ) {
                        if userAge > 0 {
                            VStack(spacing: 8) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(AppLocalization.string("Current age"))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(.secondary)
                                }

                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(userAge)")
                                        .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                                        .foregroundStyle(Color(hex: "#FCA311"))

                                    Text(AppLocalization.string("years old"))
                                        .font(.title.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 120)
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title)
                                    .foregroundStyle(.orange)
                                Text(AppLocalization.string("No age set"))
                                    .font(AppTypography.bodyEmphasis)
                                Text(AppLocalization.string("Set your age to improve health metric accuracy."))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 100)
                        }
                    }

                    // MARK: - Options card
                    AppGlassCard(
                        depth: .elevated,
                        tint: Color.cyan.opacity(0.08),
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
                                                .foregroundStyle(isLoadingHealthKit ? .secondary : .primary)
                                            Text(AppLocalization.string("Use age from HealthKit"))
                                                .font(AppTypography.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .disabled(isLoadingHealthKit)

                                if let error = healthKitError {
                                    Text(error)
                                        .font(AppTypography.caption)
                                        .foregroundStyle(.red)
                                }

                                Divider().overlay(Color.white.opacity(0.12))
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text(AppLocalization.string("Enter your age"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)

                                TextField(AppLocalization.string("Age in years"), text: $ageInput)
                                    .keyboardType(.numberPad)
                                    .font(.system(.body, design: .rounded).monospacedDigit())
                                    .focused($isAgeFocused)

                                if !ageValidation.isValid, !ageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let message = ageValidation.message {
                                    Text(message)
                                        .font(AppTypography.micro)
                                        .foregroundStyle(Color.red.opacity(0.9))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Button {
                                saveAge()
                            } label: {
                                Text(AppLocalization.string("Save"))
                                    .font(.system(.headline, design: .rounded).weight(.semibold))
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
                                .foregroundStyle(.secondary)

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
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
        }
        .navigationTitle(AppLocalization.string("Age"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
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
