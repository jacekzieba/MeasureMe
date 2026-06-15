import SwiftUI
import UIKit

struct HomeAIInsightItem: Identifiable {
    enum Tone: Equatable {
        case positive
        case warning
        case neutral
    }

    enum Kind: Equatable {
        case trend
        case baseline
        case forming
        case photoComparison
        case premiumLocked
    }

    let id = UUID()
    let symbol: String
    let text: String
    let tone: Tone
    let kind: Kind

    init(
        symbol: String,
        text: String,
        tone: Tone,
        kind: Kind = .trend
    ) {
        self.symbol = symbol
        self.text = text
        self.tone = tone
        self.kind = kind
    }
}

enum HomePhotoComparisonCopy {
    static func insightText(days: Int) -> String {
        guard days > 0 else {
            return FlowLocalization.app(
                "Your photos are saved. Add another photo on a future date to compare progress.",
                "Zdjęcia są zapisane. Dodaj kolejne w innym dniu, aby porównać postępy.",
                "Tus fotos están guardadas. Añade otra en una fecha futura para comparar el progreso.",
                "Deine Fotos sind gespeichert. Füge an einem späteren Tag ein weiteres Foto hinzu.",
                "Vos photos sont enregistrées. Ajoutez-en une autre à une date ultérieure pour comparer.",
                "Suas fotos foram salvas. Adicione outra em uma data futura para comparar o progresso."
            )
        }
        return FlowLocalization.app(
            "Progress photos are ready for a \(days)-day comparison.",
            "Zdjęcia postępu są gotowe do porównania z \(days) dni.",
            "Las fotos de progreso están listas para comparar \(days) días.",
            "Fortschrittsfotos sind bereit für einen \(days)-Tage-Vergleich.",
            "Les photos de progression sont prêtes pour \(days) jours de comparaison.",
            "Fotos de progresso prontas para comparar \(days) dias."
        )
    }
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

/// Dashboard B: state shown right after the very first measurement (one dot on the chart).
struct HomeFirstDotSnapshot {
    let metricLabel: String
    let valueText: String
    let comeBackText: String
}

struct HomeTopSummarySection: View {
    let dateText: String
    let greetingTitle: String
    let avatarText: String
    let profilePhotoData: Data?
    let isPremium: Bool
    let insights: [HomeAIInsightItem]
    let analysisItems: [HomeAIAnalysisItem]
    let showStreak: Bool
    let streakCount: Int
    let shouldAnimateStreak: Bool
    var firstDot: HomeFirstDotSnapshot? = nil
    let onUnlockPremium: () -> Void
    let onOpenStreak: () -> Void
    let onStreakAnimationComplete: () -> Void
    let onOpenProfile: () -> Void
    let onOpenPhotos: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let firstDot {
                firstDotCard(firstDot)
            }

            HomeAIInsightsPanel(
                isPremium: isPremium,
                insights: insights,
                analysisItems: analysisItems,
                onUnlockPremium: onUnlockPremium,
                onOpenPhotos: onOpenPhotos
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .accessibilityElement()
                .accessibilityLabel(AppLocalization.string("AI Insights"))
                .accessibilityIdentifier("home.module.summaryHero")
                .allowsHitTesting(false)
        }
    }

    private func firstDotCard(_ snap: HomeFirstDotSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snap.metricLabel)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                Text(snap.valueText)
                    .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            firstDotChart
                .frame(height: 84)
                .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
                Text(snap.comeBackText)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(AppColorRoles.surfaceInteractive)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .padding(AppSpacing.smmd)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lgl, style: .continuous)
                .fill(AppColorRoles.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lgl, style: .continuous)
                        .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                )
        )
        .accessibilityIdentifier("home.hero.firstDot")
    }

    private var firstDotChart: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let baseY = h - 6
            let todayPt = CGPoint(x: 26, y: h - 30)
            let futurePt = CGPoint(x: w - 36, y: h - 52)

            var baseline = Path()
            baseline.move(to: CGPoint(x: 6, y: baseY))
            baseline.addLine(to: CGPoint(x: w - 6, y: baseY))
            ctx.stroke(baseline, with: .color(AppColorRoles.borderSubtle), lineWidth: 1.5)

            var projection = Path()
            projection.move(to: todayPt)
            projection.addCurve(
                to: futurePt,
                control1: CGPoint(x: w * 0.42, y: h - 34),
                control2: CGPoint(x: w * 0.64, y: h - 48)
            )
            ctx.stroke(
                projection,
                with: .color(AppColorRoles.textTertiary),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 6])
            )

            let ring = Path(ellipseIn: CGRect(x: futurePt.x - 5, y: futurePt.y - 5, width: 10, height: 10))
            ctx.stroke(ring, with: .color(Color.appAccent), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))

            ctx.fill(
                Path(ellipseIn: CGRect(x: todayPt.x - 15, y: todayPt.y - 15, width: 30, height: 30)),
                with: .color(Color.appAccent.opacity(0.16))
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: todayPt.x - 6, y: todayPt.y - 6, width: 12, height: 12)),
                with: .color(Color.appAccent)
            )
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

            if showStreak {
                Button(action: onOpenStreak) {
                    StreakBadge(
                        count: streakCount,
                        shouldAnimate: shouldAnimateStreak,
                        onAnimationComplete: onStreakAnimationComplete
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.string("accessibility.streak.count", streakCount))
                .accessibilityIdentifier("home.streak.badge")
            }

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
    let onOpenPhotos: () -> Void

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
                                .appUntruncatedText()
                                .accessibilityIdentifier("home.aiInsights.primaryText")

                            if firstInsight.kind == .trend && !analysisItems.isEmpty {
                                Button {
                                    isAnalysisPresented = true
                                } label: {
                                    HStack(spacing: 3) {
                                        Text(FlowLocalization.app("See full analysis", "Zobacz pełną analizę", "Ver análisis completo", "Vollständige Analyse ansehen", "Voir l'analyse complète", "Ver análise completa"))
                                        Text("→")
                                    }
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(accent)
                                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .accessibilityIdentifier("home.aiInsights.openAnalysis")
                            }
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
                                    .appUntruncatedText()
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

    @ViewBuilder
    private func insightRow(_ item: HomeAIInsightItem) -> some View {
        let row = HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: item.symbol)
                .font(AppTypography.iconSmall)
                .foregroundStyle(tint(for: item.tone))
                .frame(width: 18)

            Text(item.text)
                .font(AppTypography.body)
                .foregroundStyle(AppColorRoles.textSecondary)
                .appUntruncatedText()
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if item.kind == .photoComparison {
            Button(action: onOpenPhotos) {
                row
            }
            .buttonStyle(.plain)
            .accessibilityHint(AppLocalization.string("Photos"))
            .accessibilityIdentifier("home.aiInsights.openPhotos")
        } else {
            row
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
                .appUntruncatedText()

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
                .appUntruncatedText()
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
                        .appUntruncatedText()

                    Text(item.detail)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .appUntruncatedText()
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
            Text("\(deltaChip.text) \(AppLocalization.string("home.keymetrics.delta.period.30d"))")
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
