import SwiftUI

struct UnitsSettingsSection: View {
    @Binding var unitsSystem: String

    var body: some View {
        Section {
            SettingsCard(tint: Color.appAccent.opacity(0.12)) {
                SettingsCardHeader(title: AppLocalization.string("Units"), systemImage: "ruler")
                Picker(AppLocalization.string("Units"), selection: $unitsSystem) {
                    Text(AppLocalization.string("Metric")).tag("metric")
                    Text(AppLocalization.string("Imperial")).tag("imperial")
                }
                .pickerStyle(.segmented)
                .glassSegmentedControl(tint: Color.appAccent)
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
    }
}
