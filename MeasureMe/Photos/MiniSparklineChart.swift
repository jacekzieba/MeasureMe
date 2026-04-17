import SwiftUI
#if canImport(Accessibility)
import Accessibility
#endif

/// Minimalist line chart (sparkline) without axes or background - only the trend line
/// Shows trend for the last 30 days with coloring: increase = green, decrease = red
/// Optimized for compact tiles following Apple Design Guidelines
struct MiniSparklineChart: View {
    let kind: MetricKind
    private let recentSamples: [MetricSample]
    private let cachedTrendOutcome: MetricKind.TrendOutcome?

    init(samples: [MetricSample], kind: MetricKind, goal: MetricGoal?) {
        self.kind = kind
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: AppClock.now) ?? AppClock.now
        let filtered = samples
            .filter { $0.date >= thirtyDaysAgo }
            .sorted { $0.date < $1.date }
        self.recentSamples = filtered

        if filtered.count >= 2, let first = filtered.first?.value, let last = filtered.last?.value {
            self.cachedTrendOutcome = kind.trendOutcome(from: first, to: last, goal: goal)
        } else {
            self.cachedTrendOutcome = nil
        }
    }

    private var trendColor: Color {
        guard let cachedTrendOutcome else {
            return Color.gray.opacity(0.5)
        }

        switch cachedTrendOutcome {
        case .positive:
            return AppColorRoles.stateSuccess.opacity(0.85)
        case .negative:
            return Color(hex: "#EF4444").opacity(0.85)
        case .neutral:
            return Color.gray.opacity(0.5)
        }
    }
    
    private var trendAccessibilityValue: String {
        guard let cachedTrendOutcome else {
            return AppLocalization.string("No data")
        }
        switch cachedTrendOutcome {
        case .positive: return AppLocalization.string("trend.up")
        case .negative: return AppLocalization.string("trend.down")
        case .neutral: return AppLocalization.string("trend.steady")
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let points = normalizedPoints(in: geometry.size)
            let color = trendColor

            if points.isEmpty {
                // No data - more subtle placeholder
                Path { path in
                    let midY = geometry.size.height / 2
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: midY))
                }
                .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            } else {
                // Draw sparkline with gradient fill below the line
                ZStack(alignment: .bottom) {
                    // Gradient fill below the line (optional - subtle)
                    Path { path in
                        guard let firstPoint = points.first else { return }
                        
                        path.move(to: CGPoint(x: firstPoint.x, y: geometry.size.height))
                        path.addLine(to: firstPoint)
                        
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                        
                        if let lastPoint = points.last {
                            path.addLine(to: CGPoint(x: lastPoint.x, y: geometry.size.height))
                        }
                        
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.15), color.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // Main trend line
                    Path { path in
                        guard let firstPoint = points.first else { return }
                        
                        path.move(to: firstPoint)
                        
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title)
        .accessibilityValue(trendAccessibilityValue)
        .accessibilityChartDescriptor(self)
    }
    
    /// Normalizes data points to the view dimensions
    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard !recentSamples.isEmpty else { return [] }
        
        let values = recentSamples.map { $0.value }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let range = maxValue - minValue
        
        // If all values are the same, draw a straight line in the middle
        let useRange = range > 0 ? range : 1
        
        // Add 10% padding top and bottom for better presentation
        let padding: CGFloat = 0.1
        let adjustedHeight = size.height * (1 - 2 * padding)
        
        return recentSamples.enumerated().map { index, sample in
            let x = recentSamples.count > 1
                ? size.width * CGFloat(index) / CGFloat(recentSamples.count - 1)
                : size.width / 2

            // Invert Y axis (0 at top, height at bottom) + padding
            let normalizedValue = (sample.value - minValue) / useRange
            let y = size.height * padding + adjustedHeight * (1 - normalizedValue)

            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Accessibility — chart navigation via VoiceOver rotor

extension MiniSparklineChart: AXChartDescriptorRepresentable {
    func makeChartDescriptor() -> AXChartDescriptor {
        // Snapshot once; closures below are called by AX subsystem later.
        let samples = recentSamples
        let kind = self.kind
        let unitsSystem = AppSettingsStore.shared.snapshot.profile.unitsSystem
        let summary = trendAccessibilityValue

        let values = samples.map { $0.value }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        // Ensure a non-zero range so AX subsystem does not divide by zero.
        let paddedMax = maxValue > minValue ? maxValue : minValue + 1

        let indexRange: ClosedRange<Double> = 0...Double(max(samples.count - 1, 1))

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        let xAxis = AXNumericDataAxisDescriptor(
            title: AppLocalization.string("Date"),
            range: indexRange,
            gridlinePositions: [],
            valueDescriptionProvider: { position in
                let index = Int(position.rounded())
                guard samples.indices.contains(index) else { return "" }
                return dateFormatter.string(from: samples[index].date)
            }
        )

        let yAxis = AXNumericDataAxisDescriptor(
            title: kind.title,
            range: minValue...paddedMax,
            gridlinePositions: [],
            valueDescriptionProvider: { metricValue in
                kind.formattedMetricValue(
                    fromMetric: metricValue,
                    unitsSystem: unitsSystem
                )
            }
        )

        let dataPoints: [AXDataPoint] = samples.enumerated().map { index, sample in
            AXDataPoint(x: Double(index), y: sample.value)
        }

        let series = AXDataSeriesDescriptor(
            name: kind.title,
            isContinuous: true,
            dataPoints: dataPoints
        )

        return AXChartDescriptor(
            title: kind.title,
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            series: [series]
        )
    }
}
