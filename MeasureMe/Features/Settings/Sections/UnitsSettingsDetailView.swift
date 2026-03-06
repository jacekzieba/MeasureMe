import SwiftUI

struct UnitsSettingsDetailView: View {
    @Binding var unitsSystem: String

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                UnitsSettingsSection(unitsSystem: $unitsSystem)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Units"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
