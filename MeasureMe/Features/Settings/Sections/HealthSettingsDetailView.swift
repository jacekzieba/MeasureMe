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
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
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
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Health"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
