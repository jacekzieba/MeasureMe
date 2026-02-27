import SwiftUI

/// Standalone sparkline chart for use in the widget extension.
/// Mirrors the logic of MiniSparklineChart from the main app.
struct WidgetSparklineView: View {
    let samples: [WidgetMetricData.SampleDTO]
    let trendColor: Color

    var body: some View {
        GeometryReader { geo in
            if samples.count < 2 {
                // Placeholder: dashed center line
                Path { path in
                    let mid = geo.size.height / 2
                    path.move(to: CGPoint(x: 0, y: mid))
                    path.addLine(to: CGPoint(x: geo.size.width, y: mid))
                }
                .stroke(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            } else {
                ZStack(alignment: .bottom) {
                    // Gradient fill beneath the trend line
                    Path { path in
                        let pts = normalizedPoints(in: geo.size)
                        guard let first = pts.first else { return }
                        path.move(to: CGPoint(x: first.x, y: geo.size.height))
                        path.addLine(to: first)
                        pts.dropFirst().forEach { path.addLine(to: $0) }
                        if let last = pts.last {
                            path.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                        }
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [trendColor.opacity(0.25), trendColor.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))

                    // Trend line
                    Path { path in
                        let pts = normalizedPoints(in: geo.size)
                        guard let first = pts.first else { return }
                        path.move(to: first)
                        pts.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(trendColor,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let values = samples.map(\.value)
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 0
        let range = maxV - minV > 0 ? maxV - minV : 1
        let padding: CGFloat = 0.10
        let adjustedH = size.height * (1 - 2 * padding)

        return samples.enumerated().map { idx, s in
            let x = samples.count > 1
                ? size.width * CGFloat(idx) / CGFloat(samples.count - 1)
                : size.width / 2
            let normalized = (s.value - minV) / range
            let y = size.height * padding + adjustedH * (1 - normalized)
            return CGPoint(x: x, y: y)
        }
    }
}
