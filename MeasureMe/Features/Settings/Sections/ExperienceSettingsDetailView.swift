import SwiftUI

struct ExperienceSettingsDetailView: View {
    @Binding var appAppearance: String
    @Binding var animationsEnabled: Bool
    @Binding var hapticsEnabled: Bool
    private let theme = FeatureTheme.settings

    var body: some View {
        SettingsDetailScaffold(title: AppLocalization.string("Appearance, animations and haptics"), theme: .settings) {
            Section {
                SettingsCard(tint: AppColorRoles.surfacePrimary) {
                    SettingsCardHeader(title: AppLocalization.string("Appearance"), systemImage: "circle.lefthalf.filled.inverse")

                    Picker(AppLocalization.string("Appearance"), selection: $appAppearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .glassSegmentedControl(tint: theme.accent)

                    SettingsRowDivider()

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
