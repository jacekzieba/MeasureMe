import SwiftUI
import SwiftData

// MARK: - Chart Controls (secondary action cards, legend)

private extension MetricDetailView {

    var chartSectionContent: some View {
        VStack(spacing: 12) {
            Picker(AppLocalization.string("Range"), selection: $timeframe) {
                ForEach(Timeframe.allCases) { tf in
                    Text(tf.rawValue).tag(tf)
                }
            }
            .pickerStyle(.segmented)

            chartView
                .padding(.bottom, 6)

            chartLegendRow

            HStack(spacing: 12) {
                Button {
                    showGoalSheet = true
                } label: {
                    secondaryActionCard(
                        title: AppLocalization.string("Goal"),
                        subtitle: currentGoal.map { valueString($0.targetValue) },
                        icon: "target",
                        color: measurementsTheme.accent
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("metric.detail.goal")
                .accessibilityLabel(currentGoal == nil ? AppLocalization.string("accessibility.goal.set") : AppLocalization.string("accessibility.goal.update"))
                .accessibilityHint(AppLocalization.string("accessibility.goal.define"))

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showTrendline.toggle()
                    }
                    Haptics.selection()
                } label: {
                    secondaryActionCard(
                        title: AppLocalization.string("Trend"),
                        icon: "chart.line.uptrend.xyaxis",
                        color: AppColorRoles.stateSuccess,
                        isActive: showTrendline
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("metric.detail.trend")
                .accessibilityLabel(AppLocalization.string("accessibility.trendline"))
                .accessibilityValue(showTrendline ? AppLocalization.string("accessibility.visible") : AppLocalization.string("accessibility.hidden"))
                .accessibilityHint(AppLocalization.string("accessibility.trendline.toggle"))

                Button {
                    showCompareSheet = true
                } label: {
                    secondaryActionCard(
                        title: AppLocalization.string("metric.compare.title"),
                        icon: "square.stack.3d.up",
                        color: AppColorRoles.compareAfter,
                        isActive: isComparisonActive
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("metric.detail.compare")
                .accessibilityLabel(AppLocalization.string("metric.compare.button"))
                .accessibilityValue(compareActionValueText)
                .accessibilityHint(AppLocalization.string("metric.compare.button.hint"))
            }
        }
    }

    func secondaryActionCard(
        title: String,
        subtitle: String? = nil,
        icon: String,
        color: Color,
        isActive: Bool = true,
        showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(AppTypography.iconMedium)
                .foregroundStyle(isActive ? color : AppColorRoles.textSecondary)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(
                            isActive
                                ? color.opacity(colorScheme == .dark ? 0.18 : 0.12)
                                : AppColorRoles.surfacePrimary.opacity(colorScheme == .dark ? 0.82 : 0.96)
                        )
                )
                .overlay(
                    Circle()
                        .stroke(
                            isActive
                                ? color.opacity(colorScheme == .dark ? 0.34 : 0.16)
                                : AppColorRoles.borderSubtle.opacity(colorScheme == .dark ? 0.72 : 0.9),
                            lineWidth: 1
                        )
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .allowsTightening(true)
                }
            }
            .layoutPriority(1)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColorRoles.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(actionCardBackground(accent: color, isActive: isActive))
    }

    var chartLegendRow: some View {
        HStack {
            legendItem(
                title: kind.title,
                color: measurementsTheme.accent,
                subtitle: nil
            )
            Spacer(minLength: 0)
        }
    }

    func legendItem(title: String, color: Color, subtitle: String?, dashed: Bool = false) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 4] : []))
                .background {
                    if !dashed {
                        Capsule().fill(color)
                    }
                }
                .frame(width: 18, height: 4)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColorRoles.textSecondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(legendChipBackground(accent: color))
    }

    func actionCardBackground(accent: Color, isActive: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
        let fillColors: [Color] = {
            if colorScheme == .dark {
                return [
                    AppColorRoles.surfaceChrome.opacity(isActive ? 0.98 : 0.92),
                    AppColorRoles.surfaceInteractive.opacity(isActive ? 0.94 : 0.82)
                ]
            }

            return isActive
                ? [
                    Color(hex: "#FAFBF8"),
                    Color(hex: "#F0F1EC")
                ]
                : [
                    Color(hex: "#F6F7F3"),
                    Color(hex: "#ECEDE7")
                ]
        }()
        let shadowColor = AppColorRoles.shadowSoft.opacity(colorScheme == .dark ? 0.18 : (isActive ? 0.18 : 0.12))
        let shadowBlur: CGFloat = isActive ? 10 : 7
        let shadowYOffset: CGFloat = isActive ? 4 : 3

        return ZStack {
            shape
                .fill(shadowColor)
                .blur(radius: shadowBlur)
                .offset(y: shadowYOffset)

            shape
                .fill(
                    ClaudeLightStyle.directionalGradient(
                        colors: fillColors,
                        colorScheme: colorScheme,
                        lightColor: fillColors.first ?? AppColorRoles.surfacePrimary
                    )
                )
                .overlay(
                    shape.fill(
                        ClaudeLightStyle.directionalGradient(
                            colors: [
                                accent.opacity(isActive ? (colorScheme == .dark ? 0.18 : 0.08) : 0.025),
                                .clear
                            ],
                            colorScheme: colorScheme,
                            lightColor: accent.opacity(isActive ? 0.04 : 0.015)
                        )
                    )
                )
                .overlay(
                    shape.stroke(
                        ClaudeLightStyle.directionalGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.16 : 0.9),
                                AppColorRoles.borderStrong.opacity(colorScheme == .dark ? 0.92 : 0.62)
                            ],
                            colorScheme: colorScheme,
                            lightColor: AppColorRoles.borderSubtle
                        ),
                        lineWidth: 1
                    )
                )
        }
    }

    func legendChipBackground(accent: Color) -> some View {
        let shape = Capsule(style: .continuous)
        let shadowColor = AppColorRoles.shadowSoft.opacity(colorScheme == .dark ? 0.14 : 0.1)

        return ZStack {
            shape
                .fill(shadowColor)
                .blur(radius: 8)
                .offset(y: 3)

            shape
                .fill(
                    ClaudeLightStyle.directionalGradient(
                        colors: colorScheme == .dark
                            ? [
                                AppColorRoles.surfaceChrome.opacity(0.96),
                                AppColorRoles.surfaceInteractive.opacity(0.88)
                            ]
                            : [
                                Color(hex: "#F9FAF7"),
                                Color(hex: "#EFF1EA")
                            ],
                        colorScheme: colorScheme,
                        lightColor: AppColorRoles.surfaceSecondary
                    )
                )
                .overlay(
                    shape.fill(
                        ClaudeLightStyle.directionalGradient(
                            colors: [
                                accent.opacity(colorScheme == .dark ? 0.12 : 0.06),
                                .clear
                            ],
                            colorScheme: colorScheme,
                            lightColor: accent.opacity(0.04),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                )
                .overlay(
                    shape.stroke(
                        ClaudeLightStyle.directionalGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.14 : 0.86),
                                AppColorRoles.borderStrong.opacity(colorScheme == .dark ? 0.82 : 0.56)
                            ],
                            colorScheme: colorScheme,
                            lightColor: AppColorRoles.borderSubtle
                        ),
                        lineWidth: 1
                    )
                )
        }
    }
}
