import SwiftUI

struct AISectionSummaryCard: View {
    @EnvironmentObject private var premiumStore: PremiumStore

    let input: SectionInsightInput?
    let missingDataMessage: String
    var tint: Color = FeatureTheme.health.softTint
    var accessibilityIdentifier: String = "ai.section.summary"

    @State private var text: String?
    @State private var isLoading = false

    var body: some View {
        AppGlassCard(
            depth: .base,
            cornerRadius: AppRadius.lg,
            tint: tint,
            contentPadding: AppSpacing.sm
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(AppLocalization.string("AI summary"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textSecondary)

                content
            }
        }
        .task(id: input) {
            await loadInsightIfNeeded()
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var content: some View {
        if !premiumStore.isPremium {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.string("Upgrade to Premium Edition to unlock AI Insights."))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textSecondary)

                Button {
                    premiumStore.presentPaywall(reason: .feature("AI Insights"))
                } label: {
                    Text(AppLocalization.string("Unlock AI Insights"))
                        .font(AppTypography.captionEmphasis)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColorRoles.accentPrimary)
            }
        } else if !AppleIntelligenceSupport.isAvailable() {
            Text(AppLocalization.string("AI Insights aren't available right now."))
                .font(AppTypography.body)
                .foregroundStyle(AppColorRoles.textSecondary)
        } else if input == nil {
            Text(missingDataMessage)
                .font(AppTypography.body)
                .foregroundStyle(AppColorRoles.textSecondary)
        } else {
            MetricInsightCard(
                text: text ?? AppLocalization.string("Generating your health summary..."),
                compact: false,
                isLoading: isLoading,
                onRefresh: {
                    Task { await refreshInsight() }
                }
            )
        }
    }

    @MainActor
    private func loadInsightIfNeeded() async {
        guard premiumStore.isPremium, AppleIntelligenceSupport.isAvailable(), let input else {
            text = nil
            isLoading = false
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(450))
        } catch {
            isLoading = false
            return
        }
        guard !Task.isCancelled else {
            isLoading = false
            return
        }

        isLoading = true
        text = await MetricInsightService.shared.generateSectionInsight(for: input)
        isLoading = false
    }

    @MainActor
    private func refreshInsight() async {
        guard premiumStore.isPremium, AppleIntelligenceSupport.isAvailable(), let input else { return }
        await MetricInsightService.shared.invalidateSections()
        isLoading = true
        text = await MetricInsightService.shared.generateSectionInsight(for: input)
        isLoading = false
    }
}
