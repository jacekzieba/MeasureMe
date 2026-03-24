import SwiftUI
import SwiftData

struct QuickAddSheetView: View {
    let kinds: [MetricKind]
    let latest: [MetricKind: (value: Double, date: Date)]
    let unitsSystem: String
    var customDefinitions: [CustomMetricDefinition] = []
    var customLatest: [String: (value: Double, date: Date)] = [:]
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var router: AppRouter
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @AppSetting(\.health.isSyncEnabled) private var isSyncEnabled: Bool = false
    @AppSetting(\.experience.saveUnchangedQuickAdd) private var saveUnchangedValues: Bool = false
    @AppSetting(\.home.settingsOpenTrackedMeasurements) private var settingsOpenTrackedMeasurements: Bool = false

    // Jedna data uzywana dla wszystkich szybkich wpisow
    @State private var date: Date = AppClock.now
    // User inputs in display units; nil means “skip”
    @State private var inputs: [MetricKind: Double?] = [:]
    // Custom metric inputs keyed by identifier
    @State private var customInputs: [String: Double?] = [:]
    // Sledzi, ktore metryki uzytkownik rzeczywiscie edytowal
    @State private var editedKinds: Set<MetricKind> = []
    @State private var editedCustomIds: Set<String> = []
    @State private var isSaving = false
    @State private var showNoChangesAlert = false
    @State private var saveErrorMessage: String?
    @State private var showSanityWarning = false
    @State private var suspiciousEntries: [SanityChecker.SuspiciousEntry] = []
    @State private var pendingSaveEntries: [QuickAddSaveService.Entry]? = nil
    @FocusState private var focusedKind: MetricKind?
    @FocusState private var focusedCustomId: String?
    @State private var rulerBaseValues: [MetricKind: Double] = [:]
    private let isUITestMode = ProcessInfo.processInfo.arguments.contains("-uiTestMode")

    init(
        kinds: [MetricKind],
        latest: [MetricKind: (value: Double, date: Date)],
        unitsSystem: String,
        customDefinitions: [CustomMetricDefinition] = [],
        customLatest: [String: (value: Double, date: Date)] = [:],
        onSaved: @escaping () -> Void
    ) {
        self.kinds = kinds
        self.latest = latest
        self.unitsSystem = unitsSystem
        self.customDefinitions = customDefinitions
        self.customLatest = customLatest
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

        var customInitial: [String: Double?] = [:]
        for def in customDefinitions {
            customInitial[def.identifier] = customLatest[def.identifier]?.value
        }
        _customInputs = State(initialValue: customInitial)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AppScreenBackground(topHeight: 240)

                if kinds.isEmpty && customDefinitions.isEmpty {
                    EmptyStateCard(
                        title: AppLocalization.string("No active measurements"),
                        message: AppLocalization.string("Enable metrics in the Measurements tab to add values quickly."),
                        systemImage: "square.and.pencil",
                        accessibilityIdentifier: "quickadd.empty.state"
                    )
                    .padding(.horizontal, AppSpacing.lg)
                    .accessibilityIdentifier("quickadd.empty")
                } else {
                    ScrollView {
                        VStack(spacing: AppSpacing.sm) {
                            saveUnchangedCard

                            ForEach(kinds, id: \.self) { kind in
                                row(for: kind)
                            }

                            ForEach(customDefinitions) { def in
                                customRow(for: def)
                            }

                            dateCard
                            trackedMetricsFooter
                            if useInlineSaveBar {
                                inlineSaveSection
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.top, AppSpacing.sm)
                        .padding(.bottom, useInlineSaveBar ? AppSpacing.lg : 120)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle(AppLocalization.string("Update measurements"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .accessibilityIdentifier("quickadd.sheet")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if (!kinds.isEmpty || !customDefinitions.isEmpty) && !useInlineSaveBar {
                    saveBar
                }
            }
            .alert(AppLocalization.string("Nothing to save"), isPresented: $showNoChangesAlert) {
                Button(AppLocalization.string("OK"), role: .cancel) { }
            } message: {
                Text(AppLocalization.string("Add at least one value before saving."))
            }
            .alert(AppLocalization.string("Save Failed"), isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button(AppLocalization.string("OK"), role: .cancel) {
                    saveErrorMessage = nil
                }
            } message: {
                Text(saveErrorMessage ?? "")
            }
            .confirmationDialog(
                AppLocalization.string("sanity.warning.title"),
                isPresented: $showSanityWarning,
                titleVisibility: .visible
            ) {
                Button(AppLocalization.string("sanity.warning.save"), role: .destructive) {
                    if let entries = pendingSaveEntries {
                        Task { await saveAll(entries: entries) }
                    }
                    pendingSaveEntries = nil
                }
                Button(AppLocalization.string("Cancel"), role: .cancel) {
                    pendingSaveEntries = nil
                }
            } message: {
                Text(sanityWarningMessage)
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
                        focusedCustomId = nil
                    }
                }
            }
        }
    }

    // MARK: - Row
    @ViewBuilder
    private func row(for kind: MetricKind) -> some View {
        let showRuler = hasBaseValue(for: kind)

        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs) {
                kind.iconView(font: AppTypography.iconMedium, size: 22, tint: Color.appAccent)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                    .background(
                        Circle()
                            .fill(Color.appAccent.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(kind.title)
                        .font(AppTypography.headline)
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
                        .contentTransition(.numericText())
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.appAccent.opacity(0.14))
                        )
                }
            }

