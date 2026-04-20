import SwiftUI

struct HomeMetricDeltaChip {
    let text: String
    let tint: Color
}

struct HomeSecondaryMetricToggleRow<ExpandedContent: View>: View {
    let kind: MetricKind
    let latestText: String
    let detailText: String
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let expandedContent: () -> ExpandedContent

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        kind.iconView(font: AppTypography.captionEmphasis, size: 14, tint: Color.appAccent)
                        Text(kind.title)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColorRoles.textPrimary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(latestText)
                            .font(AppTypography.captionEmphasis.monospacedDigit())
                            .foregroundStyle(AppColorRoles.textPrimary)
                        Text(detailText)
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColorRoles.textSecondary)
                            .lineLimit(1)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppColorRoles.textTertiary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(AppColorRoles.borderSubtle.opacity(0.7))
                        .frame(height: 1)
                        .padding(.horizontal, 12)

                    expandedContent()
                        .padding(12)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                )
        )
    }
}

struct HomeSecondaryMetricNavigationRow: View {
    let kind: MetricKind
    let latestText: String
    let detailText: String
    let deltaChip: HomeMetricDeltaChip?

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                kind.iconView(font: AppTypography.captionEmphasis, size: 14, tint: Color.appAccent)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)
                        .lineLimit(1)

                    Text(detailText)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(latestText)
                    .font(AppTypography.captionEmphasis.monospacedDigit())
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .lineLimit(1)

                if let deltaChip {
                    deltaChipView(deltaChip)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppColorRoles.textTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                )
        )
        .accessibilityIdentifier("home.keyMetrics.secondary.\(kind.rawValue).row")
    }

    private func deltaChipView(_ chip: HomeMetricDeltaChip) -> some View {
        Text(chip.text)
            .font(AppTypography.badge)
            .foregroundStyle(chip.tint)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(chip.tint.opacity(0.12))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(chip.tint.opacity(0.24), lineWidth: 1)
                    )
            )
    }
}

struct HomeExpandedMetricTrendChart: View {
    let kind: MetricKind
    let samples: [MetricSample]
    let goal: MetricGoal?
    let unitsSystem: String

    private var sortedSamples: [MetricSample] {
        samples.sorted { $0.date < $1.date }
    }

    private var trendColor: Color {
        guard let first = sortedSamples.first, let last = sortedSamples.last else {
            return AppColorRoles.textTertiary
        }

        switch kind.trendOutcome(from: first.value, to: last.value, goal: goal) {
        case .positive:
            return AppColorRoles.stateSuccess
        case .negative:
            return Color(hex: "#EF4444")
        case .neutral:
            return AppColorRoles.textTertiary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let points = normalizedPoints(in: proxy.size)

                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppColorRoles.surfaceInteractive.opacity(0.72))

                    ForEach(0..<4, id: \.self) { index in
                        Rectangle()
                            .fill(AppColorRoles.borderSubtle.opacity(0.45))
                            .frame(height: 1)
                            .offset(y: proxy.size.height * CGFloat(index) / 3)
                    }

                    if points.count >= 2 {
                        Path { path in
                            guard let firstPoint = points.first else { return }
                            path.move(to: CGPoint(x: firstPoint.x, y: proxy.size.height))
                            path.addLine(to: firstPoint)
                            for point in points.dropFirst() {
                                path.addLine(to: point)
                            }
                            if let lastPoint = points.last {
                                path.addLine(to: CGPoint(x: lastPoint.x, y: proxy.size.height))
                            }
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [trendColor.opacity(0.18), trendColor.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        Path { path in
                            guard let firstPoint = points.first else { return }
                            path.move(to: firstPoint)
                            for point in points.dropFirst() {
                                path.addLine(to: point)
                            }
                        }
                        .stroke(trendColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                        if let lastPoint = points.last {
                            Circle()
                                .fill(trendColor)
                                .frame(width: 8, height: 8)
                                .position(lastPoint)
                        }
                    } else {
                        Rectangle()
                            .fill(AppColorRoles.borderSubtle.opacity(0.7))
                            .frame(height: 1)
                            .padding(.horizontal, 10)
                    }
                }
            }
            .frame(height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                if let first = sortedSamples.first {
                    Text(valueText(first.value))
                }

                Spacer(minLength: 8)

                if let last = sortedSamples.last {
                    Text(valueText(last.value))
                }
            }
            .font(AppTypography.microEmphasis.monospacedDigit())
            .foregroundStyle(AppColorRoles.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.string("accessibility.chart", kind.title))
    }

    private func valueText(_ value: Double) -> String {
        kind.formattedMetricValue(fromMetric: value, unitsSystem: unitsSystem)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let usableSamples = sortedSamples
        guard !usableSamples.isEmpty else { return [] }

        let values = usableSamples.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let range = max(maxValue - minValue, 0.0001)
        let horizontalInset: CGFloat = 10
        let verticalInset: CGFloat = 12
        let width = max(size.width - horizontalInset * 2, 1)
        let height = max(size.height - verticalInset * 2, 1)

        return usableSamples.enumerated().map { index, sample in
            let x = usableSamples.count > 1
                ? horizontalInset + width * CGFloat(index) / CGFloat(usableSamples.count - 1)
                : size.width / 2
            let normalized = (sample.value - minValue) / range
            let y = verticalInset + height * (1 - normalized)
            return CGPoint(x: x, y: y)
        }
    }
}

struct HomeCustomSecondaryMetricRow: View {
    let definition: CustomMetricDefinition
    let latestText: String
    let deltaChip: HomeMetricDeltaChip?

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: definition.sfSymbolName)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 14, height: 14)
                Text(definition.name)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(latestText)
                    .font(AppTypography.captionEmphasis.monospacedDigit())
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .lineLimit(1)

                if let deltaChip {
                    deltaChipView(deltaChip)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppColorRoles.textTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                )
        )
    }

    private func deltaChipView(_ chip: HomeMetricDeltaChip) -> some View {
        Text(chip.text)
            .font(AppTypography.badge)
            .foregroundStyle(chip.tint)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(chip.tint.opacity(0.12))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(chip.tint.opacity(0.24), lineWidth: 1)
                    )
            )
    }
}
