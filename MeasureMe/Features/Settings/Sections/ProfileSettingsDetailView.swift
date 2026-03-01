import SwiftUI

struct ProfileSettingsDetailView: View {
    @Binding var userName: String
    @Binding var userGender: String
    @Binding var userAge: Int
    @Binding var manualHeight: Double
    @Binding var unitsSystem: String

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                ProfileSettingsSection(
                    userName: $userName,
                    userGender: $userGender,
                    userAge: $userAge,
                    manualHeight: $manualHeight,
                    unitsSystem: $unitsSystem
                )
                ProfileStatsCard()
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
