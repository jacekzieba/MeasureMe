import SwiftUI
import UIKit

struct HomeAIInsightItem: Identifiable {
    enum Tone: Equatable {
        case positive
        case warning
        case neutral
    }

    let id = UUID()
    let symbol: String
    let text: String
    let tone: Tone
}

struct HomeAIAnalysisItem: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String
    let tone: HomeAIInsightItem.Tone
}

enum HomeAIAnalysisItemsPolicy {
    static let maxVisibleItems = 5
    static let minimumUsefulItems = 3

    static func visibleItems(
        primary: [HomeAIAnalysisItem],
        fallback: [HomeAIAnalysisItem]
    ) -> [HomeAIAnalysisItem] {
        let merged = primary.count < minimumUsefulItems
            ? primary + fallback
            : primary
        return Array(merged.prefix(maxVisibleItems))
    }
}

struct HomeTopSummarySection: View {
    let dateText: String
    let greetingTitle: String
    let avatarText: String
    let profilePhotoData: Data?
    let isPremium: Bool
    let insights: [HomeAIInsightItem]
    let analysisItems: [HomeAIAnalysisItem]
    let onUnlockPremium: () -> Void
    let onOpenProfile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HomeAIInsightsPanel(
                isPremium: isPremium,
                insights: insights,
                analysisItems: analysisItems,
                onUnlockPremium: onUnlockPremium
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .accessibilityElement()
                .accessibilityIdentifier("home.module.summaryHero")
                .allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(dateText)
                    .font(AppTypography.eyebrow)
                    .foregroundStyle(AppColorRoles.textTertiary)
                    .tracking(1.4)
                    .lineLimit(1)

                Text(greetingTitle)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 10)

            Button(action: onOpenProfile) {
                HomeProfileAvatar(profilePhotoData: profilePhotoData, fallbackText: avatarText)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.string("Profile"))
            .accessibilityHint(AppLocalization.string("Open profile settings"))
            .accessibilityIdentifier("home.profile.avatar")
        }
    }
}

private struct HomeAIInsightsPanel: View {
    let isPremium: Bool
    let insights: [HomeAIInsightItem]
    let analysisItems: [HomeAIAnalysisItem]
    let onUnlockPremium: () -> Void

    @State private var isAnalysisPresented = false

    private let accent = Color.appAmber

    var body: some View {
        AppGlassCard(
            depth: .elevated,
            cornerRadius: AppRadius.xl,
            tint: FeatureTheme.premium.softTint,
            contentPadding: 16
        ) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top, spacing: 12) {
                    MeasureBuddyView(pose: .summary, size: 56)
                        .shadow(color: accent.opacity(0.30), radius: 10, x: 0, y: 4)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("📏 \(MeasureBuddyName.display.uppercased()) · \(AppLocalization.string("AI Insights").uppercased())")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1.2)
                            .foregroundStyle(accent)

                        if isPremium, let firstInsight = insights.first {
                            Text(firstInsight.text)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppColorRoles.textPrimary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)

                            Button {
                                isAnalysisPresented = true
                            } label: {
                                HStack(spacing: 3) {
                                    Text(FlowLocalization.app("See full analysis", "Zobacz pełną analizę", "Ver análisis completo", "Vollständige Analyse ansehen", "Voir l'analyse complète", "Ver análise completa"))
                                    Text("→")
                                }
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(accent)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("home.aiInsights.openAnalysis")
                            .padding(.top, 2)
                        } else {
                            Text(AppLocalization.string("AI Insights"))
                                .font(AppTypography.headlineEmphasis)
                                .foregroundStyle(AppColorRoles.textPrimary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isPremium, insights.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(insights.dropFirst())) { item in
                            insightRow(item)
                        }
                    }
                } else if !isPremium {
                    Button(action: onUnlockPremium) {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "lock.fill")
                                .font(AppTypography.iconMedium)
                                .foregroundStyle(accent)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(AppLocalization.aiString("Unlock AI Insights"))
                                    .font(AppTypography.bodyEmphasis)
                                    .foregroundStyle(AppColorRoles.textPrimary)

                                Text(AppLocalization.aiString("Upgrade to Premium Edition to unlock AI Insights."))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColorRoles.textSecondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationDestination(isPresented: $isAnalysisPresented) {
            HomeAIAnalysisView(items: analysisItems)
        }
    }

    private func insightRow(_ item: HomeAIInsightItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: item.symbol)
                .font(AppTypography.iconSmall)
                .foregroundStyle(tint(for: item.tone))
                .frame(width: 18)

            Text(item.text)
                .font(AppTypography.body)
                .foregroundStyle(AppColorRoles.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tint(for tone: HomeAIInsightItem.Tone) -> Color {
        switch tone {
        case .positive:
            return AppColorRoles.stateSuccess
        case .warning:
            return Color.appDanger
        case .neutral:
            return accent
        }
    }
}

