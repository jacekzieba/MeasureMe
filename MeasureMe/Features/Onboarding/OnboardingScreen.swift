import SwiftUI
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
    @AppSetting(\.health.isSyncEnabled) private var isSyncEnabled: Bool = false
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var currentStep: InputStep = .welcome
    @State private var nameInput: String = ""
    @State private var selectedPriority: OnboardingPriority?
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

    private var isSkipVisible: Bool { currentStep != .welcome && currentStep != .startingPoint }
    private var isFooterHidden: Bool { currentStep == .goal || currentStep == .startingPoint || currentStep == .healthImport }

    private var primaryButtonTitle: String {
        switch currentStep {
        case .welcome:
            return FlowLocalization.app(
                "Get started",
                "Zaczynamy",
                "Continuar",
                "Weiter",
                "Commencer",
                "Começar"
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
            return FlowLocalization.app(
                "Import from Apple Health",
                "Importuj z Apple Health",
                "Importar desde Apple Health",
                "Aus Apple Health importieren",
                "Importer depuis Apple Health",
                "Importar do Apple Health"
            )
        case .healthImport:
            return FlowLocalization.app(
                "Continue",
                "Dalej",
                "Continuar",
                "Weiter",
                "Continuer",
                "Continuar"
            )
        }
    }

    private var skipButtonTitle: String {
        FlowLocalization.app("Skip for now", "Pomiń na razie", "Omitir por ahora", "Vorerst überspringen", "Passer pour l'instant", "Pular por enquanto")
    }

    private var isPrimaryEnabled: Bool {
        switch currentStep {
        case .goal:
            return selectedPriority != nil || !onboardingPrimaryGoalRaw.isEmpty
        case .healthImport:
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

    private var explicitPriority: OnboardingPriority? {
        selectedPriority ?? OnboardingPriority(rawValue: onboardingPrimaryGoalRaw)
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

    private var startingPointTitle: String {
        switch resolvedPriority {
        case .loseWeight:
            return FlowLocalization.app("Start with Weight + Waist", "Zacznij od Wagi + Pasa", "Empieza con Peso + Cintura", "Starte mit Gewicht + Taille", "Commencez par Poids + Taille", "Comece com Peso + Cintura")
        case .buildMuscle:
            return FlowLocalization.app("Start with Weight + Key Measurements", "Zacznij od Wagi + Kluczowych pomiarów", "Empieza con Peso + medidas clave", "Starte mit Gewicht + wichtigen Messwerten", "Commencez par Poids + mesures clés", "Comece com Peso + medições-chave")
        case .improveHealth:
            return FlowLocalization.app("Track both fat loss and muscle gain", "Śledź utratę tłuszczu i przyrost mięśni", "Sigue pérdida de grasa y ganancia muscular", "Verfolge Fettverlust und Muskelaufbau", "Suivez perte de graisse et gain musculaire", "Acompanhe perda de gordura e ganho muscular")
        case .trackHealth:
            return FlowLocalization.app("Build a simple health baseline", "Zbuduj prosty punkt zdrowia", "Crea una base simple de salud", "Baue eine einfache Gesundheitsbasis", "Créez une base santé simple", "Crie uma base simples de saúde")
        }
    }

    private var startingPointBody: String {
        switch resolvedPriority {
        case .loseWeight:
            return FlowLocalization.app("Weight shows the pace. Waist helps confirm real body change.", "Waga pokazuje tempo. Pas pomaga potwierdzić realną zmianę ciała.", "El peso muestra el ritmo. La cintura ayuda a confirmar el cambio real.", "Gewicht zeigt das Tempo. Die Taille bestätigt echte Veränderung.", "Le poids montre le rythme. La taille confirme le vrai changement.", "O peso mostra o ritmo. A cintura ajuda a confirmar mudança real.")
        case .buildMuscle:
            return FlowLocalization.app("Weight shows overall change. Body measurements help track muscle growth.", "Waga pokazuje ogólną zmianę. Pomiary ciała pomagają śledzić wzrost mięśni.", "El peso muestra el cambio general. Las medidas ayudan a seguir músculo.", "Gewicht zeigt die Gesamtänderung. Körpermaße zeigen Muskelwachstum.", "Le poids montre l'évolution globale. Les mesures suivent la croissance musculaire.", "O peso mostra a mudança geral. Medidas corporais acompanham crescimento muscular.")
        case .improveHealth:
            return FlowLocalization.app("Weight may move slowly. Waist, photos and measurements show the bigger picture.", "Waga może zmieniać się wolno. Pas, zdjęcia i pomiary pokazują większy obraz.", "El peso puede moverse lento. Cintura, fotos y medidas muestran el panorama.", "Gewicht bewegt sich oft langsam. Taille, Fotos und Maße zeigen das Gesamtbild.", "Le poids peut bouger lentement. Taille, photos et mesures montrent l'ensemble.", "O peso pode mudar devagar. Cintura, fotos e medidas mostram o quadro maior.")
        case .trackHealth:
            return FlowLocalization.app("Start with a few consistent measurements and watch long-term trends.", "Zacznij od kilku regularnych pomiarów i obserwuj długoterminowe trendy.", "Empieza con pocas medidas constantes y observa tendencias a largo plazo.", "Starte mit wenigen konstanten Messwerten und beobachte Langzeittrends.", "Commencez avec quelques mesures régulières et suivez les tendances.", "Comece com poucas medições consistentes e acompanhe tendências de longo prazo.")
        }
    }

    private var startingPointMetricLabels: [String] {
        switch resolvedPriority {
        case .loseWeight, .trackHealth:
            return [MetricKind.weight.title, MetricKind.waist.title]
        case .buildMuscle:
            return [
                MetricKind.weight.title,
                MetricKind.chest.title,
                FlowLocalization.app("Arms", "Ramiona", "Brazos", "Arme", "Bras", "Braços"),
                MetricKind.waist.title
            ]
        case .improveHealth:
            return [
                MetricKind.weight.title,
                MetricKind.waist.title,
                FlowLocalization.app("Photos", "Zdjęcia", "Fotos", "Fotos", "Photos", "Fotos"),
                FlowLocalization.app("Chest / Arms", "Klatka / ramiona", "Pecho / brazos", "Brust / Arme", "Torse / bras", "Peito / braços")
            ]
        }
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

            if isSkipVisible {
                skipLink
            } else {
                Color.clear
                    .frame(width: 116, height: 44)
            }
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
        case .goal:
            onboardingInputCard {
                goalSelectionContent(layout: layout)
            }
        case .startingPoint:
            onboardingInputCard {
                startingPointContent(layout: layout)
            }
        case .healthImport:
            onboardingInputCard {
                healthImportContent(layout: layout)
            }
            .task {
                guard !didPrewarmHealthKitAuthorization else { return }
                didPrewarmHealthKitAuthorization = true
                await effects.prewarmHealthKitAuthorization()
            }
        }
    }

    @State var slideBlobAnimate = false
    @State var welcomeShimmerEnabled = true

    private func goalSelectionContent(layout: OnboardingCardLayout) -> some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            HStack(alignment: .top, spacing: 12) {
                onboardingSlideHeader(
                    title: FlowLocalization.app(
                        "What are you working toward?",
                        "Nad czym pracujesz?",
                        "¿En qué estás trabajando?",
                        "Woran arbeitest du?",
                        "Quel est votre objectif ?",
                        "No que você está trabalhando?"
                    ),
                    subtitle: FlowLocalization.app(
                        "Choose one goal to shape your first baseline.",
                        "Wybierz jeden cel, aby dopasować pierwszy punkt startowy.",
                        "Elige un objetivo para adaptar tu primera base.",
                        "Wähle ein Ziel, damit deine erste Basis passt.",
                        "Choisissez un objectif pour adapter votre première base.",
                        "Escolha um objetivo para ajustar sua primeira base."
                    ),
                    titleSize: layout.headerTitleSize - 2
                )

                MeasureBuddyView(pose: .goals, size: 76, idleAnimation: false)
                    .shadow(color: Color.appAccent.opacity(0.28), radius: 10, x: 0, y: 6)
            }

            VStack(spacing: 10) {
                ForEach(OnboardingPriority.onboardingOptions, id: \.self) { priority in
                    goalOptionButton(priority)
                }
            }
        }
    }

    private func goalOptionButton(_ priority: OnboardingPriority) -> some View {
        let isSelected = explicitPriority == priority
        return Button {
            chooseGoal(priority)
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(OnboardingCopy.priorityTitle(priority))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    Text(OnboardingCopy.prioritySubtitle(priority))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
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

    private func startingPointContent(layout: OnboardingCardLayout) -> some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            onboardingSlideHeader(
                title: startingPointTitle,
                subtitle: startingPointBody,
                titleSize: layout.headerTitleSize - 2
            )

            VStack(alignment: .leading, spacing: 10) {
                Text(FlowLocalization.app("Recommended metrics", "Polecane pomiary", "Medidas recomendadas", "Empfohlene Messwerte", "Mesures recommandées", "Medições recomendadas"))
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(Color.appAccent)

                flowChipList(labels: startingPointMetricLabels)
            }

            VStack(spacing: 10) {
                Button(action: beginAppleHealthImport) {
                    Label(
                        FlowLocalization.app(
                            "Import from Apple Health",
                            "Importuj z Apple Health",
                            "Importar desde Apple Health",
                            "Aus Apple Health importieren",
                            "Importer depuis Apple Health",
                            "Importar do Apple Health"
                        ),
                        systemImage: "heart.text.square.fill"
                    )
                    .foregroundStyle(AppColorRoles.textOnAccent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                }
                .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
                .accessibilityIdentifier("onboarding.startingPoint.importHealth")

                Button(action: chooseManualStartingPoint) {
                    Label(
                        FlowLocalization.app(
                            "Log manually",
                            "Wpisz ręcznie",
                            "Registrar manualmente",
                            "Manuell eintragen",
                            "Saisir manuellement",
                            "Registrar manualmente"
                        ),
                        systemImage: "square.and.pencil"
                    )
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                }
                .buttonStyle(AppSecondaryButtonStyle(cornerRadius: AppRadius.md))
                .accessibilityIdentifier("onboarding.startingPoint.manual")
            }
        }
    }

    private func healthImportContent(layout: OnboardingCardLayout) -> some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            onboardingSlideHeader(
                title: OnboardingCopy.healthPromptTitle,
                subtitle: OnboardingCopy.healthPromptBody,
                titleSize: layout.headerTitleSize - 2
            )

            VStack(spacing: 10) {
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

                Button(action: chooseManualStartingPoint) {
                    Text(FlowLocalization.app(
                        "Log manually",
                        "Wpisz ręcznie",
                        "Registrar manualmente",
                        "Manuell eintragen",
                        "Saisir manuellement",
                        "Registrar manualmente"
                    ))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                }
                .buttonStyle(AppSecondaryButtonStyle(cornerRadius: AppRadius.md))
                .accessibilityIdentifier("onboarding.health.manual")
            }

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

            privacyCard(compact: layout.isCompact)
        }
    }

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
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.appAccent)

            Text(
                FlowLocalization.app(
                    "We'll start with %@.",
                    "Zaczniemy od %@.",
                    "Empezaremos con %@.",
                    "Wir starten mit %@.",
                    "Nous allons commencer par %@.",
                    "Vamos começar com %@."
                )
                .replacingOccurrences(
                    of: "%@",
                    with: GoalMetricPack.recommendedKinds(for: priority).map(\.title).joined(separator: " + ")
                )
            )
            .font(AppTypography.captionEmphasis)
            .foregroundStyle(AppColorRoles.textPrimary)
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
                    "\(name), chest and arm size will tell the story.",
                    "\(name), klatka i ramię pokażą prawdziwy progres.",
                    "\(name), pecho y brazo contarán la historia.",
                    "\(name), Brust und Armumfang erzählen die Geschichte.",
                    "\(name), le torse et le bras raconteront l'histoire.",
                    "\(name), peito e braço vão contar a história."
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
            case .trackHealth:
                return FlowLocalization.app(
                    "\(name), start with a simple health baseline.",
                    "\(name), zacznij od prostego punktu zdrowia.",
                    "\(name), empieza con una base simple de salud.",
                    "\(name), starte mit einer einfachen Gesundheitsbasis.",
                    "\(name), commencez par une base santé simple.",
                    "\(name), comece com uma base simples de saúde."
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
                "Chest and arm size will tell the story.",
                "Klatka i ramię pokażą prawdziwy progres.",
                "Pecho y brazo contarán la historia.",
                "Brust und Armumfang erzählen die Geschichte.",
                "Le torse et le bras raconteront l'histoire.",
                "Peito e braço vão contar a história."
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
        case .trackHealth:
            return FlowLocalization.app(
                "Start with weight and waist.",
                "Zacznij od wagi i pasa.",
                "Empieza con peso y cintura.",
                "Starte mit Gewicht und Taille.",
                "Commencez par le poids et la taille.",
                "Comece com peso e cintura."
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
        case .trackHealth:
            return FlowLocalization.app(
                "A few consistent measurements make long-term trends easier to read.",
                "Kilka regularnych pomiarów ułatwia odczyt długoterminowych trendów.",
                "Unas pocas medidas constantes facilitan leer tendencias largas.",
                "Wenige konstante Messwerte machen Langzeittrends leichter lesbar.",
                "Quelques mesures régulières rendent les tendances plus lisibles.",
                "Poucas medições consistentes tornam tendências longas mais claras."
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
        case .trackHealth:
            preferred = "onboarding-before"
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
        case .trackHealth:
            preferred = "onboarding-after"
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
        guard isPrimaryEnabled else { return }
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
            persistGoalSelection(trackStepCompletion: true)
            animateToInputStep(.startingPoint)
        case .startingPoint:
            beginAppleHealthImport()
        case .healthImport:
            requestHealthAccess()
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
            persistGoalSelection(trackStepCompletion: true)
            animateToInputStep(.startingPoint)
        case .startingPoint, .healthImport:
            chooseManualStartingPoint()
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

    private func chooseGoal(_ priority: OnboardingPriority) {
        Haptics.selection()
        selectedPriority = priority
        onboardingPrimaryGoalRaw = priority.rawValue
        persistGoalSelection(trackStepCompletion: true)
        animateToInputStep(.startingPoint)
    }

    private func persistGoalSelection(trackStepCompletion: Bool) {
        let trimmed = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            userName = trimmed
        }
        let priority = resolvedPriority
        selectedPriority = priority
        onboardingPrimaryGoalRaw = priority.rawValue
        applyMetricPackIfNeeded()
        Analytics.shared.track(AnalyticsEvents.onboardingPrioritySelected(priority: priority.analyticsValue))
        if trackStepCompletion {
            Analytics.shared.track(
                AnalyticsEvents.onboardingStepCompleted(
                    step: InputStep.goal.analyticsName,
                    stepIndex: InputStep.goal.rawValue + 1
                )
            )
        }
    }

    private func beginAppleHealthImport() {
        persistGoalSelection(trackStepCompletion: false)
        Analytics.shared.track(
            AnalyticsEvents.onboardingStepCompleted(
                step: InputStep.startingPoint.analyticsName,
                stepIndex: InputStep.startingPoint.rawValue + 1
            )
        )
        animateToInputStep(.healthImport)
    }

    private func chooseManualStartingPoint() {
        onboardingSkippedHealthKit = true
        Analytics.shared.track(
            AnalyticsEvents.onboardingStepCompleted(
                step: currentStep.analyticsName,
                stepIndex: currentStep.rawValue + 1
            )
        )
        finishOnboarding()
    }

    private func applyMetricPackIfNeeded() {
        let customizedMetricsBefore = effects.hasCustomizedMetrics()
        guard !customizedMetricsBefore else { return }
        effects.applyMetricPack(recommendedKinds)
        Analytics.shared.track(
            AnalyticsEvents.onboardingMetricPackApplied(
                priority: resolvedPriority.analyticsValue,
                packID: resolvedPriority.rawValue,
                metricsCount: recommendedKinds.count,
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
                Analytics.shared.track(
                    AnalyticsEvents.onboardingStepCompleted(
                        step: InputStep.healthImport.analyticsName,
                        stepIndex: InputStep.healthImport.rawValue + 1
                    )
                )
                finishOnboarding()
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
        activationCurrentTaskID = ActivationTask.firstMeasurement.rawValue
        activationCompletedTaskIDsRaw = ""
        activationSkippedTaskIDsRaw = ""
        activationIsDismissed = false
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
