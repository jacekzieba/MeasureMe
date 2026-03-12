import SwiftUI

struct UnitsSettingsDetailView: View {
    @Binding var unitsSystem: String

    var body: some View {
        SettingsDetailScaffold(title: AppLocalization.string("Units"), theme: .settings) {
            UnitsSettingsSection(unitsSystem: $unitsSystem)
        }
    }
}
