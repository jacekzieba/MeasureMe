import SwiftUI
import Charts
import Accessibility
import SwiftData
import Foundation

@available(iOS 16.0, *)
extension MetricDetailView {
    var chartDescriptor: AXChartDescriptor {
        let unit = kind.unitSymbol(unitsSystem: self.unitsSystem)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"

        let points: [(String, Double)] = chartSamples.map { sample in
            let label = dateFormatter.string(from: sample.date)
            return (label, displayValue(sample.value))
        }

        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Date",
            categoryOrder: points.map(\.0)
        )

        let values = points.map(\.1)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1

        let yAxis = AXNumericDataAxisDescriptor(
            title: "\(kind.title) (\(unit))",
            range: minValue...maxValue,
            gridlinePositions: [],
            valueDescriptionProvider: { value in
                String(format: "%.1f %@", value, unit)
            }
        )

        let series = AXDataSeriesDescriptor(
            name: kind.title,
            isContinuous: true,
            dataPoints: points.map { AXDataPoint(x: $0.0, y: $0.1) }
        )

        let minText = String(format: "%.1f %@", minValue, unit)
        let maxText = String(format: "%.1f %@", maxValue, unit)
        let trendText = trendlineSegment?.endValue == trendlineSegment?.startValue ? "steady" :
        ((trendlineSegment?.endValue ?? 0) > (trendlineSegment?.startValue ?? 0) ? "trending up" : "trending down")
        let summary = "\(kind.title), \(timeframeLabel.lowercased()), from \(minText) to \(maxText), \(trendText)."
        return AXChartDescriptor(
            title: "\(kind.title) trend",
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }

    /// Określa dynamiczną pozycję etykiety celu na wykresie
    func goalLabelPosition(for goalValue: Double) -> AnnotationPosition {
        let minV = yDomain.lowerBound
        let maxV = yDomain.upperBound
        let span = max(maxV - minV, 0.0001)
        let rel = (goalValue - minV) / span
        if rel > 0.85 { return .bottom }
        if rel < 0.15 { return .top }
        return .top
    }

    /// Minimalny span dla osi Y - zapewnia czytelność gdy dane są bardzo zbliżone
    func minimalSpan(for kind: MetricKind) -> Double {
        switch kind.unitCategory {
        case .percent: return 1.0
        case .weight, .length: return 1.0
        }
    }

    /// Minimalny padding dla osi Y - zapewnia margines wokół danych
    func minimalPadding(for kind: MetricKind) -> Double {
        switch kind.unitCategory {
        case .percent: return 1.0
        case .weight, .length: return 0.5
        }
    }

    var insightInput: MetricInsightInput? {
        guard supportsAppleIntelligence, let latest = chartSamples.last else { return nil }
        return MetricInsightInput(
            userName: userName.isEmpty ? nil : userName,
            metricTitle: kind.englishTitle,
            latestValueText: valueString(latest.value),
            timeframeLabel: timeframeLabel,
            sampleCount: chartSamples.count,
            delta7DaysText: deltaText(days: 7, in: chartSamples),
            delta30DaysText: deltaText(days: 30, in: chartSamples),
            goalStatusText: goalStatusText
        )
    }

    var goalStatusText: String? {
        guard let goal = currentGoal, let latest = samples.last else { return nil }
        if goal.isAchieved(currentValue: latest.value) {
            return "Goal reached"
        }
        let remaining = displayValue(abs(goal.remainingToGoal(currentValue: latest.value)))
        let unit = kind.unitSymbol(unitsSystem: unitsSystem)
        return String(format: "%.1f %@ away from goal", remaining, unit)
    }

