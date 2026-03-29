import SwiftUI

struct HomeSecondaryMetricToggleRow: View {
    let kind: MetricKind
    let latestText: String
    let detailText: String
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
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
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppColorRoles.surfaceInteractive)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.keyMetrics.secondary.\(kind.rawValue).toggle")
    }
}

struct HomeCustomSecondaryMetricRow: View {
    let definition: CustomMetricDefinition
    let latestText: String

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

            Text(latestText)
                .font(AppTypography.captionEmphasis.monospacedDigit())
                .foregroundStyle(AppColorRoles.textPrimary)

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
}
