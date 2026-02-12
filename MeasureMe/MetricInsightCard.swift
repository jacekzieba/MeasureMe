import SwiftUI

struct MetricInsightCard: View {
    let text: String
    let compact: Bool
    let isLoading: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                .foregroundStyle(Color(hex: "#FCA311"))
                .padding(8)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())

            Text(text)
                .font(compact ? AppTypography.caption : AppTypography.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(compact ? 4 : nil)
                .redacted(reason: isLoading ? .placeholder : [])
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
