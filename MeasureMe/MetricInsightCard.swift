import SwiftUI

struct MetricInsightCard: View {
    let text: String
    let compact: Bool
    let isLoading: Bool
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(compact ? AppTypography.iconSmall : AppTypography.iconSmall)
                .foregroundStyle(AppColorRoles.accentPrimary)
                .padding(8)
                .background(AppColorRoles.accentPrimary.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(compact ? AppTypography.microEmphasis : AppTypography.body)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .redacted(reason: isLoading ? .placeholder : [])
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(compact ? "insight.card.text.compact" : "insight.card.text.detail")

                HStack {
                    Text(AppLocalization.string("AI generated"))
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColorRoles.textSecondary)

                    if let onRefresh, !isLoading {
                        Spacer()
                        Button {
                            onRefresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColorRoles.textSecondary)
                        }
                        .accessibilityLabel(AppLocalization.string("Refresh insight"))
                        .accessibilityIdentifier("insight.card.refresh")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(compact ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                .fill(AppColorRoles.surfaceGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            AppColorRoles.borderStrong,
                            AppColorRoles.borderSubtle
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 4)
    }
}
