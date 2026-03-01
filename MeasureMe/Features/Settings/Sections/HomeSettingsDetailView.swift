import SwiftUI

struct HomeSettingsDetailView: View {
    @Binding var showMeasurementsOnHome: Bool
    @Binding var showLastPhotosOnHome: Bool
    @Binding var showHealthMetricsOnHome: Bool
    @Binding var showOnboardingChecklistOnHome: Bool
    @Binding var showStreakOnHome: Bool

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                HomeSettingsSection(
                    showMeasurementsOnHome: $showMeasurementsOnHome,
                    showLastPhotosOnHome: $showLastPhotosOnHome,
                    showHealthMetricsOnHome: $showHealthMetricsOnHome,
                    showOnboardingChecklistOnHome: $showOnboardingChecklistOnHome,
                    showStreakOnHome: $showStreakOnHome
                )
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Home"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
