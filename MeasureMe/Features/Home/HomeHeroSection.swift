import SwiftUI

// MARK: - Living Pulse Hero

enum HeroPulseAction: Equatable {
    case streakDetail
    case quickAdd
    case metricDetail(MetricKind)
    case measurementsTab
    case none
}

enum HeroPulseSignalKind: String {
    case streakRisk
    case streakMilestone
    case streakActive
    case goalAchieved
    case goalNearComplete
    case returnNudge
    case trendHighlight
    case fresh
}

enum HeroPulseTint {
    case accent
    case success
    case warning
    case neutral
}

struct HeroPulseSignal {
    let kind: HeroPulseSignalKind
    let icon: String                  // SF Symbol name; ignored when useStreakBadge == true
    let title: String
    let subtitle: String
    let tint: HeroPulseTint
    let useStreakBadge: Bool
    let streakCount: Int
    let animateStreak: Bool
    let action: HeroPulseAction
}

struct HomeHeroNextFocusSnapshot {
    let headline: String?
    let primaryValue: String?
    let supportingLabel: String?
    let contextLabel: String
    let summary: String
}

struct HomeHeroMeasurementSnapshot {
    let label: String
    let value: String
    let detail: String
}

struct HomeHeroSnapshot {
    let tint: Color
    let greetingTitle: String
    let goalStatusText: String
    let goalStatusColor: Color
    let goalStatusAccessibilityHint: String
    let isFreshState: Bool
    let showStreak: Bool
    let streakCount: Int
    let shouldAnimateStreak: Bool
    let prefersStackedPanels: Bool
    let primaryMeasurement: HomeHeroMeasurementSnapshot?
    let nextFocus: HomeHeroNextFocusSnapshot
    let weekTitle: String
    let weekDetail: String
    let shouldShowPostOnboardingSummary: Bool
    let pulseSignal: HeroPulseSignal
    let showNextFocusChip: Bool
    let showThisWeekChip: Bool
}

