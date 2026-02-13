import SwiftUI

struct MetricInsightCard: View {
    let text: String
    let compact: Bool
    let isLoading: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(compact ? AppTypography.iconSmall : AppTypography.iconSmall)
                .foregroundStyle(Color(hex: "#FCA311"))
                .padding(8)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(compact ? AppTypography.microEmphasis : .subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .redacted(reason: isLoading ? .placeholder : [])
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(compact ? "insight.card.text.compact" : "insight.card.text.detail")

                Text(AppLocalization.string("AI generated"))
                    .font(AppTypography.micro)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(compact ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.08)
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
