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
    @State var slideAppeared = false
    @FocusState private var isNameFieldFocused: Bool

    private let isUITestOnboardingMode = UITestArgument.isPresent(.onboardingMode)

    init(effects: OnboardingEffects? = nil) {
        self.effects = effects ?? .live
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
                "Continue",
                "Dalej",
                "Continuar",
                "Weiter",
                "Continuer",
                "Continuar"
            )
        case .profile:
            return FlowLocalization.app(
                "Create my starting point",
                "Utwórz punkt startowy",
                "Crear mi punto de partida",
                "Meinen Startpunkt erstellen",
                "Créer mon point de départ",
                "Criar meu ponto de partida"
            )
        case .metrics:
            if hasSavedFirstMeasurement {
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
        case .photos:
            return FlowLocalization.app(
                "Continue",
                "Dalej",
                "Continuar",
                "Weiter",
                "Continuer",
                "Continuar"
            )
        case .health:
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
        case .metrics:
            return !isSavingFirstMeasurement && !isRequestingHealthKit && (hasSavedFirstMeasurement || hasAnyFirstMeasurementInput)
        case .health:
            return !isRequestingHealthKit
        default:
            return true
        }
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

    private var hasAnyFirstMeasurementInput: Bool {
        recommendedKinds.contains { kind in
            !(firstMeasurementEntries[kind] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var firstMeasurementDisplayEntries: [BaselineDisplayEntry] {
        recommendedKinds.compactMap { kind in
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

    private let footerReservedHeight: CGFloat = 94

    var body: some View {
        ZStack {
            AppScreenBackground(topHeight: 400, tint: Color.appAccent.opacity(0.2))

            VStack(spacing: 0) {
                topBar

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.md)
                    .padding(.bottom, isFooterHidden ? 0 : footerReservedHeight)
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
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
        case .profile:
            onboardingInputCard {
                VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                    HStack(alignment: .top, spacing: 12) {
                        onboardingSlideHeader(
                            title: FlowLocalization.app(
                                "What's your name?",
                                "Jak masz na imię?",
                                "¿Cómo te llamas?",
                                "Wie heißt du?",
                                "Comment vous appelez-vous ?",
                                "Como você se chama?"
                            ),
                            subtitle: "",
                            titleSize: layout.headerTitleSize - 4
                        )

                        MeasureBuddyView(pose: .welcome, size: 72, idleAnimation: false)
                            .shadow(color: Color.appAccent.opacity(0.35), radius: 10, x: 0, y: 6)
                            .padding(.top, -4)
                    }

                    TextField(FlowLocalization.app("e.g. Alex", "np. Alex", "p. ej. Alex", "z. B. Alex", "p. ex. Alex", "ex. Alex"), text: $nameInput)
                        .textInputAutocapitalization(.words)
                        .font(.system(size: layout.nameFieldFontSize, weight: .semibold, design: .rounded))
                        .padding(.vertical, layout.nameFieldVerticalPadding)
                        .padding(.horizontal, AppSpacing.smmd)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                                .fill(AppColorRoles.surfaceInteractive)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                                .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                        )
                        .focused($isNameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { isNameFieldFocused = false }
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button(AppLocalization.string("Done")) {
                                    isNameFieldFocused = false
                                }
                            }
                        }
                        .accessibilityIdentifier("onboarding.name.field")

                    VStack(alignment: .leading, spacing: layout.groupSpacing) {
                        Text(
                            FlowLocalization.app(
                                "What do you want this app to help with first?",
                                "W czym ta aplikacja ma pomóc Ci najpierw?",
                                "¿En qué quieres que te ayude primero esta app?",
                                "Wobei soll dir diese App zuerst helfen?",
                                "Sur quoi voulez-vous que cette app vous aide en premier ?",
                                "Em que você quer que este app ajude primeiro?"
                            )
                        )
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                        Text(
                            FlowLocalization.app(
                                "This only chooses your starting metrics. You can change tracked metrics and set numeric goals later.",
                                "To tylko wybiera metryki startowe. Śledzone metryki i cele liczbowe zmienisz później.",
                                "Esto solo elige tus métricas iniciales. Podrás cambiar métricas y objetivos numéricos después.",
                                "Das wählt nur deine Startmetriken. Verfolgte Metriken und Zahlenziele kannst du später ändern.",
                                "Cela choisit seulement vos indicateurs de départ. Vous pourrez modifier les indicateurs suivis et les objectifs chiffrés plus tard.",
                                "Isso só escolhe suas métricas iniciais. Você pode mudar métricas acompanhadas e metas numéricas depois."
                            )
                        )
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                        ForEach(OnboardingPriority.allCases, id: \.self) { priority in
                            let isSelected = selectedPriority == priority
                            Button {
                                Haptics.selection()
                                selectedPriority = isSelected ? nil : priority
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
        case .metrics:
            onboardingInputCard {
                VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                    if hasSavedFirstMeasurement {
                        savedBaselineCard
                    } else {
                        OnboardingFirstMeasurementStep(
                            recommendedKinds: recommendedKinds,
                            entries: $firstMeasurementEntries,
                            unitsSystem: unitsSystem
                        )

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
                    }
                }
            }
        case .photos:
            onboardingInputCard {
                VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                    onboardingSlideHeader(
                        title: FlowLocalization.app(
                            "You have a starting point",
                            "Masz punkt startowy",
                            "Ya tienes un punto de partida",
                            "Du hast einen Startpunkt",
                            "Vous avez un point de départ",
                            "Você tem um ponto de partida"
                        ),
                        subtitle: FlowLocalization.app(
                            "The next check-in can show what changed. A photo is private and optional.",
                            "Następny check-in pokaże zmianę. Zdjęcie jest prywatne i opcjonalne.",
                            "El siguiente check-in podrá mostrar qué cambió. La foto es privada y opcional.",
                            "Der nächste Check-in kann zeigen, was sich verändert hat. Ein Foto ist privat und optional.",
                            "Le prochain check-in pourra montrer ce qui a changé. La photo est privée et facultative.",
                            "O próximo check-in pode mostrar o que mudou. A foto é privada e opcional."
                        ),
                        titleSize: layout.headerTitleSize
                    )

                    if hasSavedFirstMeasurement {
                        savedBaselineCard
                    } else {
                        skippedBaselineCard
                    }

                    startPhotoCard
                }
            }
        case .health:
            onboardingInputCard {
                VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                    onboardingSlideHeader(
                        title: FlowLocalization.app(
                            "Connect Health. Keep it private.",
                            "Połącz Zdrowie. Zachowaj prywatność.",
                            "Conecta Salud. Mantén la privacidad.",
                            "Health verbinden. Privat bleiben.",
                            "Connectez Santé. Gardez le contrôle.",
                            "Conecte o Health. Mantenha a privacidade."
                        ),
                        subtitle: FlowLocalization.app(
                            "Apple Health is optional. Your measurements and photos stay on device, and you can still log everything manually.",
                            "Apple Health jest opcjonalne. Twoje pomiary i zdjęcia zostają na urządzeniu, a wszystko nadal możesz wpisywać ręcznie.",
                            "Apple Health es opcional. Tus medidas y fotos se quedan en el dispositivo y también puedes registrar todo manualmente.",
                            "Apple Health ist optional. Deine Messwerte und Fotos bleiben auf dem Gerät und du kannst alles auch manuell eintragen.",
                            "Apple Health est facultatif. Vos mesures et photos restent sur l'appareil, et vous pouvez tout enregistrer manuellement.",
                            "O Apple Health é opcional. Suas medidas e fotos ficam no aparelho, e você ainda pode registrar tudo manualmente."
                        ),
                        titleSize: layout.headerTitleSize
                    )

                    flowChipList(labels: recommendedKinds.map(\.title))

                    if isRequestingHealthKit {
                        onboardingHealthProgress
                    }

                    if !healthStatusLines.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(healthStatusLines, id: \.self) { line in
                                Label(line, systemImage: "checkmark.circle.fill")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(Color.appAccent)
                            }
                        }
                    }

                    Button(action: requestHealthAccess) {
                        HStack(spacing: 10) {
                            if isRequestingHealthKit {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(AppColorRoles.textOnAccent)
                            }
                            Text(healthButtonTitle)
                        }
                        .foregroundStyle(AppColorRoles.textOnAccent)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                    }
                    .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
                    .disabled(isRequestingHealthKit || isSyncEnabled)
                    .accessibilityIdentifier("onboarding.health.allow")

                    privacyCard(compact: layout.isCompact)
                }
            }
            .task {
                guard !didPrewarmHealthKitAuthorization else { return }
                didPrewarmHealthKitAuthorization = true
                await effects.prewarmHealthKitAuthorization()
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

    private var startPhotoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: hasSavedOnboardingPhoto ? "photo.badge.checkmark.fill" : "camera.viewfinder")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 38, height: 38)
                    .background(Color.appAccent.opacity(0.13))
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

            Button {
                Haptics.medium()
                showOnboardingPhotoSheet = true
            } label: {
                Label(
                    hasSavedOnboardingPhoto
                        ? FlowLocalization.app(
                            "Add another photo",
                            "Dodaj kolejne zdjęcie",
                            "Añadir otra foto",
                            "Weiteres Foto hinzufügen",
                            "Ajouter une autre photo",
                            "Adicionar outra foto"
                        )
                        : FlowLocalization.app(
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
                .frame(minHeight: 46)
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
                        .frame(width: max(proxy.size.width * healthAuthorizationVisualProgress, 10))
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

    private func onboardingInputCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        AppGlassCard(depth: .elevated, cornerRadius: 28, tint: Color.appAccent, contentPadding: 20) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 12)
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
        animateToInputStep(previous)
    }

    private func goToNextStep() {
        seedFirstMeasurementForUITestsIfNeeded()
        guard isPrimaryEnabled else { return }
        switch currentStep {
        case .welcome:
            Analytics.shared.track(
                AnalyticsEvents.onboardingStepCompleted(
                    step: InputStep.welcome.analyticsName,
                    stepIndex: InputStep.welcome.rawValue + 1
                )
            )
            animateToInputStep(.profile)
        case .profile:
            persistProfileSelections()
            animateToInputStep(.metrics)
        case .metrics:
            guard saveFirstMeasurementIfNeeded() else { return }
            completeStepAndAdvance(from: .metrics, to: .photos)
        case .photos:
            completeStepAndAdvance(from: .photos, to: .health)
        case .health:
            onboardingSkippedHealthKit = !isSyncEnabled
            Analytics.shared.track(
                AnalyticsEvents.onboardingStepCompleted(
                    step: InputStep.health.analyticsName,
                    stepIndex: InputStep.health.rawValue + 1
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
            animateToInputStep(.profile)
        case .profile:
            animateToInputStep(.metrics)
        case .metrics:
            firstMeasurementErrorMessage = nil
            animateToInputStep(.photos)
        case .photos:
            animateToInputStep(.health)
        case .health:
            onboardingSkippedHealthKit = true
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

        for kind in recommendedKinds {
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
              currentStep == .metrics,
              !hasSavedFirstMeasurement,
              !hasAnyFirstMeasurementInput,
              let firstKind = recommendedKinds.first else {
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
        let trimmed = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            userName = trimmed
        }
        let priority = resolvedPriority
        selectedPriority = priority
        onboardingPrimaryGoalRaw = priority.rawValue
        applyMetricPackIfNeeded()
        Analytics.shared.track(AnalyticsEvents.onboardingPrioritySelected(priority: priority.analyticsValue))
        Analytics.shared.track(
            AnalyticsEvents.onboardingStepCompleted(
                step: InputStep.profile.analyticsName,
                stepIndex: InputStep.profile.rawValue + 1
            )
        )
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
        onboardingFlowVersion = Int(AnalyticsEvents.onboardingFlowVersion) ?? 4

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
        if availableHeight < 620 {
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
