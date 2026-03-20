import SwiftUI

struct LanguageSettingsDetailView: View {
    @Binding var appLanguage: String
    private let theme = FeatureTheme.settings

    var body: some View {
        SettingsDetailScaffold(title: AppLocalization.string("Language"), theme: .settings) {
            Section {
                SettingsCard(tint: AppColorRoles.surfacePrimary) {
                    SettingsCardHeader(title: AppLocalization.string("Language"), systemImage: "globe")
                    languageRow(title: AppLocalization.string("System"), value: "system")
                    SettingsRowDivider()
                    languageRow(title: AppLocalization.string("English"), value: "en")
                    SettingsRowDivider()
                    languageRow(title: AppLocalization.string("Polish"), value: "pl")
                }
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowInsets(settingsComponentsRowInsets)
            .listRowBackground(Color.clear)
        }
    }

    private func languageRow(title: String, value: String) -> some View {
        Button {
            appLanguage = value
            AppLocalization.reloadLanguage()
            Haptics.selection()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textPrimary)
                Spacer()
                languageAccessory(for: value)
                    .frame(width: 16, alignment: .trailing)
            }
            .padding(.trailing, 2)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func languageAccessory(for value: String) -> some View {
        if appLanguage == value {
            Image(systemName: "checkmark")
                .font(AppTypography.iconSmall)
                .foregroundStyle(theme.accent)
        } else {
            Color.clear
        }
    }
}
