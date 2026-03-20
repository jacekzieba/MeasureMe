import SwiftUI

struct AIInsightsSettingsDetailView: View {
    @EnvironmentObject private var premiumStore: PremiumStore
    @Binding var appleIntelligenceEnabled: Bool
    private let theme = FeatureTheme.settings

    var body: some View {
        SettingsDetailScaffold(title: AppLocalization.string("AI Insights"), theme: .settings) {
            Section {
                SettingsCard(tint: FeatureTheme.premium.softTint) {
                    SettingsCardHeader(title: AppLocalization.string("AI Insights"), systemImage: "sparkles")
                    if premiumStore.isPremium {
                        if AppleIntelligenceSupport.isAvailable() {
                            SettingsToggleRow(isOn: $appleIntelligenceEnabled, accent: theme.accent) {
                                Text(AppLocalization.string("Enable AI Insights"))
                                    .font(AppTypography.body)
                                    .foregroundStyle(AppColorRoles.textPrimary)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(AppLocalization.string("AI Insights aren't available right now."))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColorRoles.textSecondary)
                                NavigationLink {
                                    FAQView()
                                } label: {
                                    Text(AppLocalization.string("Learn more in FAQ"))
                                        .font(AppTypography.captionEmphasis)
                                        .foregroundStyle(theme.accent)
                                }
                            }
                        }
                    } else {
                        HStack {
                            Text(AppLocalization.string("Premium Edition required"))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColorRoles.textSecondary)
                            Spacer()
                            Button(AppLocalization.string("Unlock")) {
                                premiumStore.presentPaywall(reason: .feature("AI Insights"))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(theme.accent)
                            .frame(minHeight: 44)
                        }
                    }
                }
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowInsets(settingsComponentsRowInsets)
            .listRowBackground(Color.clear)
        }
    }
}
