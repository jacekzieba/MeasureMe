import SwiftUI

struct ProfileSettingsDetailView: View {
    @Binding var userName: String
    @Binding var userGender: String
    @Binding var userAge: Int
    @Binding var manualHeight: Double
    @Binding var unitsSystem: String
    @Binding var profilePhotoData: Data?

    var body: some View {
        SettingsDetailScaffold(title: AppLocalization.string("Profile"), theme: .settings) {
            ProfileSettingsSection(
                userName: $userName,
                userGender: $userGender,
                userAge: $userAge,
                manualHeight: $manualHeight,
                unitsSystem: $unitsSystem,
                profilePhotoData: $profilePhotoData
            )
            ProfileStatsCard()
        }
    }
}