    var goalForecastText: String? {
        guard let goal = currentGoal,
              let latest = chartSamples.last,
              let trend = trendlineSegment else { return nil }

        if goal.isAchieved(currentValue: latest.value) {
            return "Goal already achieved."
        }

        let slope = (trend.endValue - trend.startValue) / trend.endDate.timeIntervalSince(trend.startDate)
        guard slope.isFinite, slope != 0 else { return nil }

        let latestValue = displayValue(latest.value)
        let targetValue = displayValue(goal.targetValue)

        let movingTowardGoal: Bool
        let remaining: Double
        switch goal.direction {
        case .increase:
            movingTowardGoal = slope > 0
            remaining = targetValue - latestValue
        case .decrease:
            movingTowardGoal = slope < 0
            remaining = latestValue - targetValue
        }

        guard movingTowardGoal, remaining > 0 else { return nil }

        let seconds = remaining / abs(slope)
        guard seconds.isFinite, seconds > 0 else { return nil }

        let predictedDate = latest.date.addingTimeInterval(seconds)
        if predictedDate.timeIntervalSince(latest.date) > 60 * 60 * 24 * 365 * 5 {
            return nil
        }

        let formatted = predictedDate.formatted(date: .abbreviated, time: .omitted)
        return AppLocalization.string("metric.goal.projected.date", formatted)
    }

    func baselineValue(for goal: MetricGoal) -> Double {
        guard !samples.isEmpty else { return latestSampleValue ?? goal.targetValue }
        let sorted = samples.sorted { $0.date < $1.date }
        if let baseline = sorted.last(where: { $0.date <= goal.createdDate }) {
            return baseline.value
        }
        return sorted.first?.value ?? (latestSampleValue ?? goal.targetValue)
    }

    var latestSampleValue: Double? {
        samples.last?.value
    }

    var timeframeLabel: String {
        switch timeframe {
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        case .threeMonths: return "Last 90 days"
        case .year: return "Last year"
        case .all: return "All time"
        }
    }

    func deltaText(days: Int, in source: [MetricSample]) -> String? {
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return nil }
        let window = source.filter { $0.date >= start }
        guard let first = window.first, let last = window.last, first.persistentModelID != last.persistentModelID else {
            return nil
        }
        let delta = displayValue(last.value) - displayValue(first.value)
        let unit = kind.unitSymbol(unitsSystem: unitsSystem)
        return String(format: "%+.1f %@", delta, unit)
    }

    @MainActor
    func loadInsightIfNeeded() async {
        guard let input = insightInput else {
            detailedInsight = nil
            isLoadingInsight = false
            return
        }

        isLoadingInsight = true
        let generated = await MetricInsightService.shared.generateInsight(for: input)
        let baseText = generated?.detailedText ?? ""
        if let forecast = goalForecastText, !forecast.isEmpty {
            let combined = [baseText, forecast]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " ")
            detailedInsight = combined.isEmpty ? forecast : combined
        } else {
            detailedInsight = baseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : baseText
        }
        isLoadingInsight = false
    }

    // MARK: - Data Management
    
    /// Dodaje nową próbkę do bazy danych
    func add(date: Date, value: Double) {
        let sample = MetricSample(kind: kind, value: value, date: date)
        context.insert(sample)
        NotificationManager.shared.recordMeasurement(date: date)
        if let goal = currentGoal, goal.isAchieved(currentValue: value) {
            NotificationManager.shared.sendGoalAchievedNotification(
                kind: kind,
                goalCreatedDate: goal.createdDate,
                goalValue: goal.targetValue
            )
        }
        ReviewRequestManager.recordMetricEntryAdded(count: 1)
        // SwiftData automatycznie zapisuje zmiany
    }

    /// Otwiera sheet edycji próbki
    func edit(sample: MetricSample) {
        editingSample = sample
    }

    /// Usuwa próbkę z bazy danych
    func delete(sample: MetricSample) {
        context.delete(sample)
    }
    
    /// Ustawia lub aktualizuje cel dla metryki
    func setGoal(targetValue: Double, direction: MetricGoal.Direction) {
        if let existing = currentGoal {
            // Aktualizuj istniejący cel
            existing.targetValue = targetValue
            existing.direction = direction
        } else {
            // Utwórz nowy cel
            let goal = MetricGoal(kind: kind, targetValue: targetValue, direction: direction)
            context.insert(goal)
        }
    }
    
    /// Usuwa cel z bazy danych
    func deleteGoal() {
        if let goal = currentGoal {
            context.delete(goal)
        }
    }
}

