import SwiftUI

/// Rząd z pojedynczym snapshotem metryki (tryb wyświetlania)
struct MetricSnapshotRow: View {
    let snapshot: MetricValueSnapshot
    @AppStorage("unitsSystem") private var unitsSystem: String = "metric"
    
    var body: some View {
        HStack {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                if let kind = snapshot.kind {
                    Text(kind.title)
                        .font(AppTypography.bodyEmphasis)
                } else {
                    Text(snapshot.metricRawValue)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Text("\(displayValue.formatted(.number.precision(.fractionLength(1)))) \(displayUnit)")
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var isMetricStored: Bool {
        guard let kind = snapshot.kind else { return false }
        return snapshot.unit == kind.unitSymbol(unitsSystem: "metric")
    }

    private var displayValue: Double {
        guard let kind = snapshot.kind, isMetricStored else { return snapshot.value }
        return kind.valueForDisplay(fromMetric: snapshot.value, unitsSystem: unitsSystem)
    }

    private var displayUnit: String {
        guard let kind = snapshot.kind, isMetricStored else { return snapshot.unit }
        return kind.unitSymbol(unitsSystem: unitsSystem)
    }
}

/// Edytor snapshotów metryk (tryb edycji)
struct MetricSnapshotsEditor: View {
    @Binding var snapshots: [MetricValueSnapshot]
    let metricsStore: ActiveMetricsStore
    
    @State private var showAddMetric = false
    
    var body: some View {
        VStack(spacing: 12) {
            if snapshots.isEmpty {
                emptyStateView
            } else {
                snapshotsList
            }
            
            addMetricButton
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $showAddMetric) {
            AddMetricSnapshotView(
                metricsStore: metricsStore,
                onAdd: { newSnapshot in
                    snapshots.append(newSnapshot)
                }
            )
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(.secondary)
            Text(AppLocalization.string("No metrics recorded"))
                .font(AppTypography.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    private var snapshotsList: some View {
        ForEach(snapshots) { snapshot in
            EditableMetricRow(
                snapshot: snapshot,
                onDelete: {
                    snapshots.removeAll { $0.id == snapshot.id }
                },
                onUpdate: { updated in
                    if let index = snapshots.firstIndex(where: { $0.id == snapshot.id }) {
                        snapshots[index] = updated
                    }
                }
            )
        }
    }
    
    private var addMetricButton: some View {
        Button {
            showAddMetric = true
        } label: {
            Label(AppLocalization.string("Add Metric"), systemImage: "plus.circle.fill")
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.appAccent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// Rząd z edytowalną metryką
struct EditableMetricRow: View {
    let snapshot: MetricValueSnapshot
    let onDelete: () -> Void
    let onUpdate: (MetricValueSnapshot) -> Void
    
    @State private var editedValue: String
    
    init(
        snapshot: MetricValueSnapshot,
        onDelete: @escaping () -> Void,
        onUpdate: @escaping (MetricValueSnapshot) -> Void
    ) {
        self.snapshot = snapshot
        self.onDelete = onDelete
        self.onUpdate = onUpdate
        _editedValue = State(initialValue: String(format: "%.1f", snapshot.value))
    }
    
    var body: some View {
        HStack(spacing: 12) {
            metricName
            Spacer()
            valueEditor
            deleteButton
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var metricName: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let kind = snapshot.kind {
                Text(kind.title)
                    .font(AppTypography.bodyEmphasis)
            } else {
                Text(snapshot.metricRawValue)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var valueEditor: some View {
        HStack(spacing: 4) {
            TextField(AppLocalization.string("Value"), text: $editedValue)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .frame(width: 80)
                .onChange(of: editedValue) { _, newValue in
                    updateValue(newValue)
                }
            
            Text(snapshot.unit)
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var deleteButton: some View {
        Button(role: .destructive, action: onDelete) {
            Image(systemName: "trash.fill")
                .foregroundStyle(.red)
        }
    }
    
    private func updateValue(_ newValue: String) {
        guard let doubleValue = Double(newValue) else { return }
        
        let updated = MetricValueSnapshot(
            id: snapshot.id,
            metricRawValue: snapshot.metricRawValue,
            value: doubleValue,
            unit: snapshot.unit
        )
        onUpdate(updated)
    }
}

#Preview("Metric Snapshot Row") {
    MetricSnapshotRow(
        snapshot: MetricValueSnapshot(
            kind: .weight,
            value: 75.5,
            unit: "kg"
        )
    )
    .padding()
}

#Preview("Editable Metric Row") {
    EditableMetricRow(
        snapshot: MetricValueSnapshot(
            kind: .waist,
            value: 85.0,
            unit: "cm"
        ),
        onDelete: {},
        onUpdate: { _ in }
    )
    .padding()
}
