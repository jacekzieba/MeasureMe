import SwiftUI
import SwiftData
import UIKit

@MainActor
struct OnboardingView: View {
    private enum HealthAuthorizationPhase {
        case idle
        case preparing
        case requestingSystemPrompt
        case importingProfile
        case completed
    }

    private struct BaselineDisplayEntry: Identifiable {
        let kind: MetricKind
        let value: Double

        var id: String { kind.rawValue }
    }

    private let effects: OnboardingEffects

    @AppSetting(\.onboarding.hasCompletedOnboarding) private var hasCompletedOnboarding: Bool = false
    @AppSetting(\.onboarding.onboardingFlowVersion) private var onboardingFlowVersion: Int = 0
    @AppSetting(\.onboarding.onboardingSkippedHealthKit) private var onboardingSkippedHealthKit: Bool = false
    @AppSetting(\.onboarding.onboardingSkippedReminders) private var onboardingSkippedReminders: Bool = false
    @AppSetting(\.onboarding.onboardingPrimaryGoal) private var onboardingPrimaryGoalRaw: String = ""
    @AppSetting(\.onboarding.activationCurrentTaskID) private var activationCurrentTaskID: String = ""
    @AppSetting(\.onboarding.activationCompletedTaskIDs) private var activationCompletedTaskIDsRaw: String = ""
    @AppSetting(\.onboarding.activationSkippedTaskIDs) private var activationSkippedTaskIDsRaw: String = ""
    @AppSetting(\.onboarding.activationIsDismissed) private var activationIsDismissed: Bool = false
    @AppSetting(\.profile.userName) private var userName: String = ""
    @AppSetting(\.profile.userAge) private var userAge: Int = 0
    @AppSetting(\.profile.manualHeight) private var manualHeight: Double = 0
    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"
    @AppSetting(\.health.isSyncEnabled) private var isSyncEnabled: Bool = false
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var metricsStore: ActiveMetricsStore
    @EnvironmentObject private var pendingPhotoSaveStore: PendingPhotoSaveStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var currentStep: InputStep = .welcome
    @State private var nameInput: String = ""
    @State private var selectedPriority: OnboardingPriority?
    @State private var firstMeasurementEntries: [MetricKind: String] = [:]
    @State private var hasSavedFirstMeasurement = false
    @State private var firstMeasurementErrorMessage: String?
    @State private var isSavingFirstMeasurement = false
    @State private var showOnboardingPhotoSheet = false
    @State private var hasSavedOnboardingPhoto = false
    @State private var isRequestingHealthKit = false
    @State private var healthStatusLines: [String] = []
    @State private var healthAuthorizationPhase: HealthAuthorizationPhase = .idle
    @State private var healthAuthorizationVisualProgress: CGFloat = 0
    @State private var didPrewarmHealthKitAuthorization = false
    @State private var hasTrackedStart = false
    @State private var rhythmWeekday: Int = 1          // Calendar weekday: 1 = Sunday
    @State private var rhythmHour: Int = 9
    @State private var isSchedulingRhythm = false
    @State private var didSetReminderRhythm = false
    @State private var showMoreMetrics = false
    @State var slideAppeared = false
    @FocusState private var isNameFieldFocused: Bool
    @FocusState private var focusedMeasurementKind: MetricKind?

    private let isUITestOnboardingMode = UITestArgument.isPresent(.onboardingMode)

    init(effects: OnboardingEffects? = nil, initialStep: InputStep = .welcome) {
        self.effects = effects ?? .live
        _currentStep = State(initialValue: initialStep)
    }

    var shouldAnimate: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    private var activationTasksCount: Int { ActivationTask.allCases.count }

    private var overallStepIndex: Int { currentStep.rawValue }
    private var onboardingStepCount: Int { InputStep.allCases.count }

    private var canGoBack: Bool { currentStep != .welcome }

    private var isSkipVisible: Bool { currentStep != .welcome }
    private var isFooterHidden: Bool { false }

    private var primaryButtonTitle: String {
        switch currentStep {
        case .welcome:
            return FlowLocalization.app(
                "Let's go",
                "Zaczynamy",
                "Empezamos",
                "Los geht's",
                "C'est parti",
                "Vamos lá"
            )
        case .goal:
            return FlowLocalization.app(
                "Continue",
                "Dalej",
                "Continuar",
                "Weiter",
                "Continuer",
                "Continuar"
            )
        case .startingPoint:
            if hasSavedFirstMeasurement || didSetReminderRhythm {
                return FlowLocalization.app(
                    "Continue",
                    "Dalej",
                    "Continuar",
                    "Weiter",
                    "Continuer",
                    "Continuar"
                )
            }
            return FlowLocalization.app(
                "Save starting point",
                "Zapisz punkt startowy",
                "Guardar punto de partida",
                "Startpunkt speichern",
                "Enregistrer le point de départ",
                "Salvar ponto de partida"
            )
        case .rhythm:
            if isReminderRhythmSet {
                return FlowLocalization.app(
                    "Continue",
                    "Dalej",
                    "Continuar",
                    "Weiter",
                    "Continuer",
                    "Continuar"
                )
            }
            return FlowLocalization.app(
                "Remind me then",
                "Przypomnij mi wtedy",
                "Recuérdamelo entonces",
                "Erinnere mich dann",
                "Rappelle-moi alors",
                "Lembre-me então"
            )
        case .boosters:
            return FlowLocalization.app(
                "Continue",
                "Dalej",
                "Continuar",
                "Weiter",
                "Continuer",
                "Continuar"
            )
        case .plan:
            return FlowLocalization.app(
                "See my dashboard",
                "Pokaż dashboard",
                "Ver mi panel",
                "Mein Dashboard ansehen",
                "Voir mon tableau de bord",
                "Ver meu painel"
            )
        }
    }

    private var skipButtonTitle: String {
        FlowLocalization.app("Skip for now", "Pomiń na razie", "Omitir por ahora", "Vorerst überspringen", "Passer pour l'instant", "Pular por enquanto")
    }

    private var isPrimaryEnabled: Bool {
        switch currentStep {
        case .goal:
            return selectedPriority != nil
        case .startingPoint:
            let hasStartingPointAction = hasSavedFirstMeasurement || hasAnyFirstMeasurementInput || didSetReminderRhythm
            if isUITestOnboardingMode {
                return !isSavingFirstMeasurement && !isRequestingHealthKit
            }
            return !isSavingFirstMeasurement && !isRequestingHealthKit && hasStartingPointAction
        case .boosters:
            return !isRequestingHealthKit
        default:
            return true
        }
    }

    /// True once a weekly check-in reminder has been scheduled (rhythm step).
    private var isReminderRhythmSet: Bool {
        didSetReminderRhythm || effects.isReminderScheduled()
    }

    var resolvedPriority: OnboardingPriority {
        if let selectedPriority {
            return selectedPriority
        }
        if let storedPriority = OnboardingPriority(rawValue: onboardingPrimaryGoalRaw) {
            return storedPriority
        }
        return .improveHealth
    }

    private var hasRestoredInputState: Bool {
        !onboardingPrimaryGoalRaw.isEmpty
            || !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || userAge > 0
            || manualHeight > 0
            || isSyncEnabled
    }

    private var resolvedPriorityTitle: String { OnboardingCopy.priorityTitle(resolvedPriority) }

    private var recommendedKinds: [MetricKind] { GoalMetricPack.recommendedKinds(for: resolvedPriority) }

    /// v5 starting point: weight is always the hero, followed by the goal pack (deduped).
    private var startingPointKinds: [MetricKind] {
        var kinds: [MetricKind] = [.weight]
        for kind in recommendedKinds where kind != .weight {
            kinds.append(kind)
        }
        return kinds
    }

    /// Goal-pack metrics shown under "Add more (optional)" (everything except the weight hero).
    private var additionalStartingPointKinds: [MetricKind] {
        startingPointKinds.filter { $0 != .weight }
    }

