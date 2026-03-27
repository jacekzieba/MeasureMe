import SwiftUI

/// Krok 1 onboardingu — dane profilowe (imię, wzrost, płeć, wiek).
struct OnboardingProfileStep: View {
    @Binding var nameInput: String
    @Binding var ageInput: String
    @Binding var heightInput: String
    @Binding var feetInput: String
    @Binding var inchesInput: String
    @Binding var userGender: String

    let unitsSystem: String

    @FocusState.Binding var focused: OnboardingView.FocusField?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            onboardingSlideHeader(title: OnboardingView.Step.profile.title, subtitle: OnboardingView.Step.profile.subtitle)

            profileField(title: AppLocalization.systemString("Name")) {
                TextField(AppLocalization.systemString("e.g., Jacek"), text: $nameInput)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .name)
                    .accessibilityIdentifier("onboarding.profile.name")
            }

            profileField(title: AppLocalization.systemString("Height")) {
                if unitsSystem == "imperial" {
                    HStack(spacing: 10) {
                        TextField(AppLocalization.systemString("Feet"), text: $feetInput)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .focused($focused, equals: .feet)
                        TextField(AppLocalization.systemString("Inches"), text: $inchesInput)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .focused($focused, equals: .inches)
                    }
                } else {
                    TextField(AppLocalization.systemString("Centimeters"), text: $heightInput)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused, equals: .height)
                        .accessibilityIdentifier("onboarding.profile.height")
                }
            }

            HStack(spacing: 10) {
                profileField(title: AppLocalization.systemString("Sex")) {
                    Picker("", selection: $userGender) {
                        Text(AppLocalization.systemString("Not specified")).tag("notSpecified")
                        Text(AppLocalization.systemString("Male")).tag("male")
                        Text(AppLocalization.systemString("Female")).tag("female")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("onboarding.profile.sex")
                }
            }

            profileField(title: AppLocalization.systemString("Age")) {
                TextField(AppLocalization.systemString("Age in years"), text: $ageInput)
                    .keyboardType(unitsSystem == "imperial" ? .numberPad : .decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .age)
                    .accessibilityIdentifier("onboarding.profile.age")
            }

            VStack(alignment: .leading, spacing: 8) {
                reasonRow(icon: "person.fill", text: AppLocalization.systemString("Name helps personalize your experience."))
                reasonRow(icon: "figure.stand", text: AppLocalization.systemString("Height improves BMI and waist-to-height indicators."))
                reasonRow(icon: "calendar", text: AppLocalization.systemString("Age and sex tune ranges for selected indicators."))
            }
            .padding(12)
            .background(AppColorRoles.surfaceInteractive)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(AppLocalization.systemString("You can skip and fill this later."))
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
        }
    }

    // MARK: - Helpers

    private func profileField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(AppColorRoles.textPrimary)
            content()
        }
    }

    private func reasonRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.appAccent)
                .frame(width: 16)
            Text(text)
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
