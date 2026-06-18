import SwiftUI
import SwiftData

struct QuickAddSheetView: View {
    let kinds: [MetricKind]
    let latest: [MetricKind: (value: Double, date: Date)]
    let unitsSystem: String
    let telemetrySource: MeasurementTelemetrySource
    var customDefinitions: [CustomMetricDefinition] = []
    var customLatest: [String: (value: Double, date: Date)] = [:]
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
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
    @State private var activeField: QuickAddFieldID?
    @State private var inputBuffer = NumericInputBuffer(value: nil)
    @FocusState private var hardwareInputFocused: Bool
    @State private var rulerBaseValues: [MetricKind: Double] = [:]
    private let isUITestMode = UITestArgument.isPresent(.mode)
    private let cardTint = Color.appAccent.opacity(0.10)

    init(
        kinds: [MetricKind],
        latest: [MetricKind: (value: Double, date: Date)],
        unitsSystem: String,
        telemetrySource: MeasurementTelemetrySource = .quickAdd,
        customDefinitions: [CustomMetricDefinition] = [],
        customLatest: [String: (value: Double, date: Date)] = [:],
        onSaved: @escaping () -> Void
    ) {
        self.kinds = kinds
        self.latest = latest
        self.unitsSystem = unitsSystem
        self.telemetrySource = telemetrySource
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
                        .padding(.bottom, scrollContentBottomPadding)
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
                if let activeField {
                    numericKeypad(for: activeField)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if shouldShowBottomSaveBar {
                    saveBar
                }
            }
            .animation(
                AppMotion.animation(AppMotion.standard, enabled: shouldAnimate),
                value: activeField
            )
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
            }
            .focusable()
            .focused($hardwareInputFocused)
            .onKeyPress { press in
                handleKeyPress(press)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                clearFocus()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                clearFocus()
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
                        .foregroundStyle(AppColorRoles.textPrimary)

                    if let summary = lastSummary(for: kind) {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
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
                .appInputContainer(focused: activeField == .metric(kind))

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
                        .foregroundStyle(AppColorRoles.textPrimary)

                    if let last = customLatest[id] {
                        Text(customLastSummary(value: last.value, unit: definition.unitLabel, date: last.date))
                            .font(.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
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
                .appInputContainer(focused: activeField == .custom(id))
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
        return Button {
            activateField(.custom(id))
        } label: {
            HStack(spacing: 8) {
                Text(AppLocalization.string("Enter value"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .lineLimit(2)

                Spacer(minLength: 0)

                numericDisplayText(for: .custom(id), value: customInputs[id] ?? nil)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 88, alignment: .trailing)

                Text(definition.unitLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColorRoles.textTertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("quickadd.input.custom.\(id)")
        .accessibilityLabel(AppLocalization.string("accessibility.value", definition.name))
        .accessibilityValue(accessibilityValue(for: .custom(id), value: customInputs[id] ?? nil, unit: definition.unitLabel))
        .accessibilityHint(AppLocalization.string("quickadd.keypad.open.hint"))
    }

    private func customInputRowVertical(for definition: CustomMetricDefinition) -> some View {
        let id = definition.identifier
        return Button {
            activateField(.custom(id))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.string("Enter value"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    numericDisplayText(for: .custom(id), value: customInputs[id] ?? nil)
                        .font(.title3.monospacedDigit().weight(.semibold))

                    Text(definition.unitLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColorRoles.textTertiary)
                    Spacer(minLength: 0)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("quickadd.input.custom.\(id)")
        .accessibilityLabel(AppLocalization.string("accessibility.value", definition.name))
        .accessibilityValue(accessibilityValue(for: .custom(id), value: customInputs[id] ?? nil, unit: definition.unitLabel))
        .accessibilityHint(AppLocalization.string("quickadd.keypad.open.hint"))
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
                    .foregroundStyle(AppColorRoles.textPrimary)
                Text(AppLocalization.string("When enabled, current values are saved even if unchanged."))
                    .font(.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
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
                .foregroundStyle(AppColorRoles.textPrimary)

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

    private var isEditingAnyField: Bool {
        activeField != nil
    }

    private var shouldShowBottomSaveBar: Bool {
        (!kinds.isEmpty || !customDefinitions.isEmpty) && !useInlineSaveBar && !isEditingAnyField
    }

    private var scrollContentBottomPadding: CGFloat {
        shouldShowBottomSaveBar ? 120 : AppSpacing.lg
    }

    private var saveBar: some View {
        saveControls
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, dynamicTypeSize.isAccessibilitySize ? 10 : 6)
        .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 12 : 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColorRoles.borderSubtle)
                .frame(height: 1)
        }
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
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .disabled(isSaving)
            .opacity(isSaving ? 0.64 : 1)
            .accessibilityIdentifier("quickadd.save")
            .accessibilityHint(AppLocalization.systemString("Save entered measurements"))
            .accessibilitySortPriority(2)

            if cannotSave {
                Text(cannotSaveReasonText)
                    .font(.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("quickadd.validation.hint")
            }
        }
    }

    private var trackedMetricsFooter: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(AppLocalization.string("measurements.footer.dynamic", kinds.count, 18))
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
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
        AppGlassBackground(
            depth: .base,
            cornerRadius: cornerRadius,
            tint: cardTint
        )
    }

    private var shouldAnimate: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func valueInputField(for kind: MetricKind, showRuler: Bool) -> some View {
        Button {
            activateField(.metric(kind))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.string(
                    showRuler ? "Enter value" : "quickadd.first.value.hint"
                ))
                .font(showRuler ? AppTypography.caption : .subheadline.weight(.medium))
                .foregroundStyle(AppColorRoles.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    numericDisplayText(for: .metric(kind), value: inputs[kind] ?? nil)
                        .font(showRuler
                            ? .title3.monospacedDigit().weight(.semibold)
                            : .title.monospacedDigit().weight(.bold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(kind.unitSymbol(unitsSystem: unitsSystem))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColorRoles.textTertiary)
                    Spacer(minLength: 0)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("quickadd.input.\(kind.rawValue)")
        .accessibilityLabel(AppLocalization.string("accessibility.value", kind.title))
        .accessibilityValue(accessibilityValue(
            for: .metric(kind),
            value: inputs[kind] ?? nil,
            unit: kind.unitSymbol(unitsSystem: unitsSystem)
        ))
        .accessibilityHint(AppLocalization.string("quickadd.keypad.open.hint"))
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
        return QuickAddMetricLogic.lastSummary(
            for: kind,
            latestValue: last.value,
            latestDate: last.date,
            unitsSystem: unitsSystem
        )
    }

    private func valueBinding(for kind: MetricKind) -> Binding<Double> {
        Binding<Double>(
            get: { (inputs[kind] ?? nil) ?? baseValue(for: kind) },
            set: {
                inputs[kind] = $0
                editedKinds.insert(kind)
                if activeField == .metric(kind) {
                    inputBuffer = NumericInputBuffer(
                        value: $0,
                        locale: locale,
                        replaceOnFirstInput: false
                    )
                }
            }
        )
    }

    private func baseValue(for kind: MetricKind) -> Double {
        QuickAddMetricLogic.baseValue(
            for: kind,
            currentInput: inputs[kind] ?? nil,
            latestMetricValue: latest[kind]?.value,
            unitsSystem: unitsSystem
        )
    }

    private func rulerRange(for kind: MetricKind) -> ClosedRange<Double> {
        QuickAddMetricLogic.rulerRange(
            for: kind,
            rulerBaseValue: rulerBaseValues[kind],
            currentInput: inputs[kind] ?? nil,
            latestMetricValue: latest[kind]?.value,
            unitsSystem: unitsSystem
        )
    }

    private func rulerStep(for kind: MetricKind) -> Double {
        QuickAddMetricLogic.rulerStep(for: kind)
    }

    private func validRange(for kind: MetricKind) -> ClosedRange<Double> {
        MetricInputValidator.metricDisplayRange(for: kind, unitsSystem: unitsSystem)
    }

    private func formatted(_ value: Double, for kind: MetricKind) -> String {
        QuickAddMetricLogic.formatted(value, for: kind, unitsSystem: unitsSystem)
    }

    @ViewBuilder
    private func numericDisplayText(for field: QuickAddFieldID, value: Double?) -> some View {
        let text = activeField == field
            ? inputBuffer.text
            : NumericInputBuffer(value: value, locale: locale, replaceOnFirstInput: false).text

        Text(text.isEmpty ? "0\(NumericInputBuffer(value: nil, locale: locale).decimalSeparator)0" : text)
            .foregroundStyle(text.isEmpty ? AppColorRoles.textTertiary : AppColorRoles.textPrimary)
            .contentTransition(.numericText())
    }

    private func accessibilityValue(for field: QuickAddFieldID, value: Double?, unit: String) -> String {
        let shown = activeField == field
            ? inputBuffer.text
            : NumericInputBuffer(value: value, locale: locale, replaceOnFirstInput: false).text
        guard !shown.isEmpty else { return AppLocalization.string("quickadd.keypad.no.value") }
        return "\(shown) \(unit)"
    }

    @ViewBuilder
    private func numericKeypad(for field: QuickAddFieldID) -> some View {
        let metadata = keypadMetadata(for: field)
        QuickAddNumericKeypad(
            title: metadata.title,
            unit: metadata.unit,
            valueText: inputBuffer.text,
            decimalSeparator: inputBuffer.decimalSeparator,
            onDigit: appendDigit,
            onDecimalSeparator: appendDecimalSeparator,
            onDelete: deleteBackward,
            onClear: clearInput,
            onDone: clearFocus
        )
    }

    private func keypadMetadata(for field: QuickAddFieldID) -> (title: String, unit: String) {
        switch field {
        case .metric(let kind):
            return (kind.title, kind.unitSymbol(unitsSystem: unitsSystem))
        case .custom(let id):
            guard let definition = customDefinitions.first(where: { $0.identifier == id }) else {
                return (AppLocalization.string("Enter value"), "")
            }
            return (definition.name, definition.unitLabel)
        }
    }

    private func activateField(_ field: QuickAddFieldID) {
        guard activeField != field else { return }

        let value = field.value(metricInputs: inputs, customInputs: customInputs)
        let shouldReplace = value != nil && !field.wasEdited(
            metricKinds: editedKinds,
            customIDs: editedCustomIds
        )

        inputBuffer = NumericInputBuffer(
            value: value,
            locale: locale,
            replaceOnFirstInput: shouldReplace
        )
        activeField = field
        DispatchQueue.main.async {
            hardwareInputFocused = true
        }
    }

    private func appendDigit(_ digit: Int) {
        inputBuffer.appendDigit(digit)
        commitInputBuffer()
    }

    private func appendDecimalSeparator() {
        inputBuffer.appendDecimalSeparator()
        commitInputBuffer()
    }

    private func deleteBackward() {
        inputBuffer.deleteBackward()
        commitInputBuffer()
    }

    private func clearInput() {
        inputBuffer.clear()
        commitInputBuffer()
    }

    private func commitInputBuffer() {
        guard let activeField else { return }
        activeField.markEdited(metricKinds: &editedKinds, customIDs: &editedCustomIds)
        switch activeField {
        case .metric(let kind):
            inputs[kind] = inputBuffer.value
            if let value = inputBuffer.value {
                rulerBaseValues[kind] = value
            }
        case .custom(let id):
            customInputs[id] = inputBuffer.value
        }
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard activeField != nil else { return .ignored }

        switch press.key {
        case .delete:
            deleteBackward()
            return .handled
        case .return, .escape:
            clearFocus()
            return .handled
        default:
            break
        }

        if press.characters == "." || press.characters == "," {
            appendDecimalSeparator()
            Haptics.selection()
            return .handled
        }

        if press.characters.count == 1,
           let character = press.characters.first,
           let digit = character.wholeNumberValue {
            appendDigit(digit)
            Haptics.selection()
            return .handled
        }

        return .ignored
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
        QuickAddMetricLogic.validationMessage(
            value: inputs[kind] ?? nil,
            kind: kind,
            unitsSystem: unitsSystem
        )
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
            NotificationManager.shared.recordMeasurement(kinds: entries.map(\.kind), date: date)
            for entry in entries {
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
            try service.save(entries: entries, date: date, unitsSystem: unitsSystem, source: telemetrySource)
            await MainActor.run {
                NotificationManager.shared.scheduleAINotificationsIfNeeded(
                    context: context,
                    trigger: .manualLog(kinds: entries.map(\.kind))
                )
            }

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
            NotificationCenter.default.post(name: .measureBuddyDidSaveMeasurement, object: nil)
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

    private func clearFocus() {
        activeField = nil
        hardwareInputFocused = false
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
            let width = proxy.size.width.isFinite ? max(proxy.size.width, 1) : 1
            let height = proxy.size.height.isFinite ? max(proxy.size.height, 1) : 1
            let drawableWidth = max(width - horizontalInset * 2, 1)
            let span = max(range.upperBound - range.lowerBound, 0.0001)
            let rawRatio = (value - range.lowerBound) / span
            let ratio = rawRatio.isFinite ? min(max(rawRatio, 0), 1) : 0
            let indicatorX = horizontalInset + CGFloat(ratio) * drawableWidth

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColorRoles.surfaceSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                    )

                let tickCount = QuickAddMath.tickCount(span: span, step: step)
                ForEach(0..<tickCount, id: \.self) { index in
                    let tickX = horizontalInset + CGFloat(index) * (drawableWidth / CGFloat(max(tickCount - 1, 1)))
                    let isMajor = index.isMultiple(of: 5)
                    Rectangle()
                        .fill(AppColorRoles.textTertiary.opacity(isMajor ? 0.55 : 0.26))
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
