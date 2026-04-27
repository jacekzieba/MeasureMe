import SwiftData
import SwiftUI
import PhotosUI

struct ProfileSettingsSection: View {
    private let theme = FeatureTheme.settings
    @Binding var userName: String
    @Binding var userGender: String
    @Binding var userAge: Int
    @Binding var manualHeight: Double
    @Binding var unitsSystem: String
    @Binding var profilePhotoData: Data?

    @State private var ageInput: String = ""
    @State private var heightInput: String = ""
    @State private var selectedProfilePhoto: PhotosPickerItem?
    @State private var isProcessingProfilePhoto = false

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

                profilePhotoRow

                SettingsRowDivider()

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
        .onChange(of: selectedProfilePhoto) { _, item in
            guard let item else { return }
            Task { await importProfilePhoto(from: item) }
        }
    }

    private var profilePhotoRow: some View {
        HStack(alignment: .center, spacing: 14) {
            ProfileAvatarPreview(profilePhotoData: profilePhotoData, fallbackText: avatarFallbackText)
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 5) {
                Text(AppLocalization.string("Profile photo"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Text(AppLocalization.string("Shown on your Home dashboard."))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                PhotosPicker(
                    selection: $selectedProfilePhoto,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(
                        profilePhotoData == nil
                            ? AppLocalization.string("Add photo")
                            : AppLocalization.string("Change photo"),
                        systemImage: "photo"
                    )
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(isProcessingProfilePhoto)
                .accessibilityIdentifier("settings.profile.photo.picker")

                if profilePhotoData != nil {
                    Button(role: .destructive) {
                        profilePhotoData = nil
                    } label: {
                        Text(AppLocalization.string("Remove"))
                            .font(AppTypography.caption)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.profile.photo.remove")
                }
            }
        }
        .frame(minHeight: 82)
    }

    private var avatarFallbackText: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "M" }
        return String(first).uppercased(with: AppLocalization.currentLanguage.locale)
    }

    @MainActor
    private func importProfilePhoto(from item: PhotosPickerItem) async {
        isProcessingProfilePhoto = true
        defer {
            isProcessingProfilePhoto = false
            selectedProfilePhoto = nil
        }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        let prepared = PhotoUtilities.prepareImportedImage(image, maxDimension: 512)
        profilePhotoData = PhotoUtilities.makeGridThumbnailData(
            from: prepared,
            size: CGSize(width: 220, height: 220),
            targetBytes: 55_000,
            maxBytes: 80_000
        )
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

private struct ProfileAvatarPreview: View {
    let profilePhotoData: Data?
    let fallbackText: String

    var body: some View {
        ZStack {
            if let profilePhotoData, let image = UIImage(data: profilePhotoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color(hex: "#FCA311"), Color(hex: "#5DD39E")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(fallbackText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.20), lineWidth: 1)
        )
        .contentShape(Circle())
        .accessibilityLabel(AppLocalization.string("Profile photo"))
    }
}

// MARK: - Profile Stats Card

struct ProfileStatsCard: View {
    @Query private var allSamples: [MetricSample]
    private let theme = FeatureTheme.settings

    private var totalLogs: Int {
        if let firstDate = StreakManager.shared.firstActiveDate {
            return allSamples.filter { $0.date >= firstDate }.count
        }
        return allSamples.count
    }

    var body: some View {
        Section {
            SettingsCard(tint: theme.softTint) {
                SettingsCardHeader(
                    title: AppLocalization.string("Your Progress"),
                    systemImage: "chart.line.uptrend.xyaxis"
                )

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("\(totalLogs)")
                        .font(AppTypography.dataCompact)
                        .foregroundStyle(theme.accent)
                        .contentTransition(.numericText())
                        .accessibilityLabel(AppLocalization.string("profile.stats.accessibility", totalLogs))

                    Text(AppLocalization.string("streak.detail.totalLogs"))
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
        switch totalLogs {
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
