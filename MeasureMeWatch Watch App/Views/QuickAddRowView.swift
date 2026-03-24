import SwiftUI

struct QuickAddRowView: View {
    let kind: WatchMetricKind
    let isMetric: Bool
    let displayValue: Double
    let isSelected: Bool

    private var formattedValue: String {
        kind.formattedDisplayValue(displayValue, isMetric: isMetric)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: kind.systemImage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.watchAccent)
                        .accessibilityHidden(true)

                    Text(kind.shortName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.watchTertiaryText)
                        .lineLimit(1)
                }

                Text(formattedValue)
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.watchAccent : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer()

            if isSelected {
                Image(systemName: "crown.fill")
                    .font(.caption)
                    .foregroundStyle(Color.watchAccent.opacity(0.6))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.watchAccent.opacity(0.12) : Color.white.opacity(0.06))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