@available(iOS 16.0, *)
struct MetricChartAXDescriptor: AXChartDescriptorRepresentable {
    let descriptor: AXChartDescriptor

    func makeChartDescriptor() -> AXChartDescriptor {
        descriptor
    }
}

struct MetricPhotosRow: View {
    let photos: [PhotoEntry]
    @State private var availableWidth: CGFloat = 0

    private let spacing: CGFloat = 8

    private var side: CGFloat {
        let totalSpacing = spacing * 2
        let width = availableWidth > 0 ? availableWidth : 0
        let raw = (width - totalSpacing) / 3
        return max(floor(raw), 86)
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(side), spacing: spacing), count: 3),
            spacing: spacing
        ) {
            ForEach(photos) { photo in
                DownsampledImageView(
                    imageData: photo.imageData,
                    targetSize: CGSize(width: side, height: side),
                    contentMode: .fill,
                    cornerRadius: 12,
                    showsProgress: false,
                    cacheID: String(describing: photo.id)
                )
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(height: {
            let rows = max(1, Int(ceil(Double(photos.count) / 3.0)))
            return CGFloat(rows) * side + CGFloat(max(rows - 1, 0)) * spacing
        }())
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { availableWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newValue in
                        availableWidth = newValue
                    }
            }
        )
    }
}

struct GoalProgressView: View {
    let goal: MetricGoal
    let latest: MetricSample
    let baselineValue: Double
    let format: (Double) -> String

    var body: some View {
        let currentVal = latest.value
        let goalVal = goal.targetValue
        let isAchieved = goal.isAchieved(currentValue: currentVal)
        let progress: Double
        switch goal.direction {
        case .increase:
            let denominator = goalVal - baselineValue
            let raw = denominator == 0 ? (isAchieved ? 1.0 : 0.0) : (currentVal - baselineValue) / denominator
            progress = min(max(raw, 0.0), 1.0)
        case .decrease:
            let denominator = baselineValue - goalVal
            let raw = denominator == 0 ? (isAchieved ? 1.0 : 0.0) : (baselineValue - currentVal) / denominator
            progress = min(max(raw, 0.0), 1.0)
        }
        return ProgressViewCard(
            isAchieved: isAchieved,
            progress: progress,
            percentage: Int(progress * 100),
            currentValueString: format(currentVal),
            goalValueString: format(goalVal),
            directionUp: goal.direction == .increase
        )
    }
}

struct ProgressViewCard: View {
    let isAchieved: Bool
    let progress: Double
    let percentage: Int
    let currentValueString: String
    let goalValueString: String
    let directionUp: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(AppLocalization.string("Progress"))
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(percentage)%")
                    .font(AppTypography.bodyEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(isAchieved ? Color(hex: "#22C55E") : Color(hex: "#FCA311"))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: isAchieved ? [
                                    Color(hex: "#22C55E"),
                                    Color(hex: "#22C55E").opacity(0.8)
                                ] : [
                                    Color(hex: "#FCA311"),
                                    Color(hex: "#FCA311").opacity(0.8)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * max(0, min(1, progress)))
                }
            }
            .frame(height: 8)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.string("Current"))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                    Text(currentValueString)
                        .font(AppTypography.captionEmphasis)
                        .monospacedDigit()
                }

                Spacer()

                Image(systemName: directionUp ? "arrow.up" : "arrow.down")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(AppLocalization.string("Goal"))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                    Text(goalValueString)
                        .font(AppTypography.captionEmphasis)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.string("Progress"))
        .accessibilityValue("\(percentage)%")
        .accessibilityHint(AppLocalization.string("accessibility.progress.hint", currentValueString, goalValueString))
    }
}

// MARK: - Add Metric Sample View

/// **AddMetricSampleView**
/// Sheet do dodawania nowej próbki metryki.
///
/// **Funkcje:**
/// - Wybór daty i czasu pomiaru
/// - Wprowadzanie wartości w odpowiednich jednostkach (metric/imperial)
/// - Walidacja wartości procentowych (0-100)
/// - Automatyczna konwersja jednostek przed zapisem
struct AddMetricSampleView: View {
    let kind: MetricKind
    var onAdd: (Date, Double) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var date: Date = .now
    @State private var displayValue: Double

