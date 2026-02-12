import SwiftUI

/// Arkusz do dodawania nowego snapshotu metryki
struct AddMetricSnapshotView: View {
    @Environment(\.dismiss) private var dismiss
    
    let metricsStore: ActiveMetricsStore
    let onAdd: (MetricValueSnapshot) -> Void
    
    @State private var selectedMetricKind: MetricKind?
    @State private var value: String = ""
    @AppStorage("units_system") private var unitsSystem = "metric"
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground(topHeight: 200, tint: Color.cyan.opacity(0.16))
                Form {
                    metricSection
                    
                    if selectedMetricKind != nil {
                        valueSection
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(AppLocalization.string("Add Metric"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(AppLocalization.string("Add")) {
                        addMetric()
                    }
                    .disabled(!canAdd)
                }
            }
        }
    }
    
    private var metricSection: some View {
        Section(AppLocalization.string("Metric")) {
            Picker(AppLocalization.string("Select Metric"), selection: $selectedMetricKind) {
                Text(AppLocalization.string("Choose...")).tag(nil as MetricKind?)
                ForEach(metricsStore.activeKinds, id: \.self) { kind in
                    Text(kind.title).tag(kind as MetricKind?)
                }
            }
        }
    }
    
    private var valueSection: some View {
        Section(AppLocalization.string("Value")) {
            HStack {
                TextField(AppLocalization.string("Value"), text: $value)
                    .keyboardType(.decimalPad)
                
                if let kind = selectedMetricKind {
                    Text(kind.unitSymbol(unitsSystem: unitsSystem))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private var canAdd: Bool {
        guard selectedMetricKind != nil,
              let doubleValue = Double(value),
              doubleValue > 0 else {
            return false
        }
        return true
    }
    
    private func addMetric() {
        guard let kind = selectedMetricKind,
              let doubleValue = Double(value) else {
            return
        }
        
        let snapshot = MetricValueSnapshot(
            kind: kind,
            value: doubleValue,
            unit: kind.unitSymbol(unitsSystem: unitsSystem)
        )
        
        onAdd(snapshot)
        dismiss()
    }
}

#Preview {
    let metricsStore = ActiveMetricsStore()
    
    return AddMetricSnapshotView(
        metricsStore: metricsStore,
        onAdd: { _ in }
    )
}
