import SwiftUI

struct ExperienceSettingsDetailView: View {
    @Binding var animationsEnabled: Bool
    @Binding var hapticsEnabled: Bool
    private let theme = FeatureTheme.settings

    var body: some View {
        SettingsDetailScaffold(title: AppLocalization.string("Animations and haptics"), theme: .settings) {
            Section {
                SettingsCard(tint: AppColorRoles.surfacePrimary) {
                    SettingsCardHeader(title: AppLocalization.string("Animations and haptics"), systemImage: "apple.haptics.and.music.note")
                    SettingsToggleRow(isOn: $animationsEnabled, accent: theme.accent) {
                        Text(AppLocalization.string("Animations"))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColorRoles.textPrimary)
                    }

                    SettingsRowDivider()

                    SettingsToggleRow(isOn: $hapticsEnabled, accent: theme.accent) {
                        Text(AppLocalization.string("Haptics"))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColorRoles.textPrimary)
                    }
                }
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowInsets(settingsComponentsRowInsets)
            .listRowBackground(Color.clear)
        }
    }
}
