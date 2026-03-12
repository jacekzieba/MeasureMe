import SwiftData
import SwiftUI

struct ProfileSettingsSection: View {
    private let theme = FeatureTheme.settings
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
            SettingsCard(tint: AppColorRoles.surfacePrimary) {
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
                        .font(AppTypography.body)
                        .foregroundStyle(userName.isEmpty ? AppColorRoles.textTertiary : theme.accent)
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
                                .font(AppTypography.body)
                                .foregroundStyle(theme.accent)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(AppTypography.iconSmall)
                                .foregroundStyle(theme.accent)
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
                    TextField(AppLocalization.string("0"), text: $ageInput)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .font(AppTypography.body)
                        .foregroundStyle(ageInput.isEmpty ? AppColorRoles.textTertiary : theme.accent)
                        .frame(minWidth: 48)
                    Text(AppLocalization.string("profile.unit.age"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
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
                    TextField(AppLocalization.string("0"), text: $heightInput)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .font(AppTypography.body)
                        .foregroundStyle(heightInput.isEmpty ? AppColorRoles.textTertiary : theme.accent)
                        .frame(minWidth: 64)
                    Text(heightUnitSymbol)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
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

// MARK: - Profile Stats Card

struct ProfileStatsCard: View {
    @Query private var allSamples: [MetricSample]
    private let theme = FeatureTheme.settings

    var body: some View {
        Section {
            SettingsCard(tint: theme.softTint) {
                SettingsCardHeader(
                    title: AppLocalization.string("Your Progress"),
                    systemImage: "chart.line.uptrend.xyaxis"
                )

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("\(allSamples.count)")
                        .font(AppTypography.dataCompact)
                        .foregroundStyle(theme.accent)
                        .contentTransition(.numericText())
                        .accessibilityLabel(AppLocalization.string("profile.stats.accessibility", allSamples.count))

                    Text(AppLocalization.string("total measurements"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                }

                SettingsRowDivider()

                Text(motivationalPhrase)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
    }

    private var motivationalPhrase: String {
        switch allSamples.count {
        case 0:
            return AppLocalization.string("profile.stats.phrase.0")
        case 1...10:
            return AppLocalization.string("profile.stats.phrase.1")
        case 11...50:
            return AppLocalization.string("profile.stats.phrase.2")
        case 51...100:
            return AppLocalization.string("profile.stats.phrase.3")
        case 101...250:
            return AppLocalization.string("profile.stats.phrase.4")
        case 251...500:
            return AppLocalization.string("profile.stats.phrase.5")
        case 501...1000:
            return AppLocalization.string("profile.stats.phrase.6")
        default:
            return AppLocalization.string("profile.stats.phrase.7")
        }
    }
}