private struct HomeProfileAvatar: View {
    let profilePhotoData: Data?
    let fallbackText: String

    var body: some View {
        ZStack {
            if let profilePhotoData, let image = UIImage(data: profilePhotoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color.appAmber, Color.appMint],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(fallbackText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.20), lineWidth: 1)
        )
    }
}

struct HomeAIAnalysisView: View {
    let items: [HomeAIAnalysisItem]

    private let accent = Color.appAmber

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                VStack(spacing: 12) {
                    ForEach(items.prefix(5)) { item in
                        analysisCard(item)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(AppColorRoles.surfaceCanvas.ignoresSafeArea())
        .navigationTitle(FlowLocalization.app("AI Analysis", "Analiza AI", "Análisis IA", "KI-Analyse", "Analyse IA", "Análise IA"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("home.aiAnalysis.screen")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            MeasureBuddyView(pose: .ai, size: 90)
                .shadow(color: accent.opacity(0.30), radius: 14, x: 0, y: 8)

            VStack(alignment: .leading, spacing: 6) {
                Text("📏 \(FlowLocalization.app("Miara says", "Miara mówi", "Miara dice", "Miara sagt", "Miara dit", "Miara diz").uppercased())")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(accent)

                Text(FlowLocalization.app(
                    "I analyzed your last 30 days",
                    "Przeanalizowałam Twoje 30 dni",
                    "He analizado tus últimos 30 días",
                    "Ich habe deine letzten 30 Tage analysiert",
                    "J'ai analysé tes 30 derniers jours",
                    "Analisei seus últimos 30 dias"
                ))
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(AppColorRoles.textPrimary)

                Text(FlowLocalization.app(
                    "Generated from your recent body metrics and photos.",
                    "Wygenerowane z ostatnich metryk ciała i zdjęć.",
                    "Generado con tus métricas y fotos recientes.",
                    "Aus deinen aktuellen Körperwerten und Fotos erstellt.",
                    "Généré depuis vos mesures et photos récentes.",
                    "Gerado com suas métricas e fotos recentes."
                ))
                .font(AppTypography.body)
                .foregroundStyle(AppColorRoles.textSecondary)
            }
        }
    }

    private func analysisCard(_ item: HomeAIAnalysisItem) -> some View {
        AppGlassCard(
            depth: .elevated,
            cornerRadius: AppRadius.xl,
            tint: tint(for: item.tone).opacity(0.16),
            contentPadding: 16
        ) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: item.symbol)
                    .font(AppTypography.iconMedium)
                    .foregroundStyle(tint(for: item.tone))
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .fill(tint(for: item.tone).opacity(0.16))
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(AppTypography.headlineEmphasis)
                        .foregroundStyle(tint(for: item.tone))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(item.detail)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tint(for tone: HomeAIInsightItem.Tone) -> Color {
        switch tone {
        case .positive:
            return AppColorRoles.stateSuccess
        case .warning:
            return Color.appAmber
        case .neutral:
            return accent
        }
    }
}

struct HomeKeyMetricGoalProgress {
    let progress: Double
    let label: String
}

struct HomeKeyMetricTile: View {
    let title: String
    let valueText: String?
    let deltaChip: HomeMetricDeltaChip?
    let goalProgress: HomeKeyMetricGoalProgress?
    let samples: [MetricSample]
    let trendKind: MetricKind
    let goal: MetricGoal?

    private var style: HomeMetricTileStyle {
        .style(for: trendKind)
    }

    var body: some View {
        metricTileScaffold(
            title: title,
            valueText: valueText,
            deltaChip: deltaChip,
            goalProgress: goalProgress,
            style: style
        ) {
            trendKind.iconView(size: 18, tint: style.accent)
        } chart: {
            MiniSparklineChart(samples: samples, kind: trendKind, goal: goal)
        }
    }
}

struct HomeCustomKeyMetricTile: View {
    let definition: CustomMetricDefinition
    let latest: MetricSample?
    let deltaChip: HomeMetricDeltaChip?
    let goalProgress: HomeKeyMetricGoalProgress?
    let samples: [MetricSample]
    let goal: MetricGoal?

    private var style: HomeMetricTileStyle {
        HomeMetricTileStyle(
            accent: Color.appViolet,
            softTint: Color.appViolet.opacity(0.14),
            border: Color.appViolet.opacity(0.26)
        )
    }

    var body: some View {
        metricTileScaffold(
            title: definition.name,
            valueText: latest.map { formattedValue($0.value) },
            deltaChip: deltaChip,
            goalProgress: goalProgress,
            style: style
        ) {
            Image(systemName: "ruler")
                .font(AppTypography.iconSmall)
                .foregroundStyle(style.accent)
        } chart: {
            CustomMiniSparklineChart(
                samples: samples,
                favorsDecrease: definition.favorsDecrease,
                goal: goal
            )
        }
    }

    private func formattedValue(_ value: Double) -> String {
        let formatted = value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "\(formatted) \(definition.unitLabel)"
    }
}

private struct HomeMetricTileStyle {
    let accent: Color
    let softTint: Color
    let border: Color

    static func style(for kind: MetricKind) -> HomeMetricTileStyle {
        let accent: Color
        switch kind {
        case .weight:
            accent = Color(hex: "#38BDF8")
        case .waist, .hips:
            accent = Color(hex: "#2DD4BF")
        case .bodyFat, .bust:
            accent = Color.appAmber
        case .leanBodyMass, .chest, .shoulders:
            accent = Color.appMint
        case .height:
            accent = Color(hex: "#60A5FA")
        case .neck, .leftForearm, .rightForearm:
            accent = Color.appViolet
        case .leftBicep, .rightBicep:
            accent = Color(hex: "#FB7185")
        case .leftThigh, .rightThigh, .leftCalf, .rightCalf:
            accent = Color(hex: "#34D399")
        }
        return HomeMetricTileStyle(
            accent: accent,
            softTint: accent.opacity(0.14),
            border: accent.opacity(0.28)
        )
    }
}

private func metricTileScaffold<Icon: View, Chart: View>(
    title: String,
    valueText: String?,
    deltaChip: HomeMetricDeltaChip?,
    goalProgress: HomeKeyMetricGoalProgress?,
    style: HomeMetricTileStyle,
    @ViewBuilder icon: () -> Icon,
    @ViewBuilder chart: () -> Chart
) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
            icon()
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .fill(style.accent.opacity(0.16))
                )

