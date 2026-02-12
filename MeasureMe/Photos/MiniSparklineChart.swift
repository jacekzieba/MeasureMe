import SwiftUI

/// Minimalistyczny wykres liniowy (sparkline) bez osi, tła - tylko linia trendu
/// Pokazuje trend za ostatnie 30 dni z kolorystyką: wzrost = zielony, spadek = czerwony
/// Zoptymalizowany dla kompaktowych kafelków zgodnie z Apple Design Guidelines
struct MiniSparklineChart: View {
    let samples: [MetricSample]
    let kind: MetricKind
    let goal: MetricGoal?
    
    private var last30Days: [MetricSample] {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return samples
            .filter { $0.date >= thirtyDaysAgo }
            .sorted { $0.date < $1.date }
    }
    
    private var trendColor: Color {
        guard last30Days.count >= 2,
              let first = last30Days.first?.value,
              let last = last30Days.last?.value else {
            return Color.gray.opacity(0.5)
        }

        switch kind.trendOutcome(from: first, to: last, goal: goal) {
        case .positive:
            return Color(hex: "#22C55E").opacity(0.85)
        case .negative:
            return Color(hex: "#EF4444").opacity(0.85)
        case .neutral:
            return Color.gray.opacity(0.5)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            if last30Days.isEmpty {
                // Brak danych - bardziej subtelny placeholder
                Path { path in
                    let midY = geometry.size.height / 2
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: midY))
                }
                .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            } else {
                // Rysuj sparkline z gradientem pod linią
                ZStack(alignment: .bottom) {
                    // Gradient fill pod linią (opcjonalny - subtelny)
                    Path { path in
                        let points = normalizedPoints(in: geometry.size)
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
                            colors: [trendColor.opacity(0.15), trendColor.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // Główna linia trendu
                    Path { path in
                        let points = normalizedPoints(in: geometry.size)
                        
                        guard let firstPoint = points.first else { return }
                        
                        path.move(to: firstPoint)
                        
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(trendColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }
    
    /// Normalizuje punkty danych do wymiarów widoku
    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard !last30Days.isEmpty else { return [] }
        
        let values = last30Days.map { $0.value }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let range = maxValue - minValue
        
        // Jeśli wszystkie wartości są takie same, rysuj linię prostą na środku
        let useRange = range > 0 ? range : 1
        
        // Dodaj padding 10% z góry i dołu dla lepszej prezentacji
        let padding: CGFloat = 0.1
        let adjustedHeight = size.height * (1 - 2 * padding)
        
        return last30Days.enumerated().map { index, sample in
            let x = last30Days.count > 1 
                ? size.width * CGFloat(index) / CGFloat(last30Days.count - 1)
                : size.width / 2
            
            // Odwróć oś Y (0 na górze, height na dole) + padding
            let normalizedValue = (sample.value - minValue) / useRange
            let y = size.height * padding + adjustedHeight * (1 - normalizedValue)
            
            return CGPoint(x: x, y: y)
        }
    }
}
