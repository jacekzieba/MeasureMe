import SwiftUI
import SwiftData

struct QuickAddSheetView: View {
    let kinds: [MetricKind]
    let latest: [MetricKind: (value: Double, date: Date)]
    let unitsSystem: String
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @AppStorage("isSyncEnabled") private var isSyncEnabled: Bool = false
    @AppStorage("save_unchanged_quick_add") private var saveUnchangedValues: Bool = false
    @AppStorage("settings_open_tracked_measurements") private var settingsOpenTrackedMeasurements: Bool = false

    // One date used for all quick entries
    @State private var date: Date = .now
    // User inputs in display units; nil means “skip”
    @State private var inputs: [MetricKind: Double?] = [:]
    // Tracks which metrics the user has actually edited
    @State private var editedKinds: Set<MetricKind> = []
    @State private var isSaving = false
    @State private var showNoChangesAlert = false
    @FocusState private var focusedKind: MetricKind?
    @State private var rulerBaseValues: [MetricKind: Double] = [:]

    init(
        kinds: [MetricKind],
        latest: [MetricKind: (value: Double, date: Date)],
        unitsSystem: String,
        onSaved: @escaping () -> Void
    ) {
        self.kinds = kinds
        self.latest = latest
        self.unitsSystem = unitsSystem
        self.onSaved = onSaved

        var initial: [MetricKind: Double?] = [:]
        for k in kinds {
            if let last = latest[k]?.value {
                initial[k] = k.valueForDisplay(fromMetric: last, unitsSystem: unitsSystem)
            } else {
                initial[k] = nil
            }
        }
        _inputs = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AppScreenBackground(topHeight: 240)

                if kinds.isEmpty {
                    ContentUnavailableView(
                        "No active measurements",
                        systemImage: "square.and.pencil",
                        description: Text(AppLocalization.string("Enable metrics in the Measurements tab to add values quickly."))
                    )
                    .padding(.horizontal, 20)
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            saveUnchangedCard

                            ForEach(kinds, id: \.self) { kind in
                                row(for: kind)
                            }

                            dateCard
                            trackedMetricsFooter
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 120)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle(AppLocalization.string("Update measurements"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !kinds.isEmpty && focusedKind == nil {
                    saveBar
                }
            }
            .alert(AppLocalization.string("Nothing to save"), isPresented: $showNoChangesAlert) {
                Button(AppLocalization.string("OK"), role: .cancel) { }
            } message: {
                Text(AppLocalization.string("Add at least one value before saving."))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(AppLocalization.string("Done")) {
                        focusedKind = nil
                    }
                }
            }
        }
    }

    // MARK: - Row
    @ViewBuilder
    private func row(for kind: MetricKind) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
                    .scaleEffect(x: kind.shouldMirrorSymbol ? -1 : 1, y: 1)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(Color.appAccent.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)

                    if let summary = lastSummary(for: kind) {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.68))
                    }
                }

                Spacer()

                if let current = inputs[kind] ?? nil {
                    Text(formatted(current, for: kind))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.appAccent.opacity(0.14))
                        )
                }
            }

            RulerSlider(
                value: valueBinding(for: kind),
                range: rulerRange(for: kind),
                step: rulerStep(for: kind)
            )
            .frame(height: 52)

            HStack(spacing: 8) {
                Text(AppLocalization.string("Enter value"))
                    .font(AppTypography.caption)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                TextField(
                    "0.0",
                    value: binding(for: kind),
                    format: .number.precision(.fractionLength(1))
                )
                .focused($focusedKind, equals: kind)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.title3.monospacedDigit().weight(.semibold))
                .frame(minWidth: 72)
                .accessibilityLabel(AppLocalization.string("accessibility.value", kind.title))

                Text(kind.unitSymbol(unitsSystem: unitsSystem))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.26))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(focusedKind == kind ? 0.36 : 0.16), lineWidth: 1)
                    )
            )
        }
        .padding(14)
        .background(cardBackground(cornerRadius: 16))
        .onAppear {
            if rulerBaseValues[kind] == nil {
                rulerBaseValues[kind] = baseValue(for: kind)
            }
        }
    }

    private var saveUnchangedCard: some View {
        Toggle(isOn: $saveUnchangedValues) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalization.string("Save unchanged values"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(AppLocalization.string("When enabled, current values are saved even if unchanged."))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .tint(Color.appAccent)
        .padding(14)
        .background(cardBackground(cornerRadius: 16))
    }

    private var dateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(AppLocalization.string("Measurement time"), systemImage: "calendar.badge.clock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            DatePicker(
                "",
                selection: $date,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .tint(Color.appAccent)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(cardBackground(cornerRadius: 16))
    }

    private var saveBar: some View {
        VStack(spacing: 8) {
            Button {
                if cannotSave {
                    Haptics.error()
                    showNoChangesAlert = true
                } else {
                    Haptics.medium()
                    Task { await saveAll() }
                }
            } label: {
                Group {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(AppLocalization.string("Save Measurements"))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppAccentButtonStyle(cornerRadius: 14))
            .disabled(isSaving)
            .opacity(isSaving ? 0.64 : 1)

            if cannotSave {
                Text(AppLocalization.string("Add at least one valid value to save."))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.thinMaterial)
    }

    private var trackedMetricsFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.string("Tracked metric visibility can be changed in Settings."))
                .font(AppTypography.caption)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openTrackedMetricsSettings()
            } label: {
                HStack(spacing: 6) {
                    Text(AppLocalization.string("Open tracked metrics settings"))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.appAccent)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .padding(14)
        .background(cardBackground(cornerRadius: 16))
    }

    private func cardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
    }

    // MARK: - Helpers

    private func lastSummary(for kind: MetricKind) -> String? {
        guard let last = latest[kind] else { return nil }
        let shown = kind.valueForDisplay(fromMetric: last.value, unitsSystem: unitsSystem)
        let dateText = last.date.formatted(date: .abbreviated, time: .omitted)
        return AppLocalization.string("quickadd.last.summary", formatted(shown, for: kind), dateText)
    }

    private func binding(for kind: MetricKind) -> Binding<Double?> {
        Binding<Double?>(
            get: { inputs[kind] ?? nil },
            set: {
                inputs[kind] = $0
                editedKinds.insert(kind)
                if let value = $0 {
                    rulerBaseValues[kind] = value
                }
            }
        )
    }

    private func valueBinding(for kind: MetricKind) -> Binding<Double> {
        Binding<Double>(
            get: { (inputs[kind] ?? nil) ?? baseValue(for: kind) },
            set: {
                inputs[kind] = $0
                editedKinds.insert(kind)
            }
        )
    }

    private func baseValue(for kind: MetricKind) -> Double {
        if let current = inputs[kind] ?? nil {
            return current
        }
        if let last = latest[kind]?.value {
            return kind.valueForDisplay(fromMetric: last, unitsSystem: unitsSystem)
        }

        switch kind.unitCategory {
        case .percent:
            return 20
        case .weight:
            return unitsSystem == "imperial" ? 170 : 75
        case .length:
            return unitsSystem == "imperial" ? 35 : 90
        }
    }

    private func rulerRange(for kind: MetricKind) -> ClosedRange<Double> {
        let base = rulerBaseValues[kind] ?? baseValue(for: kind)
        let span: Double
        switch kind.unitCategory {
        case .percent:
            span = 20
        case .weight:
            span = unitsSystem == "imperial" ? 66 : 30
        case .length:
            span = unitsSystem == "imperial" ? 20 : 40
        }

        let valid = validRange(for: kind)
        let minValue = max(base - span, valid.lowerBound)
        let maxValue = min(base + span, valid.upperBound)
        return minValue...maxValue
    }

    private func rulerStep(for kind: MetricKind) -> Double {
        switch kind.unitCategory {
        case .percent:
            return 0.1
        case .weight, .length:
            return 0.1
        }
    }

    private func validRange(for kind: MetricKind) -> ClosedRange<Double> {
        switch kind.unitCategory {
        case .percent:
            return 0.1...100
        case .weight:
            return unitsSystem == "imperial" ? 0.1...660 : 0.1...300
        case .length:
            return unitsSystem == "imperial" ? 0.1...100 : 0.1...250
        }
    }

    private func formatted(_ value: Double, for kind: MetricKind) -> String {
        switch kind.unitCategory {
        case .percent:
            return String(format: "%.1f%%", value)
        case .weight, .length:
            return String(format: "%.1f %@", value, kind.unitSymbol(unitsSystem: unitsSystem))
        }
    }

    private var cannotSave: Bool {
        let values = preparedEntries(includeUnchanged: saveUnchangedValues)

        guard !values.isEmpty else { return true }

        return values.contains { kind, value in
            !validRange(for: kind).contains(value)
        }
    }

    private func metricValue(for kind: MetricKind, displayValue: Double) -> Double {
        kind.valueToMetric(fromDisplay: displayValue, unitsSystem: unitsSystem)
    }

    private func saveToHealthKit(kind: MetricKind, metricValue: Double, date: Date) async {
        guard isSyncEnabled, kind.isHealthSynced else { return }
        switch kind {
        case .weight:
            try? await HealthKitManager.shared.saveWeight(kilograms: metricValue, date: date)
        case .height:
            try? await HealthKitManager.shared.saveHeight(centimeters: metricValue, date: date)
        case .bodyFat:
            try? await HealthKitManager.shared.saveBodyFatPercentage(percent: metricValue, date: date)
        case .leanBodyMass:
            try? await HealthKitManager.shared.saveLeanBodyMass(kilograms: metricValue, date: date)
        case .waist:
            try? await HealthKitManager.shared.saveWaistMeasurement(value: metricValue, date: date)
        default:
            break
        }
    }

    private func saveAll() async {
        guard !isSaving else { return }
        await MainActor.run { isSaving = true }

        let preparedEntries: [(kind: MetricKind, metricValue: Double)] = preparedEntries(includeUnchanged: saveUnchangedValues)
            .map { kind, displayValue in
                (kind: kind, metricValue: metricValue(for: kind, displayValue: displayValue))
            }

        await MainActor.run {
            for entry in preparedEntries {
                let sample = MetricSample(kind: entry.kind, value: entry.metricValue, date: date)
                context.insert(sample)
                NotificationManager.shared.recordMeasurement(date: date)
            }
        }

        await MainActor.run {
            for entry in preparedEntries {
                if let goal = fetchGoal(for: entry.kind), goal.isAchieved(currentValue: entry.metricValue) {
                    NotificationManager.shared.sendGoalAchievedNotification(
                        kind: entry.kind,
                        goalCreatedDate: goal.createdDate,
                        goalValue: goal.targetValue
                    )
                }
            }
        }

        do {
            try await MainActor.run {
                try context.save()
            }
        } catch {
            await MainActor.run {
                isSaving = false
            }
            AppLog.debug("❌ QuickAdd save failed: \(error.localizedDescription)")
            return
        }

        for entry in preparedEntries {
            await saveToHealthKit(kind: entry.kind, metricValue: entry.metricValue, date: date)
        }

        await MainActor.run {
            ReviewRequestManager.recordMetricEntryAdded(count: preparedEntries.count)
            isSaving = false
            Haptics.success()
            onSaved()
            dismiss()
        }
    }

    private func preparedEntries(includeUnchanged: Bool) -> [(MetricKind, Double)] {
        kinds.compactMap { kind -> (MetricKind, Double)? in
            guard let value = inputs[kind] ?? nil else { return nil }
            if includeUnchanged {
                return (kind, value)
            }
            guard editedKinds.contains(kind) else { return nil }
            return (kind, value)
        }
    }

    private func fetchGoal(for kind: MetricKind) -> MetricGoal? {
        let kindValue = kind.rawValue
        let descriptor = FetchDescriptor<MetricGoal>(
            predicate: #Predicate { $0.kindRaw == kindValue }
        )
        return try? context.fetch(descriptor).first
    }

    private func openTrackedMetricsSettings() {
        settingsOpenTrackedMeasurements = true
        router.selectedTab = .settings
        onSaved()
        dismiss()
    }
}