            Text(title.uppercased(with: AppLocalization.currentLanguage.locale))
                .font(AppTypography.eyebrow)
                .foregroundStyle(style.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(AppTypography.iconSmall)
                .foregroundStyle(AppColorRoles.textTertiary)
        }

        let parts = splitMetricValue(valueText)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(parts.value)
                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(AppColorRoles.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.70)

            if !parts.unit.isEmpty {
                Text(parts.unit)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(height: 42, alignment: .leading)

        chart()
            .frame(height: 48)

        if let deltaChip {
            Text("\(deltaChip.text) 30d")
                .font(AppTypography.captionEmphasis.monospacedDigit())
                .foregroundStyle(deltaChip.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        } else {
            Text(AppLocalization.string("home.keymetrics.delta.empty"))
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textTertiary)
                .lineLimit(1)
        }

        progressBar(
            goalProgress,
            accent: style.accent,
            emptyLabel: valueText == nil
                ? AppLocalization.string("home.keymetrics.action.addValue")
                : AppLocalization.string("home.keymetrics.action.setTarget")
        )
    }
    .padding(AppSpacing.md)
    .frame(maxWidth: .infinity, minHeight: 228, alignment: .topLeading)
    .background(
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(style.softTint)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(style.border, lineWidth: 1)
            )
    )
}

private func progressBar(
    _ progress: HomeKeyMetricGoalProgress?,
    accent: Color,
    emptyLabel: String
) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColorRoles.surfaceInteractive)
                Capsule()
                    .fill(accent)
                    .frame(width: proxy.size.width * max(0, min(progress?.progress ?? 0, 1)))
            }
        }
        .frame(height: 5)

        Text(progress?.label ?? emptyLabel)
            .font(AppTypography.micro)
            .foregroundStyle(progress == nil ? accent : AppColorRoles.textTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
    }
}

private func splitMetricValue(_ text: String?) -> (value: String, unit: String) {
    guard let text, !text.isEmpty else {
        return (AppLocalization.string("—"), "")
    }
    let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
    if parts.count == 2 {
        return (parts[0], parts[1])
    }
    return (text, "")
}
