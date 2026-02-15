import SwiftUI

/// Arkusz do dodawania nowego snapshotu metryki
struct AddMetricSnapshotView: View {
    @Environment(\.dismiss) private var dismiss
    
    let metricsStore: ActiveMetricsStore
    let onAdd: (MetricValueSnapshot) -> Void
    
    @State private var selectedMetricKind: MetricKind?
    @State private var value: String = ""
    @AppStorage("units_system") private var unitsSystem = "metric"
    
    @FocusState private var isValueFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground(topHeight: 200, tint: Color.cyan.opacity(0.16))

                ScrollView {
                    VStack(spacing: 16) {
                        // MARK: - Metric picker card
                        AppGlassCard(
                            depth: .floating,
                            tint: Color.cyan.opacity(0.12),
                            contentPadding: 20
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(AppLocalization.string("Metric"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)

                                Picker(AppLocalization.string("Select Metric"), selection: $selectedMetricKind) {
                                    Text(AppLocalization.string("Choose...")).tag(nil as MetricKind?)
                                    ForEach(metricsStore.activeKinds, id: \.self) { kind in
                                        Text(kind.title).tag(kind as MetricKind?)
                                    }
                                }
                            }
                        }

                        // MARK: - Value card (hero)
                        if let kind = selectedMetricKind {
                            AppGlassCard(
                                depth: .floating,
                                tint: Color.cyan.opacity(0.12),
                                contentPadding: 24
                            ) {
                                VStack(spacing: 8) {
                                    HStack(spacing: 4) {
                                        TextField("0", text: $value)
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.trailing)
                                            .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                                            .fixedSize()
                                            .focused($isValueFocused)

                                        Text(kind.unitSymbol(unitsSystem: unitsSystem))
                                            .font(.title.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }

                                    if !isValueFocused {
                                        Text(AppLocalization.string("metric.input.tap_to_edit"))
                                            .font(AppTypography.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 140)
                                .contentShape(Rectangle())
                                .onTapGesture { isValueFocused = true }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
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
