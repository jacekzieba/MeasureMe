import SwiftUI

struct HealthSettingsDetailView: View {
    @Binding var isSyncEnabled: Bool
    let lastImportText: String?
    @Binding var hkWeight: Bool
    @Binding var hkBodyFat: Bool
    @Binding var hkHeight: Bool
    @Binding var hkLeanMass: Bool
    @Binding var hkWaist: Bool

    var body: some View {
        SettingsDetailScaffold(title: AppLocalization.string("Health"), theme: .health) {
            HealthSettingsSection(
                isSyncEnabled: $isSyncEnabled,
                lastImportText: lastImportText,
                hkWeight: $hkWeight,
                hkBodyFat: $hkBodyFat,
                hkHeight: $hkHeight,
                hkLeanMass: $hkLeanMass,
                hkWaist: $hkWaist
            )
        }
    }
}
