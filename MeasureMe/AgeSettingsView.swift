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

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))

            List {
                Section {
                    if userAge > 0 {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(AppLocalization.string("Current age"))
                                    .font(.system(.headline, design: .rounded))
                            }

                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(userAge)")
                                    .font(.system(size: 48, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(hex: "#FCA311"))

                                Text(AppLocalization.string("years old"))
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(AppLocalization.string("No age set"))
                                    .font(.system(.headline, design: .rounded))
                            }

                            Text(AppLocalization.string("Set your age to improve health metric accuracy."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                } header: {
                    Text(AppLocalization.string("Age"))
                }

                Section {
                    if isSyncEnabled {
                        Button {
                            importFromHealthKit()
                        } label: {
                            HStack(spacing: 12) {
                                if isLoadingHealthKit {
                                    ProgressView()
                                        .frame(width: 40, height: 40)
                                } else {
                                    GlassPillIcon(systemName: "heart.fill")
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(AppLocalization.string("Import from Health"))
                                        .font(.body)
                                        .foregroundStyle(isLoadingHealthKit ? .secondary : .primary)
                                    Text(AppLocalization.string("Use age from HealthKit"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(isLoadingHealthKit)

                        if let error = healthKitError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppLocalization.string("Enter your age"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField(AppLocalization.string("Age in years"), text: $ageInput)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)

                        if !ageValidation.isValid, !ageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let message = ageValidation.message {
                            Text(message)
                                .font(AppTypography.micro)
                                .foregroundStyle(Color.red.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 6)

                    Button {
                        saveAge()
                    } label: {
                        HStack {
                            Spacer()
                            Text(AppLocalization.string("Save"))
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!ageValidation.isValid)
                } header: {
                    Text(AppLocalization.string("Options"))
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(AppLocalization.string("Why is age important?"), systemImage: "info.circle")
                            .font(.system(.headline, design: .rounded))

                        Text(AppLocalization.string("Age can be used for:"))
                            .font(.subheadline)
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
            .navigationTitle(AppLocalization.string("Age"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .onAppear {
                if userAge > 0 {
                    ageInput = "\(userAge)"
                }
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
