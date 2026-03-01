import SwiftUI

struct HomeSettingsSection: View {
    @Binding var showMeasurementsOnHome: Bool
    @Binding var showLastPhotosOnHome: Bool
    @Binding var showHealthMetricsOnHome: Bool
    @Binding var showOnboardingChecklistOnHome: Bool
    @Binding var showStreakOnHome: Bool

    var body: some View {
        Section {
            SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                SettingsCardHeader(title: AppLocalization.string("Home"), systemImage: "house.fill")
                Toggle(isOn: $showStreakOnHome) {
                    HStack(spacing: 12) {
                        GlassPillIcon(systemName: "flame.fill")
                        Text(AppLocalization.string("Show streak on Home"))
                    }
                }
                .tint(Color.appAccent)
                .onChange(of: showStreakOnHome) { _, _ in Haptics.selection() }
                SettingsRowDivider()
                Toggle(isOn: $showMeasurementsOnHome) {
                    HStack(spacing: 12) {
                        GlassPillIcon(systemName: "chart.line.uptrend.xyaxis")
                        Text(AppLocalization.string("Show measurements on Home"))
                    }
                }
                .tint(Color.appAccent)
                .onChange(of: showMeasurementsOnHome) { _, _ in Haptics.selection() }
                SettingsRowDivider()
                Toggle(isOn: $showLastPhotosOnHome) {
                    HStack(spacing: 12) {
                        GlassPillIcon(systemName: "photo.on.rectangle")
                        Text(AppLocalization.string("Show photos on Home"))
                    }
                }
                .tint(Color.appAccent)
                .onChange(of: showLastPhotosOnHome) { _, _ in Haptics.selection() }
                SettingsRowDivider()
                Toggle(isOn: $showHealthMetricsOnHome) {
                    HStack(spacing: 12) {
                        GlassPillIcon(systemName: "heart.fill")
                        Text(AppLocalization.string("Show health summary on Home"))
                    }
                }
                .tint(Color.appAccent)
                .onChange(of: showHealthMetricsOnHome) { _, _ in Haptics.selection() }
                SettingsRowDivider()
                Toggle(isOn: $showOnboardingChecklistOnHome) {
                    HStack(spacing: 12) {
                        GlassPillIcon(systemName: "list.bullet.clipboard")
                        Text(AppLocalization.string("Show setup checklist on Home"))
                    }
                }
                .tint(Color.appAccent)
                .onChange(of: showOnboardingChecklistOnHome) { _, _ in Haptics.selection() }
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
    }
}
