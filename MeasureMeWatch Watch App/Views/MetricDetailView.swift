import SwiftUI

struct MetricDetailView: View {
    let kind: WatchMetricKind
    let data: WatchMetricData?
    let unitsSystem: String

    private var recentSamples: [WatchMetricData.SampleDTO] {
        data?.last30DaySamples ?? []
    }

    private var last10Samples: [WatchMetricData.SampleDTO] {
        let all = data?.samples ?? []
        return Array(all.suffix(10))
    }

    private var trendColor: Color {
        guard let data else { return .white.opacity(0.3) }
        switch data.trendOutcome(for: kind, recentSamples: recentSamples) {
        case .positive: return .watchGreen
        case .negative: return .watchRed
        case .neutral:  return .white.opacity(0.4)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Header: value + delta
                HStack(alignment: .firstTextBaseline) {
                    Text(data?.formattedValue(for: kind, unitsSystemOverride: unitsSystem) ?? "—")
                        .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)

                    Spacer()

                    if let delta = data?.deltaText(for: kind, recentSamples: recentSamples, unitsSystemOverride: unitsSystem) {
                        Text(delta)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(trendColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(trendColor.opacity(0.13), in: Capsule())
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(kind.displayName)
                .accessibilityValue(detailAccessibilityValue)

                // Goal info
                if let goal = data?.goal {
                    let isMetric = unitsSystem != "imperial"
                    let targetDisplay = kind.valueForDisplay(fromMetric: goal.targetValue, isMetric: isMetric)
                    HStack(spacing: 4) {
                        Image(systemName: "target")
                            .font(.caption2)
                            .foregroundStyle(Color.watchAccent)
                            .accessibilityHidden(true)
                        Text(kind.formattedDisplayValue(targetDisplay, isMetric: isMetric))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.watchSubtleText)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(data?.accessibilityGoalDescription(for: kind, unitsSystemOverride: unitsSystem) ?? watchLocalized("Goal", "Cel"))
                }

                // Sparkline
                WatchSparklineView(samples: recentSamples, trendColor: trendColor)
                    .frame(height: 50)
                    .padding(.vertical, 4)
                    .accessibilityHidden(true)

                Text(data?.accessibilityTrendDescription(for: kind, recentSamples: recentSamples, unitsSystemOverride: unitsSystem)
                     ?? watchLocalized("Not enough data for trend", "Za mało danych, aby ocenić trend"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.watchSubtleText)
                    .fixedSize(horizontal: false, vertical: true)

                // Recent measurements
                Text(WatchLocalization.string("Recent"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.watchSubtleText)

                ForEach(last10Samples.reversed(), id: \.date) { sample in
                    let isMetric = unitsSystem != "imperial"
                    let displayVal = kind.valueForDisplay(fromMetric: sample.value, isMetric: isMetric)
                    HStack {
                        Text(formattedDate(sample.date))
                            .font(.caption2)
                            .foregroundStyle(Color.watchSubtleText)
                        Spacer()
                        Text(kind.formattedDisplayValue(displayVal, isMetric: isMetric))
                            .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    .padding(.vertical, 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(formattedDate(sample.date)), \(kind.formattedDisplayValue(displayVal, isMetric: isMetric))")
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle(kind.displayName)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = WatchLocalization.currentLocale
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private var detailAccessibilityValue: String {
        let value = data?.formattedValue(for: kind, unitsSystemOverride: unitsSystem) ?? "—"
        let trend = data?.accessibilityTrendDescription(for: kind, recentSamples: recentSamples, unitsSystemOverride: unitsSystem)
            ?? watchLocalized("Not enough data for trend", "Za mało danych, aby ocenić trend")
        if let goal = data?.accessibilityGoalDescription(for: kind, unitsSystemOverride: unitsSystem) {
            return "\(value). \(trend). \(goal)"
        }
        return "\(value). \(trend)"
    }
}
