import SwiftUI

struct UnitsSettingsSection: View {
    @Binding var unitsSystem: String
    private let theme = FeatureTheme.settings

    var body: some View {
        Section {
            SettingsCard(tint: theme.softTint) {
                SettingsCardHeader(title: AppLocalization.string("Units"), systemImage: "ruler")
                Picker(AppLocalization.string("Units"), selection: $unitsSystem) {
                    Text(AppLocalization.string("Metric")).tag("metric")
                    Text(AppLocalization.string("Imperial")).tag("imperial")
                }
                .pickerStyle(.segmented)
                .glassSegmentedControl(tint: theme.accent)
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
    }
}