private struct RulerSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    @State private var dragStartValue: Double? = nil
    private let pointsPerStep: CGFloat = 10
    @State private var lastHapticStep: Int? = nil
    private let horizontalInset: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let drawableWidth = max(width - horizontalInset * 2, 1)
            let span = max(range.upperBound - range.lowerBound, 0.0001)
            let ratio = min(max((value - range.lowerBound) / span, 0), 1)
            let indicatorX = horizontalInset + CGFloat(ratio) * drawableWidth

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.26))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )

                let tickCount = max(8, min(40, Int(span / max(step * 5, 1)) + 1))
                ForEach(0..<tickCount, id: \.self) { index in
                    let tickX = horizontalInset + CGFloat(index) * (drawableWidth / CGFloat(max(tickCount - 1, 1)))
                    let isMajor = index.isMultiple(of: 5)
                    Rectangle()
                        .fill(Color.white.opacity(isMajor ? 0.55 : 0.28))
                        .frame(width: 1, height: isMajor ? height * 0.55 : height * 0.32)
                        .position(x: tickX, y: height / 2)
                }

                Rectangle()
                    .fill(Color.appAccent)
                    .frame(width: 2, height: height * 0.70)
                    .offset(x: indicatorX - 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if dragStartValue == nil {
                            dragStartValue = value
                        }
                        let start = dragStartValue ?? value
                        let deltaSteps = Double(gesture.translation.width / pointsPerStep)
                        let rawValue = start + deltaSteps * step
                        let stepped = (rawValue / step).rounded() * step
                        let clamped = min(max(stepped, range.lowerBound), range.upperBound)
                        value = clamped
                        let stepIndex = Int((clamped - range.lowerBound) / step)
                        if lastHapticStep != stepIndex {
                            lastHapticStep = stepIndex
                            Haptics.selection()
                        }
                    }
                    .onEnded { _ in
                        dragStartValue = nil
                        lastHapticStep = nil
                    }
            )
        }
    }
}
