import SwiftUI

struct SettingsAISection: View {
    let isPremium: Bool
    let isAppleIntelligenceAvailable: Bool
    @Binding var appleIntelligenceEnabled: Bool
    let onUnlock: () -> Void

    var body: some View {
        Section {
            SettingsCard(tint: Color.cyan.opacity(0.12)) {
                SettingsCardHeader(title: AppLocalization.string("AI Insights"), systemImage: "sparkles")
                if isPremium {
                    if isAppleIntelligenceAvailable {
                        Toggle(isOn: $appleIntelligenceEnabled) {
                            Text(AppLocalization.string("Enable AI Insights"))
                        }
                        .tint(Color.appAccent)
                        .onChange(of: appleIntelligenceEnabled) { _, _ in Haptics.selection() }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(AppLocalization.string("AI Insights aren’t available right now."))
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
                            onUnlock()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.appAccent)
                        .frame(minHeight: 44, alignment: .trailing)
                    }
                }
            }
        }
    }
}
