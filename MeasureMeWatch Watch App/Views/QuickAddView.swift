import SwiftUI
import WatchKit

struct QuickAddView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityManager
    @State private var values: [WatchMetricKind: Double] = [:]
    @State private var editedMetrics: Set<WatchMetricKind> = []
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
            .accessibilityLabel(String(localized: "No Metrics", table: "Watch"))
            .accessibilityValue(String(localized: "Enable metrics on your iPhone to see them here.", table: "Watch"))
        } else {
            List {
                ForEach(activeMetrics) { kind in
                    Button {
                        selectMetric(kind)
                    } label: {
                        QuickAddRowView(
                            kind: kind,
                            isMetric: isMetric,
                            displayValue: values[kind] ?? defaultDisplayValue(for: kind),
                            isSelected: selectedMetric == kind
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(kind.displayName)
                    .accessibilityValue(kind.formattedDisplayValue(values[kind] ?? defaultDisplayValue(for: kind), isMetric: isMetric))
                    .accessibilityHint(quickAddHint(for: kind))
                    .accessibilityAddTraits(selectedMetric == kind ? .isSelected : [])
                }

                Button {
                    save()
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView()
                        } else if showSaved {
                            Label(String(localized: "Saved", table: "Watch"),
                                  systemImage: "checkmark.circle.fill")
                        } else {
                            Label(String(localized: "Save", table: "Watch"),
                                  systemImage: "square.and.arrow.down")
                        }
                        Spacer()
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(showSaved ? Color.watchGreen : Color.watchAccent)
                )
                .foregroundStyle(.black)
                .fontWeight(.semibold)
                .disabled(isSaving || showSaved)
                .accessibilityLabel(showSaved
                                    ? String(localized: "Saved", table: "Watch")
                                    : String(localized: "Save", table: "Watch"))
                .accessibilityHint(saveButtonHint)
            }
            .listStyle(.plain)
            .navigationTitle(String(localized: "Add", table: "Watch"))
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
                editedMetrics.insert(kind)
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

    private func selectMetric(_ kind: WatchMetricKind) {
        selectedMetric = kind
        crownValue = values[kind] ?? defaultDisplayValue(for: kind)
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
        let kindsToSave = metricsToSave()
        for kind in kindsToSave {
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

    private func metricsToSave() -> [WatchMetricKind] {
        if !editedMetrics.isEmpty {
            return activeMetrics.filter { editedMetrics.contains($0) }
        }
        if let selectedMetric {
            return [selectedMetric]
        }
        return activeMetrics.first.map { [$0] } ?? []
    }

    private func quickAddHint(for kind: WatchMetricKind) -> String {
        if selectedMetric == kind {
            return watchLocalized("Selected. Rotate Digital Crown to adjust this metric.", "Wybrano. Obróć Digital Crown, aby zmienić tę metrykę.")
        }
        return watchLocalized("Selects this metric for Digital Crown editing.", "Wybiera tę metrykę do edycji za pomocą Digital Crown.")
    }

    private var saveButtonHint: String {
        let count = metricsToSave().count
        if count > 1 {
            return String(format: watchLocalized("Saves %d edited metrics", "Zapisuje %d edytowane metryki"), count)
        }
        return watchLocalized("Saves the selected metric", "Zapisuje wybraną metrykę")
    }
}
