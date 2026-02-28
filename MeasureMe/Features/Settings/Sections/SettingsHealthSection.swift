import SwiftUI

struct SettingsHealthSection: View {
    @Binding var isSyncEnabled: Bool
    let lastImportText: String?
    @Binding var hkWeight: Bool
    @Binding var hkBodyFat: Bool
    @Binding var hkHeight: Bool
    @Binding var hkLeanMass: Bool
    @Binding var hkWaist: Bool

    var body: some View {
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