            // Ruler — visible only when we have a sensible base value
            if showRuler {
                RulerSlider(
                    value: valueBinding(for: kind),
                    range: rulerRange(for: kind),
                    step: rulerStep(for: kind)
                )
                .frame(height: 52)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            valueInputField(for: kind, showRuler: showRuler)
                .appInputContainer(focused: focusedKind == kind)

            if let validationMessage = validationMessage(for: kind) {
                InlineErrorBanner(message: validationMessage, accessibilityIdentifier: "quickadd.error.banner.\(kind.rawValue)")
                    .accessibilityIdentifier("quickadd.error.\(kind.rawValue)")
            }
        }
        .padding(AppSpacing.sm)
        .accessibilityIdentifier("quickadd.row.\(kind.rawValue)")
        .background(cardBackground(cornerRadius: AppRadius.md))
        .animation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimate), value: showRuler)
        .onAppear {
            if rulerBaseValues[kind] == nil {
                rulerBaseValues[kind] = baseValue(for: kind)
            }
        }
    }

    // MARK: - Custom Metric Row

    @ViewBuilder
    private func customRow(for definition: CustomMetricDefinition) -> some View {
        let id = definition.identifier
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: definition.sfSymbolName)
                    .font(.body)
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(Color.appAccent.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(definition.name)
                        .font(AppTypography.headline)
                        .foregroundStyle(.white)

                    if let last = customLatest[id] {
                        Text(customLastSummary(value: last.value, unit: definition.unitLabel, date: last.date))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.68))
                    }
                }

                Spacer()

                if let current = customInputs[id] ?? nil {
                    Text(String(format: "%.1f %@", current, definition.unitLabel))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .contentTransition(.numericText())
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.appAccent.opacity(0.14))
                        )
                }
            }

            customValueInputField(for: definition)
                .appInputContainer(focused: focusedCustomId == id)
        }
        .padding(AppSpacing.sm)
        .background(cardBackground(cornerRadius: AppRadius.md))
    }

    @ViewBuilder
    private func customValueInputField(for definition: CustomMetricDefinition) -> some View {
        ViewThatFits(in: .horizontal) {
            customInputRowHorizontal(for: definition)
            customInputRowVertical(for: definition)
        }
    }

    private func customInputRowHorizontal(for definition: CustomMetricDefinition) -> some View {
        let id = definition.identifier
        return HStack(spacing: 8) {
            Text(AppLocalization.string("Enter value"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)

            Spacer(minLength: 0)

            TextField(
                "0.0",
                value: Binding(
                    get: { customInputs[id] ?? nil },
                    set: { newVal in
                        customInputs[id] = newVal
                        editedCustomIds.insert(id)
                    }
                ),
                format: .number.precision(.fractionLength(2))
            )
            .focused($focusedCustomId, equals: id)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(.title3.monospacedDigit().weight(.semibold))
            .frame(minWidth: 88)
            .accessibilityIdentifier("quickadd.input.custom.\(id)")

            Text(definition.unitLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private func customInputRowVertical(for definition: CustomMetricDefinition) -> some View {
        let id = definition.identifier
        return VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.string("Enter value"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField(
                    "0.0",
                    value: Binding(
                        get: { customInputs[id] ?? nil },
                        set: { newVal in
                            customInputs[id] = newVal
                            editedCustomIds.insert(id)
                        }
                    ),
                    format: .number.precision(.fractionLength(2))
                )
                .focused($focusedCustomId, equals: id)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.leading)
                .font(.title3.monospacedDigit().weight(.semibold))
                .accessibilityIdentifier("quickadd.input.custom.\(id)")

                Text(definition.unitLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
                Spacer(minLength: 0)
            }
        }
    }

    private func customLastSummary(value: Double, unit: String, date: Date) -> String {
        let formatted = String(format: "%.1f %@", value, unit)
        let relative = date.formatted(.relative(presentation: .named))
        return "\(formatted) · \(relative)"
    }

    private var saveUnchangedCard: some View {
        Toggle(isOn: $saveUnchangedValues) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(AppLocalization.string("Save unchanged values"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(AppLocalization.string("When enabled, current values are saved even if unchanged."))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .tint(Color.appAccent)
        .padding(AppSpacing.sm)
        .background(cardBackground(cornerRadius: AppRadius.md))
    }

    private var dateCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Label(AppLocalization.string("Measurement time"), systemImage: "calendar.badge.clock")
                .font(AppTypography.sectionAction)
                .foregroundStyle(.white)

            DatePicker(
                "",
                selection: $date,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .accessibilityLabel(AppLocalization.string("Measurement time"))
            .tint(Color.appAccent)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppSpacing.sm)
        .background(cardBackground(cornerRadius: AppRadius.md))
    }

    private var useInlineSaveBar: Bool {
        dynamicTypeSize.isAccessibilitySize && !isUITestMode
    }

    private var inlineSaveSection: some View {
        saveControls
            .padding(AppSpacing.sm)
            .background(cardBackground(cornerRadius: AppRadius.md))
    }

    private var saveBar: some View {
        saveControls
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, dynamicTypeSize.isAccessibilitySize ? 10 : 6)
        .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 12 : 8)
        .background(.thinMaterial)
    }

    private var saveControls: some View {
        VStack(spacing: AppSpacing.xs) {
            Button {
                if cannotSave {
                    Haptics.error()
                    showNoChangesAlert = true
                } else {
                    Haptics.medium()
                    attemptSave()
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
            .buttonStyle(AppCTAButtonStyle(size: dynamicTypeSize.isAccessibilitySize ? .large : .regular, cornerRadius: AppRadius.md))
            .disabled(isSaving)
            .opacity(isSaving ? 0.64 : 1)
            .accessibilityIdentifier("quickadd.save")
            .accessibilityHint(AppLocalization.systemString("Save entered measurements"))
            .accessibilitySortPriority(2)

            if cannotSave {
                Text(cannotSaveReasonText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("quickadd.validation.hint")
            }
        }
    }

    private var trackedMetricsFooter: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(AppLocalization.string("measurements.footer.dynamic", kinds.count, 18))
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
            .accessibilityHint(AppLocalization.systemString("Open tracked measurements settings"))
            .accessibilitySortPriority(1)
        }
        .padding(AppSpacing.sm)
        .background(cardBackground(cornerRadius: AppRadius.md))
    }

    private func cardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AppColorRoles.surfacePrimary)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
            )
    }

    private var shouldAnimate: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func valueInputField(for kind: MetricKind, showRuler: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            inputRowHorizontal(for: kind, showRuler: showRuler)
            inputRowVertical(for: kind, showRuler: showRuler)
        }
    }

    private func inputRowHorizontal(for kind: MetricKind, showRuler: Bool) -> some View {
        HStack(spacing: 8) {
            Text(AppLocalization.string(
                showRuler ? "Enter value" : "quickadd.first.value.hint"
            ))
            .font(showRuler ? AppTypography.caption : .subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(2)

            Spacer(minLength: 0)

            TextField(
                "0.0",
                value: binding(for: kind),
                format: .number.precision(.fractionLength(2))
            )
            .focused($focusedKind, equals: kind)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(showRuler
                ? .title3.monospacedDigit().weight(.semibold)
                : .title.monospacedDigit().weight(.bold))
            .frame(minWidth: showRuler ? 72 : 88)
            .accessibilityIdentifier("quickadd.input.\(kind.rawValue)")
            .accessibilityLabel(AppLocalization.string("accessibility.value", kind.title))

            Text(kind.unitSymbol(unitsSystem: unitsSystem))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private func inputRowVertical(for kind: MetricKind, showRuler: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.string(
                showRuler ? "Enter value" : "quickadd.first.value.hint"
            ))
            .font(showRuler ? AppTypography.caption : .subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField(
                    "0.0",
                    value: binding(for: kind),
                    format: .number.precision(.fractionLength(2))
                )
                .focused($focusedKind, equals: kind)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.leading)
                .font(showRuler
                    ? .title3.monospacedDigit().weight(.semibold)
                    : .title.monospacedDigit().weight(.bold))
                .accessibilityIdentifier("quickadd.input.\(kind.rawValue)")
                .accessibilityLabel(AppLocalization.string("accessibility.value", kind.title))

                Text(kind.unitSymbol(unitsSystem: unitsSystem))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
                Spacer(minLength: 0)
            }
        }
    }

    /// Returns `true` when we have a sensible base value for the ruler —
    /// either from a previous measurement or because the user just typed one.
    private func hasBaseValue(for kind: MetricKind) -> Bool {
        QuickAddMath.shouldShowRuler(
            hasLatest: latest[kind] != nil,
            currentInput: inputs[kind] ?? nil
        )
    }

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

        return QuickAddMath.rulerRange(base: base, span: span, validRange: validRange(for: kind))
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
        MetricInputValidator.metricDisplayRange(for: kind, unitsSystem: unitsSystem)
    }

    private func formatted(_ value: Double, for kind: MetricKind) -> String {
        kind.formattedDisplayValue(value, unitsSystem: unitsSystem)
    }

    private var cannotSave: Bool {
        let values = preparedEntries(includeUnchanged: saveUnchangedValues)
        let customValues = preparedCustomEntries(includeUnchanged: saveUnchangedValues)

        guard !values.isEmpty || !customValues.isEmpty else { return true }

        return values.contains { kind, value in
            !MetricInputValidator
                .validateMetricDisplayValue(value, kind: kind, unitsSystem: unitsSystem)
                .isValid
        }
    }

    private var hasInvalidPreparedEntries: Bool {
        let values = preparedEntries(includeUnchanged: saveUnchangedValues)
        return values.contains { kind, value in
            !MetricInputValidator
                .validateMetricDisplayValue(value, kind: kind, unitsSystem: unitsSystem)
                .isValid
        }
    }

    private var cannotSaveReasonText: String {
        if hasInvalidPreparedEntries {
            return AppLocalization.string("Fix highlighted values before saving.")
        }
        return AppLocalization.string("Add at least one valid value to save.")
    }

    private func validationMessage(for kind: MetricKind) -> String? {
        guard let value = inputs[kind] ?? nil else { return nil }
        let result = MetricInputValidator.validateOptionalMetricDisplayValue(
            value,
            kind: kind,
            unitsSystem: unitsSystem
        )
        if result.isValid {
            return nil
        }
        return result.message
    }

    private func metricValue(for kind: MetricKind, displayValue: Double) -> Double {
        kind.valueToMetric(fromDisplay: displayValue, unitsSystem: unitsSystem)
    }

    private func attemptSave() {
        let entries: [QuickAddSaveService.Entry] = preparedEntries(includeUnchanged: saveUnchangedValues)
            .map { kind, displayValue in
                QuickAddSaveService.Entry(kind: kind, metricValue: metricValue(for: kind, displayValue: displayValue))
            }

        let suspicious = SanityChecker.check(
            entries: entries.map { (kind: $0.kind, metricValue: $0.metricValue, date: date) },
            previousValues: latest
        )

        if suspicious.isEmpty {
            Task { await saveAll(entries: entries) }
        } else {
            suspiciousEntries = suspicious
            pendingSaveEntries = entries
            Haptics.trigger(.warningSoft)
            showSanityWarning = true
        }
    }

    private func preparedCustomEntries(includeUnchanged: Bool) -> [(String, Double)] {
        customDefinitions.compactMap { def -> (String, Double)? in
            guard let value = customInputs[def.identifier] ?? nil else { return nil }
            if includeUnchanged {
                return (def.identifier, value)
            }
            guard editedCustomIds.contains(def.identifier) else { return nil }
            return (def.identifier, value)
        }
    }

    private var sanityWarningMessage: String {
        suspiciousEntries.map { entry in
            let previousText = entry.kind.formattedMetricValue(fromMetric: entry.previousValue, unitsSystem: unitsSystem)
            let newText = entry.kind.formattedMetricValue(fromMetric: entry.newValue, unitsSystem: unitsSystem)
            return "\(entry.kind.title): \(previousText) \u{2192} \(newText)"
        }.joined(separator: "\n")
    }

    private func saveAll(entries: [QuickAddSaveService.Entry]) async {
        guard !isSaving else { return }
        await MainActor.run { isSaving = true }

        // Powiadomienia (zapis pomiaru + osiagniecie celu)
        await MainActor.run {
            for entry in entries {
                NotificationManager.shared.recordMeasurement(date: date)
                if let goal = fetchGoal(for: entry.kind), goal.isAchieved(currentValue: entry.metricValue) {
                    NotificationManager.shared.sendGoalAchievedNotification(
                        kind: entry.kind,
                        goalCreatedDate: goal.createdDate,
                        goalValue: goal.targetValue
                    )
                }
            }
        }

        // Persist via service
        let service = QuickAddSaveService(
            context: context,
            healthKit: isSyncEnabled ? HealthKitManager.shared : nil
        )

        do {
            try service.save(entries: entries, date: date, unitsSystem: unitsSystem)

            // Save custom metric entries
            let customEntries = preparedCustomEntries(includeUnchanged: saveUnchangedValues)
            if !customEntries.isEmpty {
                try service.saveCustom(
                    entries: customEntries.map { QuickAddSaveService.CustomEntry(identifier: $0.0, value: $0.1) },
                    date: date
                )
            }
        } catch {
            await MainActor.run {
                isSaving = false
                saveErrorMessage = AppLocalization.string("Could not save measurements. Please try again.")
                Haptics.error()
            }
            AppLog.debug("❌ QuickAdd save failed: \(error.localizedDescription)")
            return
        }

        // Synchronizacja HealthKit w trybie najlepszej starannosci
        await service.syncHealthKit(entries: entries, date: date)

        let totalCount = entries.count + preparedCustomEntries(includeUnchanged: saveUnchangedValues).count
        await MainActor.run {
            ReviewRequestManager.recordMetricEntryAdded(count: totalCount)
            isSaving = false
            Haptics.success()
            onSaved()
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

                let tickCount = QuickAddMath.tickCount(span: span, step: step)
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
                        let stepIndex = QuickAddMath.stepIndex(value: clamped, lowerBound: range.lowerBound, step: step)
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