    @AppStorage("unitsSystem") private var unitsSystem: String = "metric"

    init(kind: MetricKind, defaultMetricValue: Double? = nil, onAdd: @escaping (Date, Double) -> Void) {
        self.kind = kind
        self.onAdd = onAdd
        
        // Konwertuj domyślną wartość na jednostki wyświetlania
        let units = UserDefaults.standard.string(forKey: "unitsSystem") ?? "metric"
        if let metric = defaultMetricValue {
            _displayValue = State(initialValue: kind.valueForDisplay(fromMetric: metric, unitsSystem: units))
        } else {
            _displayValue = State(initialValue: 0)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground(topHeight: 220)
                Form {
                    Section(AppLocalization.string("Value")) {
                        HStack {
                            TextField(AppLocalization.string("Value"), value: $displayValue, format: .number)
                                .keyboardType(.decimalPad)
                                .font(.body.monospacedDigit())
                            Text(kind.unitSymbol(unitsSystem: unitsSystem))
                                .foregroundStyle(.secondary)
                        }

                        // Walidacja dla procentów
                        if kind.unitCategory == .percent {
                            Text(AppLocalization.string("Enter value in 0–100 range"))
                                .font(AppTypography.micro)
                                .foregroundStyle(.secondary)
                        }

                        DatePicker(AppLocalization.string("Date"), selection: $date, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(AppLocalization.string("metric.add.title", kind.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Add")) {
                        Haptics.light()
                        // Konwersja z jednostek wyświetlanych na bazowe (metryczne)
                        let metric = kind.valueToMetric(fromDisplay: displayValue, unitsSystem: unitsSystem)
                        onAdd(date, metric)
                        dismiss()
                    }
                    // Disable button dla nieprawidłowych wartości procentowych
                    .disabled(kind.unitCategory == .percent && (displayValue < 0 || displayValue > 100))
                }
            }
        }
    }
}

// MARK: - Edit Metric Sample View

/// **EditMetricSampleView**
/// Sheet do edycji istniejącej próbki metryki.
///
/// **Funkcje:**
/// - Modyfikacja daty i czasu pomiaru
/// - Zmiana wartości w odpowiednich jednostkach
/// - Walidacja wartości procentowych
/// - Bezpośrednia aktualizacja obiektu SwiftData
struct EditMetricSampleView: View {
    let kind: MetricKind
    let sample: MetricSample

    @Environment(\.dismiss) private var dismiss
    @AppStorage("unitsSystem") private var unitsSystem: String = "metric"

    @State private var date: Date
    @State private var displayValue: Double

    init(kind: MetricKind, sample: MetricSample) {
        self.kind = kind
        self.sample = sample
        
        // Inicjalizacja stanu z istniejących wartości
        _date = State(initialValue: sample.date)
        _displayValue = State(
            initialValue: kind.valueForDisplay(
                fromMetric: sample.value,
                unitsSystem: UserDefaults.standard.string(forKey: "unitsSystem") ?? "metric"
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalization.string("Value")) {
                    HStack {
                        TextField(AppLocalization.string("Value"), value: $displayValue, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.body.monospacedDigit())
                        Text(kind.unitSymbol(unitsSystem: unitsSystem))
                            .foregroundStyle(.secondary)
                    }

                    if kind.unitCategory == .percent {
                        Text(AppLocalization.string("Enter value in 0–100 range"))
                            .font(AppTypography.micro)
                            .foregroundStyle(.secondary)
                    }

                    DatePicker(AppLocalization.string("Date"), selection: $date, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle(AppLocalization.string("metric.edit.title", kind.title))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Save")) {
                        // Konwersja i bezpośrednia aktualizacja próbki SwiftData
                        let metric = kind.valueToMetric(fromDisplay: displayValue, unitsSystem: unitsSystem)
                        sample.value = metric
                        sample.date = date
                        dismiss()
                    }
                    .disabled(kind.unitCategory == .percent && (displayValue < 0 || displayValue > 100))
                }
            }
        }
    }
}

// MARK: - Set Goal View

/// **SetGoalView**
/// Sheet do ustawiania lub aktualizacji celu dla metryki.
///
/// **Funkcje:**
/// - Ustawianie nowego celu
/// - Wybór kierunku celu (increase/decrease)
/// - Aktualizacja istniejącego celu
/// - Walidacja wartości procentowych
/// - Pomocny opis funkcjonalności celów
///
/// **UI:**
/// - Tytuł zmienia się w zależności czy cel istnieje
/// - Przycisk potwierdzenia również się dostosowuje
struct SetGoalView: View {
    let kind: MetricKind
    let currentGoal: MetricGoal?
    var onSet: (Double, MetricGoal.Direction) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @AppStorage("unitsSystem") private var unitsSystem: String = "metric"
    
