import SwiftUI
import SwiftData

struct CustomMetricEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var metricsStore: ActiveMetricsStore

    /// Nil = tryb tworzenia nowej metryki, nie-nil = tryb edycji
    var existingDefinition: CustomMetricDefinition?

    @State private var name: String = ""
    @State private var unitLabel: String = "kg"
    @State private var sfSymbolName: String = "circle.dotted"
    @State private var minValueText: String = ""
    @State private var maxValueText: String = ""
    @State private var trendDirection: TrendDirection = .increase
    @State private var showRangeFields: Bool = false
    @State private var showIconPicker: Bool = false

    private var isEditing: Bool { existingDefinition != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Predefined Units

    struct UnitCategory: Identifiable {
        let id = UUID()
        let name: String
        let units: [String]
    }

    static let unitCategories: [UnitCategory] = [
        UnitCategory(name: "Weight", units: ["kg", "lb", "g", "oz", "st"]),
        UnitCategory(name: "Length", units: ["cm", "mm", "in", "ft", "m"]),
        UnitCategory(name: "Volume", units: ["ml", "l", "fl oz", "cups"]),
        UnitCategory(name: "Energy", units: ["kcal", "kJ"]),
        UnitCategory(name: "Count", units: ["reps", "steps", "times", "count"]),
        UnitCategory(name: "Percentage", units: ["%"]),
        UnitCategory(name: "Time", units: ["min", "hrs", "sec"]),
        UnitCategory(name: "Other", units: ["bpm", "mg/dL", "mmHg", "IU"]),
    ]

    static var allUnits: [String] {
        unitCategories.flatMap(\.units)
    }

    enum TrendDirection: String, CaseIterable {
        case increase
        case decrease
        case neutral

        var label: String {
            switch self {
            case .increase: return AppLocalization.string("custom.metric.trend.increase")
            case .decrease: return AppLocalization.string("custom.metric.trend.decrease")
            case .neutral:  return AppLocalization.string("custom.metric.trend.neutral")
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Basic Info
                Section {
                    TextField(AppLocalization.string("custom.metric.name.placeholder"), text: $name)
                        .onChange(of: name) { _, newValue in
                            if newValue.count > 40 {
                                name = String(newValue.prefix(40))
                            }
                        }

                    Picker(AppLocalization.string("custom.metric.unit.placeholder"), selection: $unitLabel) {
                        ForEach(Self.unitCategories) { category in
                            Section(category.name) {
                                ForEach(category.units, id: \.self) { unit in
                                    Text(unit).tag(unit)
                                }
                            }
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text(AppLocalization.string("custom.metric.section.basic"))
                }

                // MARK: - Icon
                Section {
                    Button {
                        showIconPicker = true
                    } label: {
                        HStack {
                            Text(AppLocalization.string("custom.metric.icon.label"))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: sfSymbolName)
                                .font(.title3)
                                .foregroundStyle(Color.appAccent)
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.appAccent.opacity(0.15))
                                )
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text(AppLocalization.string("custom.metric.section.icon"))
                }

                // MARK: - Trend Direction
                Section {
                    Picker(AppLocalization.string("custom.metric.trend.label"), selection: $trendDirection) {
                        ForEach(TrendDirection.allCases, id: \.self) { direction in
                            Text(direction.label).tag(direction)
                        }
                    }
                } header: {
                    Text(AppLocalization.string("custom.metric.section.trend"))
                } footer: {
                    Text(AppLocalization.string("custom.metric.trend.footer"))
                }

                // MARK: - Value Range (Optional)
                Section {
                    DisclosureGroup(
                        AppLocalization.string("custom.metric.range.label"),
                        isExpanded: $showRangeFields
                    ) {
                        HStack {
                            Text(AppLocalization.string("custom.metric.range.min"))
                            Spacer()
                            TextField("0", text: $minValueText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        HStack {
                            Text(AppLocalization.string("custom.metric.range.max"))
                            Spacer()
                            TextField("1000", text: $maxValueText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                    }
                } header: {
                    Text(AppLocalization.string("custom.metric.section.range"))
                } footer: {
                    Text(AppLocalization.string("custom.metric.range.footer"))
                }

                // MARK: - Delete (Edit mode only)
                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            deleteMetric()
                        } label: {
                            HStack {
                                Spacer()
                                Text(AppLocalization.string("custom.metric.delete"))
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing
                             ? AppLocalization.string("custom.metric.edit.title")
                             : AppLocalization.string("custom.metric.create.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Save")) { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showIconPicker) {
                SFSymbolPickerView(selectedSymbol: $sfSymbolName)
            }
            .onAppear {
                if let def = existingDefinition {
                    name = def.name
                    unitLabel = def.unitLabel
                    sfSymbolName = def.sfSymbolName
                    minValueText = def.minValue.map { String($0) } ?? ""
                    maxValueText = def.maxValue.map { String($0) } ?? ""
                    trendDirection = def.favorsDecrease ? .decrease : .neutral
                    showRangeFields = def.minValue != nil || def.maxValue != nil
                }
            }
        }
    }

    // MARK: - Actions

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedUnit = unitLabel
        guard !trimmedName.isEmpty else { return }

        let minVal = Double(minValueText)
        let maxVal = Double(maxValueText)
        let favorsDecrease = trendDirection == .decrease

        if let def = existingDefinition {
            def.name = trimmedName
            def.unitLabel = trimmedUnit
            def.sfSymbolName = sfSymbolName
            def.minValue = minVal
            def.maxValue = maxVal
            def.favorsDecrease = favorsDecrease
        } else {
            let existing = (try? modelContext.fetchCount(FetchDescriptor<CustomMetricDefinition>())) ?? 0
            let definition = CustomMetricDefinition(
                name: trimmedName,
                unitLabel: trimmedUnit,
                sfSymbolName: sfSymbolName,
                minValue: minVal,
                maxValue: maxVal,
                favorsDecrease: favorsDecrease,
                sortOrder: existing
            )
            modelContext.insert(definition)
            metricsStore.setCustomEnabled(true, for: definition.identifier)
        }

        Haptics.light()
        dismiss()
    }

    private func deleteMetric() {
        guard let def = existingDefinition else { return }
        metricsStore.removeCustomMetric(def.identifier)
        modelContext.delete(def)
        Haptics.medium()
        dismiss()
    }
}
