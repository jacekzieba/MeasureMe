import SwiftUI

struct AIInsightsSettingsDetailView: View {
    @EnvironmentObject private var premiumStore: PremiumStore
    @Binding var appleIntelligenceEnabled: Bool

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                Section {
                    SettingsCard(tint: Color.cyan.opacity(0.12)) {
                        SettingsCardHeader(title: AppLocalization.string("AI Insights"), systemImage: "sparkles")
                        if premiumStore.isPremium {
                            if AppleIntelligenceSupport.isAvailable() {
                                Toggle(isOn: $appleIntelligenceEnabled) {
                                    Text(AppLocalization.string("Enable AI Insights"))
                                }
                                .tint(Color.appAccent)
                                .onChange(of: appleIntelligenceEnabled) { _, _ in Haptics.selection() }
                                .frame(minHeight: 44)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(AppLocalization.string("AI Insights aren't available right now."))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(.secondary)
                                    NavigationLink {
                                        FAQView()
                                    } label: {
                                        Text(AppLocalization.string("Learn more in FAQ"))
                                            .font(AppTypography.captionEmphasis)
                                            .foregroundStyle(Color.appAccent)
                                    }
                                }
                            }
                        } else {
                            HStack {
                                Text(AppLocalization.string("Premium Edition required"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(AppLocalization.string("Unlock")) {
                                    premiumStore.presentPaywall(reason: .feature("AI Insights"))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.appAccent)
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
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("AI Insights"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