    @State private var displayValue: Double
    @State private var direction: MetricGoal.Direction
    
    init(kind: MetricKind, currentGoal: MetricGoal?, onSet: @escaping (Double, MetricGoal.Direction) -> Void) {
        self.kind = kind
        self.currentGoal = currentGoal
        self.onSet = onSet
        
        // Załaduj istniejący cel lub zacznij od zera
        let units = UserDefaults.standard.string(forKey: "unitsSystem") ?? "metric"
        if let goal = currentGoal {
            _displayValue = State(initialValue: kind.valueForDisplay(fromMetric: goal.targetValue, unitsSystem: units))
            _direction = State(initialValue: goal.direction)
        } else {
            _displayValue = State(initialValue: 0)
            // Domyślny kierunek zależny od typu metryki
            _direction = State(initialValue: SetGoalView.defaultDirection(for: kind))
        }
    }
    
    /// Określa domyślny kierunek celu dla danej metryki
    private static func defaultDirection(for kind: MetricKind) -> MetricGoal.Direction {
        switch kind {
        case .weight, .bodyFat, .waist, .neck, .bust, .chest, .hips, .leftThigh, .rightThigh, .leftCalf, .rightCalf:
            return .decrease  // Zwykle chcemy zmniejszyć
        case .height, .leanBodyMass, .shoulders, .leftBicep, .rightBicep, .leftForearm, .rightForearm:
            return .increase  // Zwykle chcemy zwiększyć
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Wybór kierunku celu
                Section {
                    Picker(AppLocalization.string("Goal type"), selection: $direction) {
                        Label(AppLocalization.string("Decrease"), systemImage: "arrow.down")
                            .tag(MetricGoal.Direction.decrease)
                        Label(AppLocalization.string("Increase"), systemImage: "arrow.up")
                            .tag(MetricGoal.Direction.increase)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(AppLocalization.string("Direction"))
                } footer: {
                    Text(AppLocalization.string("Choose whether you want to increase or decrease this metric."))
                }
                
                // Wartość celu
                Section {
                    HStack {
                        TextField(AppLocalization.string("Goal Value"), value: $displayValue, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.body.monospacedDigit())
                        Text(kind.unitSymbol(unitsSystem: unitsSystem))
                            .foregroundStyle(.secondary)
                    }
                    
                    if kind.unitCategory == .percent {
                        Text(AppLocalization.string("Enter value in 0–100 range"))
                            .font(AppTypography.micro)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(AppLocalization.string("Target Value"))
                } footer: {
                    Text(AppLocalization.string("metric.goal.set.help", kind.title.lowercased()))
                }
            }
            .navigationTitle(currentGoal == nil ? "Set Goal" : "Update Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(currentGoal == nil ? "Set" : "Update") {
                        let metric = kind.valueToMetric(fromDisplay: displayValue, unitsSystem: unitsSystem)
                        onSet(metric, direction)
                        dismiss()
                    }
                    .disabled(kind.unitCategory == .percent && (displayValue < 0 || displayValue > 100))
                }
            }
        }
    }
}