    private var hasAnyFirstMeasurementInput: Bool {
        startingPointKinds.contains { kind in
            !(firstMeasurementEntries[kind] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var firstMeasurementDisplayEntries: [BaselineDisplayEntry] {
        startingPointKinds.compactMap { kind in
            guard let value = parseDisplayValue(firstMeasurementEntries[kind]) else { return nil }
            return BaselineDisplayEntry(kind: kind, value: value)
        }
    }

    private var onboardingPhotoMetricValues: [MetricKind: Double] {
        Dictionary(uniqueKeysWithValues: firstMeasurementDisplayEntries.map { ($0.kind, $0.value) })
    }

    private var healthProgressTitle: String {
        switch healthAuthorizationPhase {
        case .idle:
            return ""
        case .preparing:
            return FlowLocalization.app(
                "Preparing Apple Health access…",
                "Przygotowuję dostęp do Zdrowia…",
                "Preparando acceso a Salud…",
                "Apple Health-Zugriff wird vorbereitet…",
                "Préparation de l'accès à Santé…",
                "Preparando acesso ao Health…"
            )
        case .requestingSystemPrompt:
            return FlowLocalization.app(
                "Opening Apple Health…",
                "Otwieram okno Zdrowia…",
                "Abriendo Apple Health…",
                "Apple Health wird geöffnet…",
                "Ouverture d'Apple Health…",
                "Abrindo Apple Health…"
            )
        case .importingProfile:
            return FlowLocalization.app(
                "Importing your baseline…",
                "Importuję Twój punkt startowy…",
                "Importando tu linię bazową…",
                "Deine Basis wird importiert…",
                "Import de votre base…",
                "Importando sua linha de base…"
            )
        case .completed:
            return FlowLocalization.app(
                "Health connected",
                "Zdrowie połączone",
                "Salud conectada",
                "Health verbunden",
                "Santé connectée",
                "Health conectado"
            )
        }
    }

    private var healthButtonTitle: String {
        if isRequestingHealthKit {
            return healthProgressTitle
        }
        if isSyncEnabled {
            return FlowLocalization.app(
                "Apple Health connected",
                "Apple Health połączone",
                "Apple Health conectado",
                "Apple Health verbunden",
                "Apple Health connecté",
                "Apple Health conectado"
            )
        }
        return OnboardingCopy.healthAllowCTA
    }

    var body: some View {
        ZStack {
            AppScreenBackground(topHeight: 400, tint: Color.appAccent.opacity(0.2), showsAmbientBlobs: false)

            VStack(spacing: 0) {
                topBar

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.md)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isFooterHidden {
                footer
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, 12)
                    .padding(.top, 8)
                    .background(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                AppColorRoles.surfaceChrome.opacity(0.82),
                                AppColorRoles.surfacePrimary.opacity(0.96)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .onAppear(perform: handleAppear)
        .onChange(of: currentStep) { _, _ in
            triggerSlideAppearance()
        }
        .onChange(of: overallStepIndex) { _, newValue in
            syncUITestBridge(stepIndex: newValue)
            trackCurrentStep()
        }
        .onReceive(NotificationCenter.default.publisher(for: .onboardingUITestNext)) { _ in
            guard isUITestOnboardingMode else { return }
            goToNextStep()
        }
        .onReceive(NotificationCenter.default.publisher(for: .onboardingUITestBack)) { _ in
            guard isUITestOnboardingMode else { return }
            goToPreviousStep()
        }
        .onReceive(NotificationCenter.default.publisher(for: .onboardingUITestSkip)) { _ in
            guard isUITestOnboardingMode else { return }
            skipCurrentStep()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            dismissKeyboardFocus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            dismissKeyboardFocus()
        }
        .sheet(isPresented: $showOnboardingPhotoSheet) {
            NavigationStack {
                AddPhotoView(
                    initialMetricValues: onboardingPhotoMetricValues,
                    telemetrySource: .onboarding,
                    onSaved: {
                        hasSavedOnboardingPhoto = true
                    }
                )
                .environmentObject(metricsStore)
                .environmentObject(pendingPhotoSaveStore)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                goToPreviousStep()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(AppColorRoles.surfacePrimary.opacity(0.92), in: Circle())
            }
            .opacity(canGoBack ? 1 : 0)
            .disabled(!canGoBack)
            .accessibilityIdentifier("onboarding.back")

            Spacer()

            stepDots

            Spacer()

            skipLink
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, 12)
    }

    private var skipLink: some View {
        Button {
            skipCurrentStep()
        } label: {
            Text(skipButtonTitle)
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(AppColorRoles.textSecondary)
                .frame(width: 116, alignment: .trailing)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.skip")
    }

    private func dismissKeyboardFocus() {
        isNameFieldFocused = false
        focusedMeasurementKind = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var stepDots: some View {
        HStack(spacing: 8) {
            ForEach(InputStep.allCases, id: \.self) { step in
                Capsule(style: .continuous)
                    .fill(step == currentStep ? Color.appAccent : AppColorRoles.borderSubtle)
                    .frame(width: step == currentStep ? 28 : 8, height: 6)
                    .animation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimate), value: currentStep)
            }
        }
    }

    private var content: some View {
        GeometryReader { proxy in
            stepView(currentStep, availableHeight: proxy.size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .id(currentStep.rawValue)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    )
                )
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button(action: goToNextStep) {
                Text(primaryButtonTitle)
                    .foregroundStyle(AppColorRoles.textOnAccent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
            .disabled(!isPrimaryEnabled)
            .accessibilityIdentifier("onboarding.next")
        }
    }

    @ViewBuilder
    private func stepView(_ step: InputStep, availableHeight: CGFloat) -> some View {
        let layout = onboardingLayout(for: availableHeight)
        switch step {
        case .welcome:
            onboardingWelcomeSlide(layout: layout)
        case .goal:
            onboardingInputCard {
                VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                    onboardingSlideHeader(
                        title: FlowLocalization.app(
                            "What's your goal?",
                            "Jaki masz cel?",
                            "¿Cuál es tu objetivo?",
                            "Was ist dein Ziel?",
                            "Quel est votre objectif ?",
                            "Qual é o seu objetivo?"
                        ),
                        subtitle: FlowLocalization.app(
                            "We'll match your starting metrics to it.",
                            "Dobierzemy do niego metryki startowe.",
                            "Ajustaremos tus métricas iniciales a él.",
                            "Wir richten deine Startmetriken danach aus.",
                            "Nous adapterons vos indicateurs de départ.",
                            "Vamos ajustar suas métricas iniciais a ele."
                        ),
                        titleSize: layout.headerTitleSize
                    )

                    VStack(alignment: .leading, spacing: layout.groupSpacing) {
                        ForEach(OnboardingPriority.allCases, id: \.self) { priority in
                            let isSelected = selectedPriority == priority
                            Button {
                                Haptics.selection()
                                selectGoal(priority)
                            } label: {
                                HStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(OnboardingCopy.priorityTitle(priority))
                                            .font(AppTypography.bodyEmphasis)
                                            .foregroundStyle(AppColorRoles.textPrimary)
                                        Text(OnboardingCopy.prioritySubtitle(priority))
                                            .font(AppTypography.caption)
                                            .foregroundStyle(AppColorRoles.textSecondary)
                                            .lineLimit(3)
                                            .minimumScaleFactor(0.86)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .layoutPriority(1)
                                    }

                                    Spacer()

                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(isSelected ? Color.appAccent : AppColorRoles.textTertiary)
                                }
                                .padding(AppSpacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                                        .fill(isSelected ? Color.appAccent.opacity(0.12) : AppColorRoles.surfaceInteractive)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                                                .stroke(isSelected ? Color.appAccent.opacity(0.45) : AppColorRoles.borderSubtle, lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("onboarding.priority.\(priority.rawValue)")
                        }
                    }

                    if let selectedPriority {
                        recommendedMetricsBanner(for: selectedPriority)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isNameFieldFocused = false
                }
            }
        case .startingPoint:
            startingPointStep(layout: layout)
        case .rhythm:
            rhythmStep(layout: layout)
        case .boosters:
            boostersStep(layout: layout)
                .task {
                    guard !didPrewarmHealthKitAuthorization else { return }
                    didPrewarmHealthKitAuthorization = true
                    await effects.prewarmHealthKitAuthorization()
                }
        case .plan:
            planStep(layout: layout)
        }
    }

    // MARK: - v5 step bodies

    @ViewBuilder
    private func startingPointStep(layout: OnboardingCardLayout) -> some View {
        onboardingInputCard {
            VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                if hasSavedFirstMeasurement {
                    savedBaselineCard
                } else {
                    onboardingSlideHeader(
                        title: FlowLocalization.app(
                            "Your starting point",
                            "Twój punkt startowy",
                            "Tu punto de partida",
                            "Dein Startpunkt",
                            "Votre point de départ",
                            "Seu ponto de partida"
                        ),
                        subtitle: FlowLocalization.app(
                            "Weight is enough. Add the rest whenever you like.",
                            "Wystarczy waga. Resztę dodasz, kiedy zechcesz.",
                            "Con el peso basta. Añade el resto cuando quieras.",
                            "Das Gewicht reicht. Den Rest ergänzt du jederzeit.",
                            "Le poids suffit. Ajoutez le reste quand vous voulez.",
                            "O peso já basta. Adicione o resto quando quiser."
                        ),
                        titleSize: layout.headerTitleSize
                    )

                    weightHeroCard

                    if !additionalStartingPointKinds.isEmpty {
                        addMoreMetricsSection
                    }

                    if let firstMeasurementErrorMessage {
                        Label(firstMeasurementErrorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(AppTypography.caption)
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                    .fill(Color.orange.opacity(0.10))
                            )
                            .accessibilityIdentifier("onboarding.measurement.error")
                    }

                    eveningExitCard
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(AppLocalization.string("Done")) { dismissKeyboardFocus() }
                }
            }
            .onAppear {
                guard !isUITestOnboardingMode,
                      !hasSavedFirstMeasurement,
                      (firstMeasurementEntries[.weight] ?? "").isEmpty else {
                    return
                }
                let delay: TimeInterval = shouldAnimate ? 0.4 : 0.05
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    if currentStep == .startingPoint { focusedMeasurementKind = .weight }
                }
            }
        }
    }

    private var weightHeroCard: some View {
        let binding = Binding<String>(
            get: { firstMeasurementEntries[.weight] ?? "" },
            set: { firstMeasurementEntries[.weight] = $0 }
        )
        let isImperial = unitsSystem == "imperial"
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(FlowLocalization.app("WEIGHT", "WAGA", "PESO", "GEWICHT", "POIDS", "PESO"))
                    .font(AppTypography.captionEmphasis)
                    .tracking(0.5)
                    .foregroundStyle(AppColorRoles.textSecondary)
                Spacer()
                weightUnitToggle
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField(isImperial ? "165" : "75", text: binding)
                    .keyboardType(.decimalPad)
                    .focused($focusedMeasurementKind, equals: .weight)
                    .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .fixedSize()
                    .id(measurementFieldID(.weight))
                    .accessibilityIdentifier("onboarding.measurement.weight")
                Text(MetricKind.weight.unitSymbol(unitsSystem: unitsSystem))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColorRoles.textTertiary)
                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .fill(Color.appAccent.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                        .stroke(Color.appAccent.opacity(0.45), lineWidth: 1.5)
                )
        )
    }

    private var weightUnitToggle: some View {
        HStack(spacing: 2) {
            ForEach(["kg", "lb"], id: \.self) { unit in
                let selected = (unit == "lb") == (unitsSystem == "imperial")
                Button {
                    Haptics.selection()
                    unitsSystem = (unit == "kg") ? "metric" : "imperial"
                } label: {
                    Text(unit)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(selected ? AppColorRoles.textOnAccent : AppColorRoles.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule(style: .continuous).fill(selected ? Color.appAccent : Color.clear))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.weight.unit.\(unit)")
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(AppColorRoles.surfaceInteractive))
    }

    private var addMoreMetricsSection: some View {
        VStack(spacing: 8) {
            Button {
                Haptics.selection()
                if shouldAnimate {
                    withAnimation(AppMotion.standard) { showMoreMetrics.toggle() }
                } else {
                    showMoreMetrics.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Text(FlowLocalization.app("Add more", "Dodaj więcej", "Añadir más", "Mehr hinzufügen", "Ajouter plus", "Adicionar mais"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColorRoles.textPrimary)
                        Text(FlowLocalization.app("(optional)", "(opcjonalnie)", "(opcional)", "(optional)", "(facultatif)", "(opcional)"))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textTertiary)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)

                    Spacer(minLength: 0)

                    if !showMoreMetrics {
                        ForEach(additionalStartingPointKinds.prefix(2), id: \.self) { kind in
                            Text(kind.title)
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColorRoles.textSecondary)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule(style: .continuous).fill(AppColorRoles.surfaceElevated))
                        }
                    }

                    Image(systemName: showMoreMetrics ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColorRoles.textTertiary)
                }
                .padding(AppSpacing.smmd)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .fill(AppColorRoles.surfaceInteractive)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.measurement.addMore")

            if showMoreMetrics {
                VStack(spacing: 8) {
                    ForEach(additionalStartingPointKinds, id: \.self) { kind in
                        additionalMetricRow(kind: kind)
                    }
                }
            }
        }
    }

    private func additionalMetricRow(kind: MetricKind) -> some View {
        let binding = Binding<String>(
            get: { firstMeasurementEntries[kind] ?? "" },
            set: { firstMeasurementEntries[kind] = $0 }
        )
        let placeholder: String = {
            switch kind.unitCategory {
            case .weight: return unitsSystem == "imperial" ? "165" : "75"
            case .length: return unitsSystem == "imperial" ? "35" : "90"
            case .percent: return "20"
            }
        }()
        return HStack(spacing: 12) {
            kind.iconView(size: 18, tint: Color.appAccent)
                .frame(width: 30, height: 30)
                .background(Color.appAccent.opacity(0.14))
                .clipShape(Circle())

            Text(kind.title)
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(AppColorRoles.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            TextField(placeholder, text: binding)
                .keyboardType(.decimalPad)
                .focused($focusedMeasurementKind, equals: kind)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(AppColorRoles.textPrimary)
                .frame(width: 64)
                .id(measurementFieldID(kind))
                .accessibilityIdentifier("onboarding.measurement.\(kind.rawValue)")

            Text(kind.unitSymbol(unitsSystem: unitsSystem))
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(AppColorRoles.textSecondary)
                .frame(width: 24, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.smmd, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.smmd, style: .continuous)
                        .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func boostersStep(layout: OnboardingCardLayout) -> some View {
        onboardingInputCard {
            VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                onboardingSlideHeader(
                    title: FlowLocalization.app(
                        "Two boosters to start",
                        "Dwa boostery na start",
                        "Dos potenciadores para empezar",
                        "Zwei Booster zum Start",
                        "Deux boosters pour démarrer",
                        "Dois reforços para começar"
                    ),
                    subtitle: FlowLocalization.app(
                        "Optional — but they speed up your first insights.",
                        "Opcjonalne — ale przyspieszą pierwsze wnioski.",
                        "Opcionales, pero aceleran tus primeros hallazgos.",
                        "Optional – aber sie beschleunigen deine ersten Einblicke.",
                        "Facultatifs, mais ils accélèrent vos premiers insights.",
                        "Opcionais, mas aceleram seus primeiros insights."
                    ),
                    titleSize: layout.headerTitleSize
                )

                startPhotoCard(compact: layout.isCompact)

                healthBoosterCard(compact: layout.isCompact)

                privacyCard(compact: layout.isCompact)
            }
        }
    }

    @ViewBuilder
    private func healthBoosterCard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(alignment: .top, spacing: compact ? 8 : 12) {
                Image(systemName: isSyncEnabled ? "heart.fill" : "heart")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
                    .frame(width: compact ? 34 : 38, height: compact ? 34 : 38)
                    .background(Color.appAccent.opacity(0.13))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(OnboardingCopy.activationTaskTitle(.connectHealth))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    Text(OnboardingCopy.activationTaskBody(.connectHealth))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !healthStatusLines.isEmpty {
                VStack(alignment: .leading, spacing: compact ? 3 : 6) {
                    ForEach(healthStatusLines, id: \.self) { line in
                        Label(line, systemImage: "checkmark.circle.fill")
                            .font(compact ? AppTypography.microEmphasis : AppTypography.caption)
                            .foregroundStyle(Color.appAccent)
                    }
                }
            }

            Button(action: requestHealthAccess) {
                HStack(spacing: 10) {
                    if isRequestingHealthKit {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppColorRoles.textPrimary)
                    }
                    Text(healthButtonTitle)
                        .frame(maxWidth: .infinity)
                }
                .frame(minHeight: 46)
            }
            .buttonStyle(AppSecondaryButtonStyle(cornerRadius: AppRadius.md))
            .disabled(isRequestingHealthKit || isSyncEnabled)
            .accessibilityIdentifier("onboarding.health.allow")
        }
        .padding(compact ? AppSpacing.sm : AppSpacing.smmd)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                )
        )
    }

    // MARK: - Starting point: evening-exit

    private var eveningExitCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.appTeal)
                    .frame(width: 34, height: 34)
                    .background(Color.appTeal.opacity(0.16))
                    .clipShape(Circle())

