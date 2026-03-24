import SwiftUI
import WatchKit

struct QuickAddView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityManager
    @State private var values: [WatchMetricKind: Double] = [:]
    @State private var selectedMetric: WatchMetricKind?
    @State private var isSaving = false
    @State private var showSaved = false
    @State private var crownValue: Double = 0

    private var activeMetrics: [WatchMetricKind] {
        connectivity.activeMetrics
    }

    private var isMetric: Bool {
        connectivity.unitsSystem != "imperial"
    }

    var body: some View {
        if activeMetrics.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "No Metrics", table: "Watch"),
                      systemImage: "ruler")
            } description: {
                Text(String(localized: "Enable metrics on your iPhone to see them here.", table: "Watch"))
                    .font(.caption2)
            }
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(activeMetrics) { kind in
                        QuickAddRowView(
                            kind: kind,
                            isMetric: isMetric,
                            displayValue: valueBinding(for: kind),
                            isSelected: selectedMetric == kind
                        )
                        .onTapGesture {
                            selectedMetric = kind
                            crownValue = values[kind] ?? defaultDisplayValue(for: kind)
                        }
                    }

                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else if showSaved {
                            Label(String(localized: "Saved", table: "Watch"),
                                  systemImage: "checkmark.circle.fill")
                        } else {
                            Label(String(localized: "Save", table: "Watch"),
                                  systemImage: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(showSaved ? .watchGreen : .watchAccent)
                    .disabled(isSaving || showSaved)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 4)
            }
            .focusable()
            .digitalCrownRotation(
                $crownValue,
                from: selectedMetric?.displayRange.lowerBound ?? 0,
                through: selectedMetric?.displayRange.upperBound ?? 300,
                by: selectedMetric?.crownStep ?? 0.1,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            .onChange(of: crownValue) { _, newValue in
                guard let kind = selectedMetric else { return }
                values[kind] = newValue
            }
            .onAppear {
                initializeValues()
                selectedMetric = activeMetrics.first
                if let first = activeMetrics.first {
                    crownValue = values[first] ?? defaultDisplayValue(for: first)
                }
            }
        }
    }

    // MARK: - Helpers

    private func valueBinding(for kind: WatchMetricKind) -> Binding<Double> {
        Binding(
            get: { values[kind] ?? defaultDisplayValue(for: kind) },
            set: { values[kind] = $0 }
        )
    }

    private func defaultDisplayValue(for kind: WatchMetricKind) -> Double {
        guard let data = WatchMetricData.load(for: kind),
              let val = data.latestDisplayValue(for: kind) else {
            return kind.unitCategory == .weight ? 70.0 : (kind.unitCategory == .percent ? 20.0 : 80.0)
        }
        return (val * 10).rounded() / 10
    }

    private func initializeValues() {
        for kind in activeMetrics {
            if values[kind] == nil {
                values[kind] = defaultDisplayValue(for: kind)
            }
        }
    }

    private func save() {
        isSaving = true
        let date = Date()

        var entries: [(kind: String, metricValue: Double)] = []
        for kind in activeMetrics {
            let displayVal = values[kind] ?? defaultDisplayValue(for: kind)
            let metricVal = kind.metricValue(fromDisplay: displayVal, isMetric: isMetric)
            entries.append((kind: kind.rawValue, metricValue: metricVal))
        }

        // Write to HealthKit for supported metrics
        Task {
            for entry in entries {
                guard let kind = WatchMetricKind(rawValue: entry.kind), kind.isHealthKitSynced else { continue }
                try? await WatchHealthKitWriter.shared.save(kind: kind, metricValue: entry.metricValue, date: date)
            }
        }

        // Send to iPhone via WatchConnectivity
        connectivity.sendMeasurements(entries: entries, date: date)

        WKInterfaceDevice.current().play(.success)
        isSaving = false
        showSaved = true

        Task {
            try? await Task.sleep(for: .seconds(2))
            showSaved = false
        }
    }
}
