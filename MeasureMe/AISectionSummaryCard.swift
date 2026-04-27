import SwiftUI

struct AISectionSummaryCard: View {
    @EnvironmentObject private var premiumStore: PremiumStore
    @Environment(\.colorScheme) private var colorScheme

    let input: SectionInsightInput?
    let missingDataMessage: String
    var tint: Color = FeatureTheme.health.softTint
    var accessibilityIdentifier: String = "ai.section.summary"

    @State private var text: String?
    @State private var isLoading = false

    var body: some View {
        AppGlassCard(
            depth: .base,
            cornerRadius: 22,
            tint: tint,
            contentPadding: 16
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(AppTypography.iconSmall)
                        .foregroundStyle(AppColorRoles.accentPrimary)

                    Text(AppLocalization.aiString("AI summary").uppercased())
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(AppColorRoles.accentPrimary)
                        .tracking(1.2)

                    Spacer(minLength: 8)

                    if input != nil, premiumStore.isPremium, AppleIntelligenceSupport.isAvailable(), !isLoading {
                        Button {
                            Task { await refreshInsight() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColorRoles.textSecondary)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppLocalization.aiString("Refresh insight"))
                    }
                }

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: input) {
            await loadInsightIfNeeded()
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var content: some View {
        if !premiumStore.isPremium {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.aiString("Upgrade to Premium Edition to unlock AI Insights."))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textSecondary)

                Button {
                    premiumStore.presentPaywall(reason: .feature("AI Insights"))
                } label: {
                    Text(AppLocalization.aiString("Unlock AI Insights"))
                        .font(AppTypography.captionEmphasis)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColorRoles.accentPrimary)
            }
        } else if !AppleIntelligenceSupport.isAvailable() {
            Text(AppLocalization.aiString("AI Insights aren't available right now."))
                .font(AppTypography.body)
                .foregroundStyle(AppColorRoles.textSecondary)
        } else if input == nil {
            Text(missingDataMessage)
                .font(AppTypography.body)
                .foregroundStyle(AppColorRoles.textSecondary)
        } else {
            if isLoading && text == nil {
                VStack(alignment: .leading, spacing: 8) {
                    shimmerBlock(width: .infinity)
                    shimmerBlock(width: 220)
                }
            } else {
                Text(text ?? AppLocalization.aiString("Generating your health summary..."))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func shimmerBlock(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(AppColorRoles.textSecondary.opacity(colorScheme == .dark ? 0.16 : 0.10))
            .frame(maxWidth: width == .infinity ? .infinity : width, alignment: .leading)
            .frame(height: 13)
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
