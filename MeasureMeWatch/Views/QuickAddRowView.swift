import SwiftUI

struct QuickAddRowView: View {
    let kind: WatchMetricKind
    let isMetric: Bool
    @Binding var displayValue: Double
    let isSelected: Bool

    private var unit: String {
        kind.unitSymbol(isMetric: isMetric)
    }

    private var formattedValue: String {
        let fmt = kind.unitCategory == .percent ? "%.1f%@" : "%.1f\u{202F}%@"
        return String(format: fmt, displayValue, unit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: kind.systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.watchAccent)

                Text(kind.shortName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Text(formattedValue)
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(isSelected ? Color.watchAccent : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.watchAccent.opacity(0.12) : Color.white.opacity(0.06))
        )
    }
}
