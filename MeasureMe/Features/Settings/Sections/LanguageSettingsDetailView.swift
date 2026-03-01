import SwiftUI

struct LanguageSettingsDetailView: View {
    @Binding var appLanguage: String

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                Section {
                    SettingsCard(tint: Color.white.opacity(0.07)) {
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
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Language"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func languageRow(title: String, value: String) -> some View {
        Button {
            appLanguage = value
            AppLocalization.reloadLanguage()
            Haptics.selection()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.white)
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
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.appAccent)
        } else {
            Color.clear
        }
    }
}