struct HomeHeroSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let snapshot: HomeHeroSnapshot
    let accent: Color
    let pillFill: Color
    let pillStroke: Color
    let border: Color
    let activationSnapshot: HomeActivationSnapshot?
    let onGoalStatusTap: () -> Void
    let onNextFocusTap: () -> Void
    let onStreakTap: () -> Void
    let onStreakAnimationComplete: () -> Void
    let onActivationPrimary: () -> Void
    let onActivationSkip: () -> Void
    let onActivationDismiss: () -> Void
    var onPulseAction: (HeroPulseAction) -> Void = { _ in }
    var onThisWeekTap: () -> Void = { }

    var body: some View {
        HomeWidgetCard(
            tint: snapshot.tint,
            depth: .floating,
            contentPadding: 18,
            accessibilityIdentifier: "home.module.summaryHero"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if snapshot.isFreshState || activationSnapshot != nil {
                    headerRow
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(snapshot.greetingTitle)
                        .font(AppTypography.titleCompact)
                        .foregroundStyle(AppColorRoles.textPrimary)
                        .lineLimit(snapshot.prefersStackedPanels ? 3 : 2)
                        .minimumScaleFactor(0.9)

                    if snapshot.shouldShowPostOnboardingSummary {
                        statusRow
                    }
                }

                if let activationSnapshot {
                    HomeActivationCard(
                        snapshot: activationSnapshot,
                        onPrimary: onActivationPrimary,
                        onSkip: onActivationSkip,
                        onDismiss: onActivationDismiss
                    )
                } else {
                    pulsePrimaryCard(snapshot.pulseSignal)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))

                    if snapshot.shouldShowPostOnboardingSummary && !snapshot.isFreshState {
                        pulseChipsRow
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image("BrandButton")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            Text("MeasureMe")
                .font(AppTypography.eyebrow)
                .foregroundStyle(AppColorRoles.textSecondary)

            Spacer()
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            goalStatusRow
            Spacer(minLength: 0)
        }
    }

    private var goalStatusRow: some View {
        Button(action: onGoalStatusTap) {
            HStack(spacing: 8) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(snapshot.goalStatusColor)

                Text(snapshot.goalStatusText)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(AppColorRoles.surfaceInteractive)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.goalStatus.button")
        .accessibilityHint(snapshot.goalStatusAccessibilityHint)
    }

    private var streakStatusChip: some View {
        Button(action: onStreakTap) {
            StreakBadge(
                count: snapshot.streakCount,
                shouldAnimate: snapshot.shouldAnimateStreak,
                onAnimationComplete: onStreakAnimationComplete
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.string("accessibility.streak.count", snapshot.streakCount))
    }

    private var todayInsightCard: some View {
        Button(action: onNextFocusTap) {
            VStack(alignment: .leading, spacing: summaryCardVerticalSpacing) {
                HStack(alignment: .center, spacing: 8) {
                    miniLabel(
                        title: FlowLocalization.app("Next focus", "Następny fokus", "Siguiente foco", "Nächster Fokus", "Prochain focus", "Próximo foco"),
                        icon: "sparkle.magnifyingglass",
                        accent: AppColorRoles.textSecondary
                    )

                    Spacer(minLength: 8)

                    Text(snapshot.nextFocus.contextLabel)
                        .font(summaryCardBadgeFont)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, summaryCardBadgeHorizontalPadding)
                        .padding(.vertical, summaryCardBadgeVerticalPadding)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppColorRoles.surfaceInteractive)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                                )
                        )

                    Image(systemName: "arrow.up.right")
                        .font(AppTypography.iconSmall)
                        .foregroundStyle(AppColorRoles.textTertiary)
                }

                if let primaryValue = snapshot.nextFocus.primaryValue {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(primaryValue)
                            .font(insightCardPrimaryFont)
                            .foregroundStyle(AppColorRoles.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .accessibilityIdentifier("home.nextFocus.primaryValue")

                        if let supportingLabel = snapshot.nextFocus.supportingLabel {
                            Text(supportingLabel)
                                .font(summaryCardBadgeFont)
                                .foregroundStyle(colorScheme == .dark ? accent : AppColorRoles.textPrimary)
                                .lineLimit(1)
                                .padding(.horizontal, summaryCardBadgeHorizontalPadding)
                                .padding(.vertical, summaryCardBadgeVerticalPadding)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(pillFill)
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .stroke(pillStroke, lineWidth: 1)
                                        )
                                )
                                .accessibilityIdentifier("home.nextFocus.supportingLabel")
                        }
                    }
                } else if let headline = snapshot.nextFocus.headline {
                    Text(headline)
                        .font(AppTypography.bodyStrong)
                        .foregroundStyle(AppColorRoles.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .accessibilityIdentifier("home.nextFocus.headline")
                }

                Text(snapshot.nextFocus.summary)
                    .font(summaryCardCaptionFont)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .lineLimit(summaryCardSummaryLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("home.nextFocus.summary")

                if !dynamicTypeSize.isAccessibilitySize {
                    Text(snapshot.weekDetail)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColorRoles.textTertiary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(summaryCardPadding)
            .frame(maxWidth: .infinity, minHeight: snapshot.prefersStackedPanels ? 116 : 104, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColorRoles.surfaceInteractive.opacity(colorScheme == .dark ? 0.72 : 1.0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.nextFocus.button")
    }

    private var nextFocusCard: some View {
        Button(action: onNextFocusTap) {
            VStack(alignment: .leading, spacing: summaryCardVerticalSpacing) {
                HStack(alignment: .center, spacing: 8) {
                    miniLabel(
                        title: AppLocalization.string("home.nextfocus.label"),
                        icon: "chart.line.uptrend.xyaxis",
                        accent: accent
                    )

                    Spacer(minLength: 8)

                    Image(systemName: "arrow.up.right")
                        .font(AppTypography.iconSmall)
                        .foregroundStyle(accent.opacity(0.84))
                }

                if let primaryValue = snapshot.nextFocus.primaryValue {
                    VStack(alignment: .leading, spacing: summaryCardContentSpacing) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(primaryValue)
                                .font(summaryCardPrimaryFont)
                                .foregroundStyle(AppColorRoles.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("home.nextFocus.primaryValue")

                            if let supportingLabel = snapshot.nextFocus.supportingLabel {
                                Text(supportingLabel)
                                    .font(summaryCardBadgeFont)
                                    .foregroundStyle(colorScheme == .dark ? accent : AppColorRoles.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                                    .padding(.horizontal, summaryCardBadgeHorizontalPadding)
                                    .padding(.vertical, summaryCardBadgeVerticalPadding)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(pillFill)
                                            .overlay(
                                                Capsule(style: .continuous)
                                                    .stroke(pillStroke, lineWidth: 1)
                                            )
                                    )
                                    .accessibilityIdentifier("home.nextFocus.supportingLabel")
                            }
                        }

                        Text(snapshot.nextFocus.summary)
                            .font(summaryCardCaptionFont)
                            .foregroundStyle(AppColorRoles.textSecondary)
                            .lineLimit(summaryCardSummaryLineLimit)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("home.nextFocus.summary")
                    }
                } else {
                    VStack(alignment: .leading, spacing: summaryCardContentSpacing) {
                        if let headline = snapshot.nextFocus.headline {
                            Text(headline)
                                .font(AppTypography.bodyStrong)
                                .foregroundStyle(AppColorRoles.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("home.nextFocus.headline")
                        }

                        Text(snapshot.nextFocus.summary)
                            .font(summaryCardCaptionFont)
                            .foregroundStyle(AppColorRoles.textSecondary)
                            .lineLimit(summaryCardSummaryLineLimit)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("home.nextFocus.summary")
                    }
                }
            }
            .padding(summaryCardPadding)
            .frame(maxWidth: .infinity, minHeight: summaryCardMinHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(pillFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.nextFocus.button")
    }

    private var thisWeekCard: some View {
        VStack(alignment: .leading, spacing: summaryCardVerticalSpacing) {
            miniLabel(
                title: AppLocalization.string("This week"),
                icon: "calendar",
                accent: AppColorRoles.textSecondary
            )

            Text(snapshot.weekTitle)
                .font(AppTypography.displayStatement)
                .foregroundStyle(AppColorRoles.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(snapshot.weekDetail)
                .font(summaryCardCaptionFont)
                .foregroundStyle(AppColorRoles.textSecondary)
                .lineLimit(3)
                .minimumScaleFactor(0.86)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(summaryCardPadding)
        .frame(maxWidth: .infinity, minHeight: summaryCardMinHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                )
        )
    }

    private var freshPromptCard: some View {
        Button(action: onNextFocusTap) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.string("home.hero.fresh.title"))
                        .font(AppTypography.bodyStrong)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    Text(AppLocalization.string("home.hero.fresh.detail"))
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 8)

                Text(AppLocalization.string("home.hero.fresh.cta"))
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(accent)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColorRoles.surfaceInteractive)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func measurementHighlightCard(_ measurement: HomeHeroMeasurementSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            miniLabel(
                title: measurement.label,
                icon: "ruler.fill",
                accent: accent
            )

            Text(measurement.value)
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 28 : 34, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(AppColorRoles.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .accessibilityIdentifier("home.hero.primaryMeasurement.value")

            Text(measurement.detail)
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(AppColorRoles.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(pillFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(pillStroke, lineWidth: 1)
                )
        )
        .accessibilityIdentifier("home.hero.primaryMeasurement")
    }

    // MARK: - Pulse Primary Card

    private func pulsePrimaryCard(_ signal: HeroPulseSignal) -> some View {
        Button(action: { onPulseAction(signal.action) }) {
            HStack(alignment: .center, spacing: 14) {
                pulseLeadingIcon(signal)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(signal.title)
                        .font(AppTypography.bodyStrong)
                        .foregroundStyle(AppColorRoles.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("home.hero.pulse.primary.title")

                    Text(signal.subtitle)
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("home.hero.pulse.primary.subtitle")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if signal.action != .none {
                    Image(systemName: "arrow.up.right")
                        .font(AppTypography.iconSmall)
                        .foregroundStyle(AppColorRoles.textTertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(pulseBackground(for: signal.tint))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.hero.pulse.primary")
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func pulseLeadingIcon(_ signal: HeroPulseSignal) -> some View {
        if signal.useStreakBadge {
            StreakBadge(
                count: signal.streakCount,
                shouldAnimate: signal.animateStreak,
                onAnimationComplete: onStreakAnimationComplete
            )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(pulseIconBackground(for: signal.tint))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(pulseIconStroke(for: signal.tint), lineWidth: 1)
                    )
                Image(systemName: signal.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(pulseIconForeground(for: signal.tint))
            }
        }
    }

    private func pulseBackground(for tint: HeroPulseTint) -> some View {
        let color = pulseTintColor(tint)
        return RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(color.opacity(colorScheme == .dark ? 0.14 : 0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(color.opacity(0.32), lineWidth: 1)
            )
    }

    private func pulseIconBackground(for tint: HeroPulseTint) -> Color {
        pulseTintColor(tint).opacity(0.18)
    }

    private func pulseIconStroke(for tint: HeroPulseTint) -> Color {
        pulseTintColor(tint).opacity(0.30)
    }

    private func pulseIconForeground(for tint: HeroPulseTint) -> Color {
        let color = pulseTintColor(tint)
        if tint == .neutral { return AppColorRoles.textSecondary }
        return color
    }

    private func pulseTintColor(_ tint: HeroPulseTint) -> Color {
        switch tint {
        case .accent: return accent
        case .success: return AppColorRoles.stateSuccess
        case .warning: return Color(hex: "#EF4444")
        case .neutral: return AppColorRoles.textTertiary
        }
    }

    // MARK: - Pulse Chips Row

    @ViewBuilder
    private var pulseChipsRow: some View {
        let showNext = snapshot.showNextFocusChip
        let showWeek = snapshot.showThisWeekChip

        if showNext || showWeek {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    if showNext { pulseChipNextFocus }
                    if showWeek { pulseChipThisWeek }
                }

                VStack(spacing: 10) {
                    if showNext { pulseChipNextFocus }
                    if showWeek { pulseChipThisWeek }
                }
            }
        }
    }

    private var pulseChipNextFocus: some View {
        Button(action: onNextFocusTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(AppTypography.iconSmall)
                        .foregroundStyle(accent)
                    Text(snapshot.nextFocus.contextLabel)
                        .font(AppTypography.eyebrow)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .lineLimit(1)
                }

                if let primaryValue = snapshot.nextFocus.primaryValue {
                    Text(primaryValue)
                        .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(AppColorRoles.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityIdentifier("home.nextFocus.primaryValue")
                } else if let headline = snapshot.nextFocus.headline {
                    Text(headline)
                        .font(AppTypography.bodyStrong)
                        .foregroundStyle(AppColorRoles.textPrimary)
                        .lineLimit(1)
                        .accessibilityIdentifier("home.nextFocus.headline")
                }

                Text(snapshot.nextFocus.summary)
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home.nextFocus.summary")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppColorRoles.surfaceInteractive.opacity(colorScheme == .dark ? 0.72 : 1.0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.hero.pulse.chip.nextFocus")
    }

    private var pulseChipThisWeek: some View {
        Button(action: onThisWeekTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(AppTypography.iconSmall)
                        .foregroundStyle(AppColorRoles.textSecondary)
                    Text(AppLocalization.string("This week"))
                        .font(AppTypography.eyebrow)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .lineLimit(1)
                }

                Text(snapshot.weekTitle)
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)

                Text(snapshot.weekDetail)
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppColorRoles.surfaceInteractive.opacity(colorScheme == .dark ? 0.72 : 1.0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.hero.pulse.chip.thisWeek")
    }

    private func miniLabel(title: String, icon: String, accent: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(dynamicTypeSize.isAccessibilitySize ? AppTypography.microEmphasis : AppTypography.iconSmall)
                .foregroundStyle(accent)

            Text(title)
                .font(dynamicTypeSize.isAccessibilitySize ? AppTypography.microEmphasis : AppTypography.eyebrow)
                .foregroundStyle(colorScheme == .dark ? accent : AppColorRoles.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }

    private var summaryCardPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 12 : 16
    }

    private var summaryCardVerticalSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 8 : 12
    }

    private var summaryCardContentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 6 : 8
    }

    private var summaryCardCaptionFont: Font {
        dynamicTypeSize.isAccessibilitySize ? AppTypography.caption : AppTypography.captionEmphasis
    }

    private var summaryCardPrimaryFont: Font {
        let size = dynamicTypeSize.isAccessibilitySize ? 19.0 : (snapshot.prefersStackedPanels ? 22.0 : 24.0)
        return .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }

    private var insightCardPrimaryFont: Font {
        let size = dynamicTypeSize.isAccessibilitySize ? 18.0 : (snapshot.prefersStackedPanels ? 20.0 : 21.0)
        return .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }

    private var summaryCardBadgeFont: Font {
        dynamicTypeSize.isAccessibilitySize ? AppTypography.microEmphasis : AppTypography.badge
    }

    private var summaryCardBadgeHorizontalPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 4 : 6
    }

    private var summaryCardBadgeVerticalPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 2 : 3
    }

    private var summaryCardSummaryLineLimit: Int {
        dynamicTypeSize.isAccessibilitySize ? 1 : 2
    }

    private var summaryCardMinHeight: CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return 112
        }
        return snapshot.prefersStackedPanels ? 134 : 138
    }
}
