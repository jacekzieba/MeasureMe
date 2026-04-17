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
        .accessibilityIdentifier("home.keyMetrics.secondary.\(kind.rawValue).toggle")
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