                Text(FlowLocalization.app(
                    "Can't measure right now?",
                    "Nie masz jak się teraz zmierzyć?",
                    "¿No puedes medirte ahora?",
                    "Kannst du dich gerade nicht messen?",
                    "Pas moyen de vous mesurer maintenant ?",
                    "Sem como se medir agora?"
                ))
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(AppColorRoles.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: triggerEveningReminder) {
                Text(FlowLocalization.app(
                    "Remind me tonight",
                    "Przypomnij wieczorem",
                    "Recordar esta noche",
                    "Heute Abend erinnern",
                    "Rappel ce soir",
                    "Lembrar à noite"
                ))
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(Color.appTeal)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.appTeal.opacity(0.12))
                        .overlay(Capsule(style: .continuous).stroke(Color.appTeal.opacity(0.55), lineWidth: 1.5))
                )
            }
            .buttonStyle(.plain)
            .disabled(isSchedulingRhythm)
            .accessibilityIdentifier("onboarding.measurement.remindTonight")
        }
        .padding(AppSpacing.smmd)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
        )
    }

    // MARK: - Rhythm step (v5 · variant B)

    @ViewBuilder
    private func rhythmStep(layout: OnboardingCardLayout) -> some View {
        onboardingInputCard {
            VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                onboardingSlideHeader(
                    title: FlowLocalization.app(
                        "Let's lock in your first trend",
                        "Umówmy się na pierwszy trend",
                        "Fijemos tu primera tendencia",
                        "Sichern wir deinen ersten Trend",
                        "Fixons votre première tendance",
                        "Vamos marcar sua primeira tendência"
                    ),
                    subtitle: FlowLocalization.app(
                        "Next week's measurement shows which way you're heading.",
                        "Drugi pomiar za tydzień pokaże, w którą stronę idziesz.",
                        "La medida de la próxima semana mostrará hacia dónde vas.",
                        "Die Messung nächste Woche zeigt, wohin es geht.",
                        "La mesure de la semaine prochaine montrera votre direction.",
                        "A medição da próxima semana mostra para onde você vai."
                    ),
                    titleSize: layout.headerTitleSize
                )

                rhythmTimelineCard
                rhythmPrePromptCard
            }
        }
    }

    private var selectedRhythmLabel: String {
        let symbols = Calendar.current.weekdaySymbols
        let day = symbols[(rhythmWeekday - 1) % symbols.count].capitalized
        return "\(day), \(rhythmHour):00"
    }

    private var rhythmTimelineCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            rhythmTimelineRow(
                dotColor: Color.appEmerald,
                glow: false,
                title: FlowLocalization.app("Today", "Dziś", "Hoy", "Heute", "Aujourd'hui", "Hoje"),
                subtitle: FlowLocalization.app("Starting point saved", "Punkt startowy zapisany", "Punto de partida guardado", "Startpunkt gespeichert", "Point de départ enregistré", "Ponto inicial salvo"),
                isLast: false,
                check: true
            )
            rhythmTimelineRow(
                dotColor: Color.appAccent,
                glow: true,
                title: selectedRhythmLabel,
                subtitle: FlowLocalization.app("Second measurement — your first trend on the chart", "Drugi pomiar — Twój pierwszy trend na wykresie", "Segunda medida: tu primera tendencia en el gráfico", "Zweite Messung – dein erster Trend im Diagramm", "Deuxième mesure — votre première tendance sur le graphique", "Segunda medição — sua primeira tendência no gráfico"),
                isLast: false,
                check: false
            )
            rhythmTimelineRow(
                dotColor: AppColorRoles.textTertiary,
                glow: false,
                title: FlowLocalization.app("Following weeks", "Kolejne tygodnie", "Próximas semanas", "Folgende Wochen", "Semaines suivantes", "Próximas semanas"),
                subtitle: FlowLocalization.app("The trend grows with each check-in", "Trend rośnie z każdym check-inem", "La tendencia crece con cada control", "Der Trend wächst mit jedem Check-in", "La tendance grandit à chaque suivi", "A tendência cresce a cada check-in"),
                isLast: true,
                check: false
            )

            Rectangle()
                .fill(AppColorRoles.borderSubtle)
                .frame(height: 1)
                .padding(.top, 4)
                .padding(.bottom, 14)

            rhythmDayPicker
                .padding(.bottom, 12)
            rhythmTimePicker
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lgl, style: .continuous)
                .fill(AppColorRoles.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lgl, style: .continuous)
                        .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                )
        )
    }

    private func rhythmTimelineRow(dotColor: Color, glow: Bool, title: String, subtitle: String, isLast: Bool, check: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 13, height: 13)
                    .shadow(color: glow ? dotColor.opacity(0.7) : .clear, radius: glow ? 7 : 0)
                    .padding(.top, 3)
                if !isLast {
                    Rectangle()
                        .fill(AppColorRoles.borderSubtle)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 13)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(isLast ? AppColorRoles.textSecondary : AppColorRoles.textPrimary)
                    if check {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.appEmerald)
                    }
                }
                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rhythmDayPicker: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let order = [2, 3, 4, 5, 6, 7, 1] // Mon…Sun in Calendar weekday numbers
        return VStack(alignment: .leading, spacing: 10) {
            Text(FlowLocalization.app(
                "Day of the week",
                "Dzień tygodnia",
                "Día de la semana",
                "Wochentag",
                "Jour de la semaine",
                "Dia da semana"
            ))
            .font(AppTypography.captionEmphasis)
            .foregroundStyle(AppColorRoles.textSecondary)

            HStack(spacing: 6) {
                ForEach(order, id: \.self) { weekday in
                    let isSelected = rhythmWeekday == weekday
                    Button {
                        Haptics.selection()
                        rhythmWeekday = weekday
                    } label: {
                        Text(symbols[(weekday - 1) % symbols.count])
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(isSelected ? AppColorRoles.textOnAccent : AppColorRoles.textSecondary)
                            .frame(width: 38, height: 38)
                            .background(
                                Circle()
                                    .fill(isSelected ? Color.appAccent : AppColorRoles.surfaceInteractive)
                                    .overlay(Circle().stroke(isSelected ? Color.clear : AppColorRoles.borderSubtle, lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("onboarding.rhythm.day.\(weekday)")
                }
            }
        }
    }

    private var rhythmTimePicker: some View {
        let options: [(hour: Int, label: String)] = [
            (9, FlowLocalization.app("Morning 9:00", "Rano 9:00", "Mañana 9:00", "Morgens 9:00", "Matin 9:00", "Manhã 9:00")),
            (15, "15:00"),
            (20, FlowLocalization.app("Evening 20:00", "Wieczorem 20:00", "Noche 20:00", "Abends 20:00", "Soir 20:00", "Noite 20:00"))
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Text(FlowLocalization.app("Time", "Godzina", "Hora", "Uhrzeit", "Heure", "Hora"))
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(AppColorRoles.textSecondary)

            HStack(spacing: 8) {
                ForEach(options, id: \.hour) { option in
                    let isSelected = rhythmHour == option.hour
                    Button {
                        Haptics.selection()
                        rhythmHour = option.hour
                    } label: {
                        Text(option.label)
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(isSelected ? AppColorRoles.textOnAccent : AppColorRoles.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? Color.appAccent : AppColorRoles.surfaceInteractive)
                                    .overlay(Capsule().stroke(isSelected ? Color.clear : AppColorRoles.borderSubtle, lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding.rhythm.time.\(option.hour)")
                }
            }
        }
    }

    private var rhythmPrePromptCard: some View {
        HStack(spacing: 14) {
            MeasureBuddyView(pose: .reminder, size: 56, idleAnimation: false)

            VStack(alignment: .leading, spacing: 4) {
                Text(isReminderRhythmSet
                     ? FlowLocalization.app("Reminder set", "Przypomnienie ustawione", "Recordatorio listo", "Erinnerung gesetzt", "Rappel défini", "Lembrete pronto")
                     : FlowLocalization.app("One notification a week", "Jedno powiadomienie tygodniowo", "Una notificación por semana", "Eine Benachrichtigung pro Woche", "Une notification par semaine", "Uma notificação por semana"))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColorRoles.textPrimary)

                Text(isReminderRhythmSet
                     ? FlowLocalization.app("See you on your check-in day. Change it anytime.", "Do zobaczenia w dniu check-inu. Zmienisz to w każdej chwili.", "Nos vemos en tu día de control. Cámbialo cuando quieras.", "Bis zu deinem Check-in-Tag. Jederzeit änderbar.", "À votre jour de suivi. Modifiable à tout moment.", "Até o seu dia de check-in. Mude quando quiser.")
                     : FlowLocalization.app("Just a check-in nudge. No spam — promise.", "Tylko przypomnienie o check-inie. Zero spamu — obiecuję.", "Solo un aviso de control. Sin spam, lo prometo.", "Nur ein Check-in-Hinweis. Kein Spam – versprochen.", "Juste un rappel de suivi. Pas de spam, promis.", "Só um lembrete de check-in. Sem spam — prometo."))
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if isReminderRhythmSet {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.appEmerald)
            }
        }
        .padding(AppSpacing.smmd)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(Color.appAccent.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(Color.appAccent.opacity(0.22), lineWidth: 1)
                )
        )
    }

    // MARK: - Plan step (v5 · contract)

    @ViewBuilder
    private func planStep(layout: OnboardingCardLayout) -> some View {
        onboardingInputCard {
            VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                HStack(alignment: .top, spacing: 12) {
                    onboardingSlideHeader(
                        title: FlowLocalization.app(
                            "Your plan is ready",
                            "Twój plan jest gotowy",
                            "Tu plan está listo",
                            "Dein Plan ist bereit",
                            "Votre plan est prêt",
                            "Seu plano está pronto"
                        ),
                        subtitle: FlowLocalization.app(
                            "The first dot is in. The second makes it a trend.",
                            "Pierwsza kropka już jest. Druga zrobi z niej trend.",
                            "El primer punto ya está. El segundo lo convierte en tendencia.",
                            "Der erste Punkt ist da. Der zweite macht einen Trend daraus.",
                            "Le premier point est là. Le second en fait une tendance.",
                            "O primeiro ponto já está. O segundo vira tendência."
                        ),
                        titleSize: layout.headerTitleSize
                    )

                    MeasureBuddyView(pose: .celebration, size: 72)
                        .padding(.top, -2)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(FlowLocalization.app("Goal", "Cel", "Objetivo", "Ziel", "Objectif", "Meta"))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                        Text(resolvedPriorityTitle)
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(AppColorRoles.textOnAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule(style: .continuous).fill(Color.appAccent))
                        Spacer(minLength: 0)
                    }
                    flowChipList(labels: recommendedKinds.map(\.title))

                    planMiniChart
                        .padding(.top, 4)
                }
                .padding(AppSpacing.smmd)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .fill(AppColorRoles.surfaceInteractive)
                )

                nextCheckInCard

                MiaraSpeechBubble(
                    text: FlowLocalization.app(
                        "See you on check-in day — that's when I'll show your first trend.",
                        "Do zobaczenia w dniu check-inu — wtedy pokażę Ci pierwszy trend.",
                        "Nos vemos el día del control: ahí te mostraré tu primera tendencia.",
                        "Bis zum Check-in-Tag — dann zeige ich dir deinen ersten Trend.",
                        "À votre jour de suivi — je vous montrerai votre première tendance.",
                        "Até o dia do check-in — aí mostro sua primeira tendência."
                    )
                )
            }
        }
    }

    private var nextCheckInCard: some View {
        HStack(spacing: 13) {
            Image(systemName: "bell.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.appAccent)
                .frame(width: 44, height: 44)
                .background(Color.appAccent.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(FlowLocalization.app("Next check-in", "Następny check-in", "Próximo control", "Nächster Check-in", "Prochain suivi", "Próximo check-in"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                Text(nextCheckInText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if isReminderRhythmSet {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.appEmerald)
            }
        }
        .padding(AppSpacing.smmd)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                )
        )
    }

    private var nextCheckInText: String {
        guard isReminderRhythmSet else {
            return FlowLocalization.app(
                "Set a reminder from your dashboard",
                "Ustaw przypomnienie na dashboardzie",
                "Configura un recordatorio desde el panel",
                "Erinnerung im Dashboard einstellen",
                "Définissez un rappel depuis le tableau de bord",
                "Defina um lembrete pelo painel"
            )
        }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMM HH:mm")
        return formatter.string(from: rhythmReminderDate())
    }

    private var planMiniChart: some View {
        VStack(spacing: 6) {
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let baseY = h - 6
                let todayPt = CGPoint(x: 24, y: h - 26)
                let futurePt = CGPoint(x: w - 28, y: h - 46)

                var baseline = Path()
                baseline.move(to: CGPoint(x: 6, y: baseY))
                baseline.addLine(to: CGPoint(x: w - 6, y: baseY))
                ctx.stroke(baseline, with: .color(AppColorRoles.borderSubtle), lineWidth: 1.5)

                var projection = Path()
                projection.move(to: todayPt)
                projection.addCurve(
                    to: futurePt,
                    control1: CGPoint(x: w * 0.42, y: h - 30),
                    control2: CGPoint(x: w * 0.64, y: h - 42)
                )
                ctx.stroke(
                    projection,
                    with: .color(AppColorRoles.textTertiary),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 6])
                )

                let ring = Path(ellipseIn: CGRect(x: futurePt.x - 5, y: futurePt.y - 5, width: 10, height: 10))
                ctx.stroke(ring, with: .color(Color.appAccent), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))

                ctx.fill(
                    Path(ellipseIn: CGRect(x: todayPt.x - 14, y: todayPt.y - 14, width: 28, height: 28)),
                    with: .color(Color.appAccent.opacity(0.16))
                )
                ctx.fill(
                    Path(ellipseIn: CGRect(x: todayPt.x - 6, y: todayPt.y - 6, width: 12, height: 12)),
                    with: .color(Color.appAccent)
                )
            }
            .frame(height: 76)
            .accessibilityHidden(true)

            HStack {
                Text(FlowLocalization.app("Today", "Dziś", "Hoy", "Heute", "Auj.", "Hoje"))
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColorRoles.textSecondary)
                Spacer()
                Text(FlowLocalization.app("First trend", "Pierwszy trend", "Primera tendencia", "Erster Trend", "1re tendance", "1ª tendência"))
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColorRoles.textTertiary)
            }
        }
    }

    private var savedBaselineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                FlowLocalization.app(
                    "Baseline saved",
                    "Punkt startowy zapisany",
                    "Línea base guardada",
                    "Startpunkt gespeichert",
                    "Point de départ enregistré",
                    "Linha de base salva"
                ),
                systemImage: "checkmark.circle.fill"
            )
            .font(AppTypography.bodyEmphasis)
            .foregroundStyle(Color.appAccent)

            Text(
                FlowLocalization.app(
                    "You have a first dot on the chart. The next check-in can show a trend.",
                    "Masz pierwszą kropkę na wykresie. Następny check-in może pokazać trend.",
                    "Ya tienes el primer punto en el gráfico. El siguiente check-in podrá mostrar una tendencia.",
                    "Du hast den ersten Punkt im Diagramm. Der nächste Check-in kann einen Trend zeigen.",
                    "Vous avez un premier point sur le graphique. Le prochain check-in pourra montrer une tendance.",
                    "Você tem o primeiro ponto no gráfico. O próximo check-in pode mostrar uma tendência."
                )
            )
            .font(AppTypography.caption)
            .foregroundStyle(AppColorRoles.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(firstMeasurementDisplayEntries) { entry in
                    HStack(spacing: 10) {
                        entry.kind.iconView(size: 16, tint: Color.appAccent)
                            .frame(width: 28, height: 28)
                            .background(Color.appAccent.opacity(0.12))
                            .clipShape(Circle())

                        Text(entry.kind.title)
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(AppColorRoles.textPrimary)

                        Spacer(minLength: 0)

                        Text(entry.kind.formattedDisplayValue(entry.value, unitsSystem: unitsSystem))
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(AppColorRoles.textPrimary)
                            .monospacedDigit()
                    }
                }
            }
            .accessibilityIdentifier("onboarding.baseline.summary")
        }
        .padding(AppSpacing.smmd)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(Color.appAccent.opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(Color.appAccent.opacity(0.22), lineWidth: 1)
                )
        )
    }

    private var skippedBaselineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                FlowLocalization.app(
                    "No tape measure right now?",
                    "Nie masz teraz miarki?",
                    "¿No tienes cinta métrica ahora?",
                    "Kein Maßband zur Hand?",
                    "Pas de mètre ruban maintenant ?",
                    "Sem fita métrica agora?"
                ),
                systemImage: "clock.arrow.circlepath"
            )
            .font(AppTypography.captionEmphasis)
            .foregroundStyle(AppColorRoles.textPrimary)

            Text(
                FlowLocalization.app(
                    "You can add the first measurement later. A private starting photo can still help future comparisons.",
                    "Pierwszy pomiar dodasz później. Prywatne zdjęcie startowe nadal pomoże w przyszłych porównaniach.",
                    "Podrás añadir la primera medida después. Una foto inicial privada aún ayudará en futuras comparaciones.",
                    "Die erste Messung kannst du später hinzufügen. Ein privates Startfoto hilft trotzdem bei späteren Vergleichen.",
                    "Vous pourrez ajouter la première mesure plus tard. Une photo initiale privée aidera quand même les comparaisons futures.",
                    "Você pode adicionar a primeira medida depois. Uma foto inicial privada ainda ajuda comparações futuras."
                )
            )
            .font(AppTypography.caption)
            .foregroundStyle(AppColorRoles.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.smmd)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
        )
    }

    private func startPhotoCard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(alignment: .top, spacing: compact ? 8 : 12) {
                Image(systemName: hasSavedOnboardingPhoto ? "photo.badge.checkmark.fill" : "camera.viewfinder")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(hasSavedOnboardingPhoto ? Color.appEmerald : Color.appAccent)
                    .frame(width: compact ? 34 : 38, height: compact ? 34 : 38)
                    .background((hasSavedOnboardingPhoto ? Color.appEmerald : Color.appAccent).opacity(0.13))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        hasSavedOnboardingPhoto
                            ? FlowLocalization.app(
                                "Starting photo added",
                                "Zdjęcie startowe dodane",
                                "Foto inicial añadida",
                                "Startfoto hinzugefügt",
                                "Photo initiale ajoutée",
                                "Foto inicial adicionada"
                            )
                            : FlowLocalization.app(
                                "Add a starting photo",
                                "Dodaj zdjęcie startowe",
                                "Añade una foto inicial",
                                "Startfoto hinzufügen",
                                "Ajouter une photo initiale",
                                "Adicionar foto inicial"
                            )
                    )
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)

                    Text(
                        FlowLocalization.app(
                            "Private and optional. Front and side photos in similar light make comparisons easier.",
                            "Prywatne i opcjonalne. Zdjęcia z przodu i z boku w podobnym świetle ułatwiają porównania.",
                            "Privada y opcional. Fotos de frente y lado con luz similar facilitan las comparaciones.",
                            "Privat und optional. Front- und Seitenfotos bei ähnlichem Licht machen Vergleiche leichter.",
                            "Privée et facultative. Les photos de face et de profil dans une lumière similaire facilitent les comparaisons.",
                            "Privada e opcional. Fotos de frente e lado com luz parecida facilitam comparações."
                        )
                    )
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if hasSavedOnboardingPhoto {
                Label(
                    FlowLocalization.app(
                        "Your photo has been added",
                        "Twoje zdjęcie zostało dodane",
                        "Tu foto ha sido añadida",
                        "Dein Foto wurde hinzugefügt",
                        "Votre photo a été ajoutée",
                        "Sua foto foi adicionada"
                    ),
                    systemImage: "checkmark.circle.fill"
                )
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(Color.appEmerald)
                .frame(maxWidth: .infinity)
                .frame(minHeight: compact ? 38 : 46)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .fill(Color.appEmerald.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                .stroke(Color.appEmerald.opacity(0.35), lineWidth: 1)
                        )
                )
                .accessibilityIdentifier("onboarding.photo.added")
            } else {
                Button {
                    Haptics.medium()
                    showOnboardingPhotoSheet = true
                } label: {
                    Label(
                        FlowLocalization.app(
                            "Add starting photo",
                            "Dodaj zdjęcie startowe",
                            "Añadir foto inicial",
                            "Startfoto hinzufügen",
                            "Ajouter une photo initiale",
                            "Adicionar foto inicial"
                        ),
                        systemImage: "plus"
                    )
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: compact ? 40 : 46)
                }
                .buttonStyle(AppSecondaryButtonStyle(cornerRadius: AppRadius.md))
                .accessibilityIdentifier("onboarding.photo.add")

                Text(
                    FlowLocalization.app(
                        "You can skip this and add a photo later.",
                        "Możesz pominąć i dodać zdjęcie później.",
                        "Puedes saltarlo y añadir una foto más tarde.",
                        "Du kannst das überspringen und später ein Foto hinzufügen.",
                        "Vous pouvez passer cette étape et ajouter une photo plus tard.",
                        "Você pode pular e adicionar uma foto depois."
                    )
                )
                .font(AppTypography.micro)
                .foregroundStyle(AppColorRoles.textTertiary)
            }
        }
        .padding(compact ? AppSpacing.sm : AppSpacing.smmd)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                )
        )
    }

    @State var slideBlobAnimate = false
    @State var welcomeShimmerEnabled = true

    func ambientBlobs(for slideIndex: Int) -> some View {
        AmbientBlobsView(
            blobs: Self.blobSpecs(for: slideIndex),
            animate: slideBlobAnimate,
            shouldAnimate: shouldAnimate
        )
    }

    private var onboardingHealthProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: healthAuthorizationPhase == .completed ? "checkmark.circle.fill" : "bolt.heart.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(healthAuthorizationPhase == .completed ? Color.appAccent : Color.appAccent.opacity(0.9))

                Text(healthProgressTitle)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Spacer(minLength: 0)
            }

            GeometryReader { proxy in
                let progressWidth = safeProgressWidth(
                    containerWidth: proxy.size.width,
                    progress: healthAuthorizationVisualProgress,
                    minimum: 10
                )
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(AppColorRoles.surfaceInteractive)

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.appAccent.opacity(0.72), Color.appAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: progressWidth)
                }
            }
            .frame(height: 8)
        }
        .padding(AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(Color.appAccent.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(Color.appAccent.opacity(0.20), lineWidth: 1)
                )
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func introMetricsVisual(layout: OnboardingCardLayout) -> some View {
        VStack(spacing: layout.chartRowSpacing) {
            HStack(alignment: .top, spacing: IntroMetricsLayout.columnSpacing) {
                ForEach(Array(metricsPreviewCards.enumerated()), id: \.offset) { _, card in
                    DummyMiniMetricChartCard(
                        title: card.title,
                        value: card.value,
                        delta: card.delta,
                        tint: card.tint,
                        backgroundTint: card.backgroundTint,
                        points: card.points,
                        compact: layout.isCompact
                    )
                }
            }

            DummyAIInsightCard(
                title: metricsInsightCopy.title,
                lineOne: metricsInsightCopy.lineOne,
                lineTwo: metricsInsightCopy.lineTwo,
                tip: metricsInsightCopy.tip,
                compact: layout.isCompact
            )
        }
    }

    @State var photoAfterAppeared = false
    @State var healthCardsAppeared = false
    @State var shieldGlowPhase = false

    private func onboardingInputCard<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        AppGlassCard(depth: .elevated, cornerRadius: 28, tint: Color.appAccent, contentPadding: 16) {
            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    content()
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? AppSpacing.md : AppSpacing.xl)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focusedMeasurementKind) { _, kind in
                    guard let kind else { return }
                    scrollFocusedMeasurement(kind, with: scrollProxy)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)
    }

    private func measurementFieldID(_ kind: MetricKind) -> String {
        "onboarding.measurement.field.\(kind.rawValue)"
    }

    private func scrollFocusedMeasurement(_ kind: MetricKind, with proxy: ScrollViewProxy) {
        let delay: TimeInterval = shouldAnimate ? 0.12 : 0.02
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard focusedMeasurementKind == kind else { return }
            if shouldAnimate {
                withAnimation(AppMotion.standard) {
                    proxy.scrollTo(measurementFieldID(kind), anchor: .center)
                }
            } else {
                proxy.scrollTo(measurementFieldID(kind), anchor: .center)
            }
        }
    }

    private func safeProgressWidth(containerWidth: CGFloat, progress: CGFloat, minimum: CGFloat) -> CGFloat {
        guard containerWidth.isFinite, containerWidth > 0 else { return 0 }
        let clampedProgress = progress.isFinite ? min(max(progress, 0), 1) : 0
        let clampedMinimum = minimum.isFinite ? max(minimum, 0) : 0
        return min(max(containerWidth * clampedProgress, clampedMinimum), containerWidth)
    }

    private func flowSummaryRow(title: String, value: String, multilineValue: Bool = false) -> some View {
        HStack(alignment: multilineValue ? .top : .center, spacing: AppSpacing.sm) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
                .frame(minWidth: 72, alignment: .leading)

            Spacer(minLength: 0)

            Text(value)
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(AppColorRoles.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(multilineValue ? nil : 1)
                .fixedSize(horizontal: false, vertical: multilineValue)
        }
    }

    private func flowChipList(labels: [String]) -> some View {
        FlowLayout(spacing: 10) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppColorRoles.surfaceInteractive)
                    )
            }
        }
    }

    private func recommendedMetricsBanner(for priority: OnboardingPriority) -> some View {
        let metrics = GoalMetricPack.recommendedKinds(for: priority)
        let metricTitles = metrics.map(\.title)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appAccent)

                Text(FlowLocalization.app(
                    "We'll start with",
                    "Zaczniemy od",
                    "Empezaremos con",
                    "Wir starten mit",
                    "Nous allons commencer par",
                    "Vamos começar com"
                ))
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(AppColorRoles.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            }

            FlowLayout(spacing: 8) {
                ForEach(metricTitles, id: \.self) { title in
                    Text(title)
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppColorRoles.surfaceInteractive)
                        )
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.appAccent.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.appAccent.opacity(0.24), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            FlowLocalization.app(
                "Recommended starting metrics: %@",
                "Rekomendowane metryki startowe: %@",
                "Metricas iniciales recomendadas: %@",
                "Empfohlene Startmetriken: %@",
                "Indicateurs de depart recommandes : %@",
                "Metricas iniciais recomendadas: %@"
            )
            .replacingOccurrences(of: "%@", with: metricTitles.joined(separator: ", "))
        )
    }

    var effectiveNameForGreeting: String? {
        let trimmedInput = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInput.isEmpty { return trimmedInput }
        let trimmedStored = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStored.isEmpty { return trimmedStored }
        return nil
    }

    private var metricsStepTitle: String {
        if let name = effectiveNameForGreeting {
            switch resolvedPriority {
            case .loseWeight:
                return FlowLocalization.app(
                    "\(name), start with weight and waist.",
                    "\(name), zacznij od wagi i pasa.",
                    "\(name), empieza con peso y cintura.",
                    "\(name), starte mit Gewicht und Taille.",
                    "\(name), commencez par le poids et la taille.",
                    "\(name), comece com peso e cintura."
                )
            case .buildMuscle:
                return FlowLocalization.app(
                    "\(name), chest and both arms will tell the story.",
                    "\(name), klatka i oba ramiona pokażą prawdziwy progres.",
                    "\(name), pecho y ambos brazos contarán la historia.",
                    "\(name), Brust und beide Arme erzählen die Geschichte.",
                    "\(name), le torse et les deux bras raconteront l'histoire.",
                    "\(name), peito e os dois braços vão contar a história."
                )
            case .improveHealth:
                return FlowLocalization.app(
                    "\(name), waist and chest will keep this grounded.",
                    "\(name), pas i klatka dadzą tu najlepszy obraz.",
                    "\(name), cintura y pecho mantendrán esto claro.",
                    "\(name), Taille und Brust halten das hier geerdet.",
                    "\(name), la taille et le torse garderont cela lisible.",
                    "\(name), cintura e peito vão dar o melhor sinal aqui."
                )
            }
        }

        switch resolvedPriority {
        case .loseWeight:
            return FlowLocalization.app(
                "Start with weight and waist.",
                "Zacznij od wagi i pasa.",
                "Empieza con peso y cintura.",
                "Starte mit Gewicht und Taille.",
                "Commencez par le poids et la taille.",
                "Comece com peso e cintura."
            )
        case .buildMuscle:
            return FlowLocalization.app(
                "Chest and both arms will tell the story.",
                "Klatka i oba ramiona pokażą prawdziwy progres.",
                "Pecho y ambos brazos contarán la historia.",
                "Brust und beide Arme erzählen die Geschichte.",
                "Le torse et les deux bras raconteront l'histoire.",
                "Peito e os dois braços vão contar a história."
            )
        case .improveHealth:
            return FlowLocalization.app(
                "Waist and chest will keep this grounded.",
                "Pas i klatka dadzą tu najlepszy obraz.",
                "Cintura y pecho mantendrán esto claro.",
                "Taille und Brust halten das hier geerdet.",
                "La taille et le torse garderont cela lisible.",
                "Cintura e peito vão dar o melhor sinal aqui."
            )
        }
    }

    private var metricsStepSubtitle: String {
        switch resolvedPriority {
        case .loseWeight:
            return FlowLocalization.app(
                "Weight shows pace. Waist confirms whether fat loss is actually happening.",
                "Waga pokazuje tempo. Pas potwierdza, czy utrata tkanki tłuszczowej naprawdę zachodzi.",
                "El peso muestra el ritmo. La cintura confirma si la pérdida de grasa realmente ocurre.",
                "Gewicht zeigt das Tempo. Die Taille bestätigt, ob Fettverlust wirklich passiert.",
                "Le poids montre le rythme. La taille confirme si la perte de graisse se produit vraiment.",
                "O peso mostra o ritmo. A cintura confirma se a perda de gordura está mesmo acontecendo."
            )
        case .buildMuscle:
            return FlowLocalization.app(
                "These two measurements surface muscle gain earlier than the scale will.",
                "Te dwie metryki pokażą budowę mięśni wcześniej niż sama waga.",
                "Estas dos medidas muestran ganancia muscular antes que la báscula.",
                "Diese zwei Messwerte zeigen Muskelaufbau früher als die Waage.",
                "Ces deux mesures révèlent le gain musculaire plus tôt que la balance.",
                "Essas duas medidas mostram ganho muscular antes da balança."
            )
        case .improveHealth:
            return FlowLocalization.app(
                "Waist and chest together make recomp easier to trust when weight is noisy.",
                "Pas i klatka razem ułatwiają ocenę rekompozycji, gdy waga szumi.",
                "Cintura y pecho juntos facilitan confiar en la recomposición cuando el peso mete ruido.",
                "Taille und Brust zusammen machen Recomp leichter lesbar, wenn das Gewicht rauscht.",
                "La taille et le torse ensemble rendent la recomposition plus fiable quand le poids est bruité.",
                "Cintura e peito juntos tornam a recomposição mais clara quando o peso oscila."
            )
        }
    }

    var onboardingBeforeAssetName: String {
        let preferred: String
        switch resolvedPriority {
        case .loseWeight:
            preferred = "onboarding-before-lose-weight"
        case .buildMuscle:
            preferred = "onboarding-before-build-muscle"
        case .improveHealth:
            preferred = "onboarding-before-recomp"
        }
        return assetName(preferred: preferred, fallback: "onboarding-before")
    }

    var onboardingAfterAssetName: String {
        let preferred: String
        switch resolvedPriority {
        case .loseWeight:
            preferred = "onboarding-after-lose-weight"
        case .buildMuscle:
            preferred = "onboarding-after-build-muscle"
        case .improveHealth:
            preferred = "onboarding-after-recomp"
        }
        return assetName(preferred: preferred, fallback: "onboarding-after")
    }

    private func assetName(preferred: String, fallback: String) -> String {
        UIImage(named: preferred) == nil ? fallback : preferred
    }

    private func handleAppear() {
        guard !hasTrackedStart else { return }
        hasTrackedStart = true
        nameInput = userName
        selectedPriority = OnboardingPriority(rawValue: onboardingPrimaryGoalRaw)
        Analytics.shared.track(
            AnalyticsEvents.onboardingSessionStarted(
                entrypoint: "root",
                restoredState: hasRestoredInputState
            )
        )
        trackCurrentStep()
        syncUITestBridge(stepIndex: overallStepIndex)
        triggerSlideAppearance()
        slideBlobAnimate = true
    }

    private func triggerSlideAppearance() {
        slideAppeared = false
        if shouldAnimate {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(AppMotion.sectionEnter) {
                    slideAppeared = true
                }
            }
        } else {
            slideAppeared = true
        }
    }

    private func trackCurrentStep() {
        Analytics.shared.track(
            AnalyticsEvents.onboardingStepViewed(
                step: currentStep.analyticsName,
                stepIndex: currentStep.rawValue + 1,
                stepCount: onboardingStepCount
            )
        )
    }

    private func syncUITestBridge(stepIndex: Int) {
        guard isUITestOnboardingMode else { return }
        OnboardingUITestBridge.shared.update(currentStepIndex: stepIndex)
    }

    private func goToPreviousStep() {
        guard canGoBack,
              let previous = InputStep(rawValue: currentStep.rawValue - 1) else {
            return
        }
        dismissKeyboardFocus()
        animateToInputStep(previous)
    }

    private func goToNextStep() {
        seedFirstMeasurementForUITestsIfNeeded()
        guard isPrimaryEnabled || (isUITestOnboardingMode && currentStep == .startingPoint) else { return }
        switch currentStep {
        case .welcome:
            Analytics.shared.track(
                AnalyticsEvents.onboardingStepCompleted(
                    step: InputStep.welcome.analyticsName,
                    stepIndex: InputStep.welcome.rawValue + 1
                )
            )
            animateToInputStep(.goal)
        case .goal:
            persistProfileSelections()
            animateToInputStep(.startingPoint)
        case .startingPoint:
            if !hasSavedFirstMeasurement && !hasAnyFirstMeasurementInput {
                guard didSetReminderRhythm else { return }
            } else {
                guard saveFirstMeasurementIfNeeded() else { return }
            }
            completeStepAndAdvance(from: .startingPoint, to: .rhythm)
        case .rhythm:
            if isReminderRhythmSet {
                completeStepAndAdvance(from: .rhythm, to: .boosters)
            } else {
                enableReminderRhythm()
            }
        case .boosters:
            completeStepAndAdvance(from: .boosters, to: .plan)
        case .plan:
            onboardingSkippedHealthKit = !isSyncEnabled
            Analytics.shared.track(
                AnalyticsEvents.onboardingStepCompleted(
                    step: InputStep.plan.analyticsName,
                    stepIndex: InputStep.plan.rawValue + 1
                )
            )
            finishOnboarding()
        }
    }

    private func skipCurrentStep() {
        Analytics.shared.track(
            AnalyticsEvents.onboardingStepSkipped(
                step: currentStep.analyticsName,
                stepIndex: currentStep.rawValue + 1,
                skipReason: "user_skipped"
            )
        )

        switch currentStep {
        case .welcome:
            animateToInputStep(.goal)
        case .goal:
            animateToInputStep(.startingPoint)
        case .startingPoint:
            firstMeasurementErrorMessage = nil
            animateToInputStep(.rhythm)
        case .rhythm:
            onboardingSkippedReminders = true
            animateToInputStep(.boosters)
        case .boosters:
            onboardingSkippedHealthKit = !isSyncEnabled
            animateToInputStep(.plan)
        case .plan:
            finishOnboarding()
        }
    }

    private func completeStepAndAdvance(from completedStep: InputStep, to nextStep: InputStep) {
        Analytics.shared.track(
            AnalyticsEvents.onboardingStepCompleted(
                step: completedStep.analyticsName,
                stepIndex: completedStep.rawValue + 1
            )
        )
        animateToInputStep(nextStep)
    }

    private func saveFirstMeasurementIfNeeded() -> Bool {
        if hasSavedFirstMeasurement {
            return true
        }
        guard let entries = makeFirstMeasurementSaveEntries() else {
            return false
        }

        isSavingFirstMeasurement = true
        defer { isSavingFirstMeasurement = false }

        do {
            try effects.saveFirstMeasurement(
                entries: entries,
                date: AppClock.now,
                unitsSystem: unitsSystem,
                context: modelContext
            )
            firstMeasurementErrorMessage = nil
            hasSavedFirstMeasurement = true
            Haptics.success()
            return true
        } catch {
            firstMeasurementErrorMessage = FlowLocalization.app(
                "Could not save this starting point. Try again.",
                "Nie udało się zapisać punktu startowego. Spróbuj ponownie.",
                "No se pudo guardar este punto de partida. Inténtalo de nuevo.",
                "Dieser Startpunkt konnte nicht gespeichert werden. Bitte versuche es erneut.",
                "Impossible d'enregistrer ce point de départ. Réessayez.",
                "Não foi possível salvar este ponto de partida. Tente novamente."
            )
            return false
        }
    }

    private func makeFirstMeasurementSaveEntries() -> [QuickAddSaveService.Entry]? {
        var entries: [QuickAddSaveService.Entry] = []

        for kind in startingPointKinds {
            let rawValue = firstMeasurementEntries[kind]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !rawValue.isEmpty else { continue }

            guard let displayValue = parseDisplayValue(rawValue) else {
                firstMeasurementErrorMessage = FlowLocalization.app(
                    "Enter a valid number for %@.",
                    "Wpisz poprawną liczbę dla %@.",
                    "Introduce un número válido para %@.",
                    "Gib eine gültige Zahl für %@ ein.",
                    "Saisissez un nombre valide pour %@.",
                    "Digite um número válido para %@."
                )
                .replacingOccurrences(of: "%@", with: kind.title)
                return nil
            }

            let validation = MetricInputValidator.validateMetricDisplayValue(
                displayValue,
                kind: kind,
                unitsSystem: unitsSystem
            )
            guard validation.isValid else {
                firstMeasurementErrorMessage = validation.message
                return nil
            }

            entries.append(
                QuickAddSaveService.Entry(
                    kind: kind,
                    metricValue: kind.valueToMetric(fromDisplay: displayValue, unitsSystem: unitsSystem)
                )
            )
        }

        guard !entries.isEmpty else {
            firstMeasurementErrorMessage = FlowLocalization.app(
                "Add at least one value to save your starting point.",
                "Dodaj przynajmniej jedną wartość, aby zapisać punkt startowy.",
                "Añade al menos un valor para guardar tu punto de partida.",
                "Füge mindestens einen Wert hinzu, um deinen Startpunkt zu speichern.",
                "Ajoutez au moins une valeur pour enregistrer votre point de départ.",
                "Adicione pelo menos um valor para salvar seu ponto de partida."
            )
            return nil
        }

        return entries
    }

    private func parseDisplayValue(_ rawValue: String?) -> Double? {
        guard let rawValue else { return nil }
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    private func seedFirstMeasurementForUITestsIfNeeded() {
        guard isUITestOnboardingMode,
              currentStep == .startingPoint,
              !hasSavedFirstMeasurement,
              !hasAnyFirstMeasurementInput,
              let firstKind = startingPointKinds.first else {
            return
        }

        switch firstKind.unitCategory {
        case .weight:
            firstMeasurementEntries[firstKind] = unitsSystem == "imperial" ? "165" : "75"
        case .length:
            firstMeasurementEntries[firstKind] = unitsSystem == "imperial" ? "35" : "90"
        case .percent:
            firstMeasurementEntries[firstKind] = "20"
        }
    }

    private func animateToInputStep(_ step: InputStep) {
        isNameFieldFocused = false
        focusedMeasurementKind = nil
        if isUITestOnboardingMode {
            currentStep = step
        } else if shouldAnimate {
            withAnimation(AppMotion.emphasized) {
                currentStep = step
            }
        } else {
            currentStep = step
        }
    }

    private func persistProfileSelections() {
        let priority = resolvedPriority
        selectedPriority = priority
        onboardingPrimaryGoalRaw = priority.rawValue
        applyMetricPackIfNeeded()
        Analytics.shared.track(AnalyticsEvents.onboardingPrioritySelected(priority: priority.analyticsValue))
        Analytics.shared.track(
            AnalyticsEvents.onboardingStepCompleted(
                step: InputStep.goal.analyticsName,
                stepIndex: InputStep.goal.rawValue + 1
            )
        )
    }

    private func selectGoal(_ priority: OnboardingPriority) {
        let isReselect = selectedPriority == priority
        selectedPriority = isReselect ? nil : priority
    }

    // MARK: - Reminder rhythm (v5)

    private func rhythmReminderDate() -> Date {
        var components = DateComponents()
        components.weekday = rhythmWeekday
        components.hour = rhythmHour
        components.minute = 0
        return Calendar.current.nextDate(
            after: AppClock.now,
            matching: components,
            matchingPolicy: .nextTime
        ) ?? AppClock.now
    }

    private func eveningReminderDate() -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: AppClock.now)
        components.hour = 20
        components.minute = 0
        let candidate = calendar.date(from: components) ?? AppClock.now
        if candidate > AppClock.now {
            return candidate
        }
        return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
    }

    private func enableReminderRhythm() {
        guard !isSchedulingRhythm else { return }
        isSchedulingRhythm = true
        Task { @MainActor in
            defer { isSchedulingRhythm = false }
            let granted = await effects.requestNotificationAuthorization()
            effects.setNotificationsEnabled(granted)
            Analytics.shared.track(
                AnalyticsEvents.notificationsPermissionResolved(
                    source: .activation,
                    result: granted ? "granted" : "denied"
                )
            )
            if granted {
                effects.upsertReminder(date: rhythmReminderDate(), repeatRule: .weekly)
                onboardingSkippedReminders = false
                didSetReminderRhythm = true
                Analytics.shared.track(
                    AnalyticsEvents.remindersSeeded(source: .activation, repeatRule: .weekly)
                )
                Haptics.success()
            } else {
                onboardingSkippedReminders = true
            }
            completeStepAndAdvance(from: .rhythm, to: .boosters)
        }
    }

    private func triggerEveningReminder() {
        guard !isSchedulingRhythm else { return }
        isSchedulingRhythm = true
        Task { @MainActor in
            defer { isSchedulingRhythm = false }
            let granted = await effects.requestNotificationAuthorization()
            effects.setNotificationsEnabled(granted)
            Analytics.shared.track(
                AnalyticsEvents.notificationsPermissionResolved(
                    source: .activation,
                    result: granted ? "granted" : "denied"
                )
            )
            if granted {
                effects.upsertReminder(date: eveningReminderDate(), repeatRule: .once)
                onboardingSkippedReminders = false
                didSetReminderRhythm = true
                Analytics.shared.track(
                    AnalyticsEvents.remindersSeeded(source: .activation, repeatRule: .once)
                )
                Haptics.success()
            } else {
                onboardingSkippedReminders = true
            }
        }
    }

    private func applyMetricPackIfNeeded() {
        let customizedMetricsBefore = effects.hasCustomizedMetrics()
        guard !customizedMetricsBefore else { return }
        let trackedKinds = GoalMetricPack.trackedKinds(for: resolvedPriority)
        effects.applyMetricPack(trackedKinds)
        Analytics.shared.track(
            AnalyticsEvents.onboardingMetricPackApplied(
                priority: resolvedPriority.analyticsValue,
                packID: resolvedPriority.rawValue,
                metricsCount: trackedKinds.count,
                customizedMetricsBefore: customizedMetricsBefore
            )
        )
    }

    private func requestHealthAccess() {
        guard !isRequestingHealthKit else { return }
        isRequestingHealthKit = true
        updateHealthAuthorizationPhase(.preparing)
        Analytics.shared.track(AnalyticsEvents.onboardingHealthPermissionPrompted(source: "onboarding"))

        Task { @MainActor in
            defer { isRequestingHealthKit = false }
            do {
                updateHealthAuthorizationPhase(.requestingSystemPrompt)
                try await effects.requestHealthKitAuthorization()
                isSyncEnabled = true
                onboardingSkippedHealthKit = false

                updateHealthAuthorizationPhase(.importingProfile)
                let profile = await effects.importProfileFromHealthIfAvailable()
                if let age = profile.age, age > 0 {
                    userAge = age
                }
                if let height = profile.height, height > 0 {
                    manualHeight = height
                }

                var imported: [String] = [
                    FlowLocalization.app("Health connected", "Health połączone", "Salud conectada", "Health verbunden", "Santé connectée", "Health conectado")
                ]
                if profile.age != nil {
                    imported.append(FlowLocalization.app("Age imported", "Zaimportowano wiek", "Edad importada", "Alter importiert", "Âge importé", "Idade importada"))
                }
                if profile.height != nil {
                    imported.append(FlowLocalization.app("Height imported", "Zaimportowano wzrost", "Altura importada", "Größe importiert", "Taille importée", "Altura importada"))
                }
                healthStatusLines = imported
                updateHealthAuthorizationPhase(.completed)

                Analytics.shared.track(
                    AnalyticsEvents.onboardingHealthPermissionResolved(
                        source: "onboarding",
                        result: "granted",
                        importedAge: profile.age != nil,
                        importedHeight: profile.height != nil
                    )
                )
            } catch {
                isSyncEnabled = false
                onboardingSkippedHealthKit = true
                updateHealthAuthorizationPhase(.idle)
                healthStatusLines = [
                    FlowLocalization.app(
                        "You can connect Health later in Settings.",
                        "Health możesz połączyć później w Ustawieniach.",
                        "Puedes conectar Salud más tarde en Ajustes.",
                        "Du kannst Health später in den Einstellungen verbinden.",
                        "Vous pourrez connecter Santé plus tard dans Réglages.",
                        "Você pode conectar o Health depois nos Ajustes."
                    )
                ]
                Analytics.shared.track(
                    AnalyticsEvents.onboardingHealthPermissionResolved(
                        source: "onboarding",
                        result: "denied",
                        importedAge: false,
                        importedHeight: false
                    )
                )
            }
        }
    }

    private func updateHealthAuthorizationPhase(_ phase: HealthAuthorizationPhase) {
        healthAuthorizationPhase = phase

        let targetProgress: CGFloat
        switch phase {
        case .idle:
            targetProgress = 0
        case .preparing:
            targetProgress = 0.16
        case .requestingSystemPrompt:
            targetProgress = 0.48
        case .importingProfile:
            targetProgress = 0.82
        case .completed:
            targetProgress = 1
        }

        if shouldAnimate {
            withAnimation(.easeInOut(duration: 0.28)) {
                healthAuthorizationVisualProgress = targetProgress
            }
        } else {
            healthAuthorizationVisualProgress = targetProgress
        }
    }

    private func finishOnboarding() {
        let priority = resolvedPriority
        onboardingPrimaryGoalRaw = priority.rawValue
        applyMetricPackIfNeeded()
        let completedActivationTasks = initialActivationCompletedTaskIDs()
        activationCompletedTaskIDsRaw = completedActivationTasks.sorted().joined(separator: ",")
        if let nextActivationTask = initialActivationCurrentTask(completedTasks: completedActivationTasks) {
            activationCurrentTaskID = nextActivationTask.rawValue
            activationIsDismissed = false
        } else {
            activationCurrentTaskID = ""
            activationIsDismissed = true
        }
        activationSkippedTaskIDsRaw = ""
        onboardingFlowVersion = Int(AnalyticsEvents.onboardingFlowVersion) ?? 5

        if shouldAnimate {
            withAnimation(AppMotion.quick) {
                hasCompletedOnboarding = true
            }
        } else {
            hasCompletedOnboarding = true
        }

        Analytics.shared.track(
            AnalyticsEvents.onboardingCompleted(
                priority: priority.analyticsValue,
                healthConnected: isSyncEnabled,
                completedAllSteps: true
            )
        )
    }

    private func initialActivationCompletedTaskIDs() -> Set<String> {
        var completed = Set<String>()
        if hasSavedFirstMeasurement {
            completed.insert(ActivationTask.firstMeasurement.rawValue)
        }
        if hasSavedOnboardingPhoto {
            completed.insert(ActivationTask.addPhoto.rawValue)
        }
        if !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || userAge > 0 || manualHeight > 0 {
            completed.insert(ActivationTask.personalizeProfile.rawValue)
        }
        if isSyncEnabled {
            completed.insert(ActivationTask.connectHealth.rawValue)
        }
        return completed
    }

    private func initialActivationCurrentTask(completedTasks: Set<String>) -> ActivationTask? {
        [
            ActivationTask.firstMeasurement,
            .addPhoto
        ]
        .first { task in
            !completedTasks.contains(task.rawValue) && !isActivationTaskSatisfiedDuringOnboarding(task)
        }
    }

    private func isActivationTaskSatisfiedDuringOnboarding(_ task: ActivationTask) -> Bool {
        switch task {
        case .firstMeasurement:
            return hasSavedFirstMeasurement
        case .addPhoto:
            return hasSavedOnboardingPhoto
        case .personalizeProfile:
            return !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || userAge > 0 || manualHeight > 0
        case .connectHealth:
            return isSyncEnabled || onboardingSkippedHealthKit
        case .chooseMetrics, .setReminders, .explorePremium:
            return false
        }
    }

    private func onboardingLayout(for availableHeight: CGFloat) -> OnboardingCardLayout {
        if availableHeight < 720 {
            return .compact
        }
        return .regular
    }
    fileprivate static func blobSpecs(for slideIndex: Int) -> [AmbientBlobSpec] {
        switch slideIndex {
        case 0:
            return [
                AmbientBlobSpec(color: .appAccent, innerOpacity: 0.35, outerOpacity: 0.0, size: 320, blurRadius: 40, startRadius: 20, endRadius: 160, offsetA: CGSize(width: 30, height: -30), offsetB: CGSize(width: -20, height: 15)),
                AmbientBlobSpec(color: .cyan, innerOpacity: 0.20, outerOpacity: 0.0, size: 260, blurRadius: 30, startRadius: 15, endRadius: 130, offsetA: CGSize(width: -35, height: 30), offsetB: CGSize(width: 20, height: -15)),
                AmbientBlobSpec(color: .appIndigo, innerOpacity: 0.15, outerOpacity: 0.0, size: 200, blurRadius: 24, startRadius: 8, endRadius: 100, offsetA: CGSize(width: 15, height: -20), offsetB: CGSize(width: -25, height: 25)),
            ]
        case 1:
            return [
                AmbientBlobSpec(color: .appAccent, innerOpacity: 0.25, outerOpacity: 0.0, size: 300, blurRadius: 40, startRadius: 18, endRadius: 150, offsetA: CGSize(width: 35, height: -20), offsetB: CGSize(width: -15, height: 20)),
                AmbientBlobSpec(color: .appTeal, innerOpacity: 0.15, outerOpacity: 0.0, size: 250, blurRadius: 30, startRadius: 12, endRadius: 125, offsetA: CGSize(width: -30, height: 35), offsetB: CGSize(width: 25, height: -10)),
                AmbientBlobSpec(color: .cyan, innerOpacity: 0.10, outerOpacity: 0.0, size: 190, blurRadius: 24, startRadius: 8, endRadius: 95, offsetA: CGSize(width: 20, height: -30), offsetB: CGSize(width: -25, height: 18)),
            ]
        case 2:
            return [
                AmbientBlobSpec(color: .appRose, innerOpacity: 0.25, outerOpacity: 0.0, size: 310, blurRadius: 40, startRadius: 20, endRadius: 155, offsetA: CGSize(width: -30, height: -25), offsetB: CGSize(width: 18, height: 18)),
                AmbientBlobSpec(color: .appAccent, innerOpacity: 0.15, outerOpacity: 0.0, size: 240, blurRadius: 30, startRadius: 12, endRadius: 120, offsetA: CGSize(width: 40, height: 20), offsetB: CGSize(width: -22, height: -18)),
                AmbientBlobSpec(color: .appIndigo, innerOpacity: 0.10, outerOpacity: 0.0, size: 200, blurRadius: 24, startRadius: 8, endRadius: 100, offsetA: CGSize(width: -18, height: 30), offsetB: CGSize(width: 28, height: -25)),
            ]
        case 3:
            return [
                AmbientBlobSpec(color: .appEmerald, innerOpacity: 0.25, outerOpacity: 0.0, size: 300, blurRadius: 40, startRadius: 18, endRadius: 150, offsetA: CGSize(width: 25, height: -35), offsetB: CGSize(width: -18, height: 15)),
                AmbientBlobSpec(color: .appTeal, innerOpacity: 0.15, outerOpacity: 0.0, size: 240, blurRadius: 30, startRadius: 12, endRadius: 120, offsetA: CGSize(width: -40, height: 25), offsetB: CGSize(width: 15, height: -20)),
                AmbientBlobSpec(color: .appAccent, innerOpacity: 0.10, outerOpacity: 0.0, size: 180, blurRadius: 24, startRadius: 8, endRadius: 90, offsetA: CGSize(width: 18, height: 28), offsetB: CGSize(width: -30, height: -15)),
            ]
        default:
            return [
                AmbientBlobSpec(color: .appIndigo, innerOpacity: 0.25, outerOpacity: 0.0, size: 320, blurRadius: 40, startRadius: 20, endRadius: 160, offsetA: CGSize(width: -28, height: -30), offsetB: CGSize(width: 22, height: 10)),
                AmbientBlobSpec(color: .appAccent, innerOpacity: 0.15, outerOpacity: 0.0, size: 260, blurRadius: 30, startRadius: 14, endRadius: 130, offsetA: CGSize(width: 32, height: 28), offsetB: CGSize(width: -25, height: -18)),
                AmbientBlobSpec(color: .appCyan, innerOpacity: 0.10, outerOpacity: 0.0, size: 200, blurRadius: 24, startRadius: 8, endRadius: 100, offsetA: CGSize(width: -15, height: -25), offsetB: CGSize(width: 28, height: 22)),
            ]
        }
    }
}
