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

    @State private var currentStep: InputStep = .profile
    @State private var nameInput: String = ""
    @State private var selectedPriority: OnboardingPriority?
    @State private var isRequestingHealthKit = false
    @State private var healthStatusLines: [String] = []
    @State private var healthAuthorizationPhase: HealthAuthorizationPhase = .idle
    @State private var healthAuthorizationVisualProgress: CGFloat = 0
    @State private var didPrewarmHealthKitAuthorization = false
    @State private var hasTrackedStart = false
    @State private var slideAppeared = false
    @FocusState private var isNameFieldFocused: Bool

    private let isUITestOnboardingMode = UITestArgument.isPresent(.onboardingMode)

    init(effects: OnboardingEffects? = nil) {
        self.effects = effects ?? .live
    }

    private var shouldAnimate: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    private var activationTasksCount: Int { ActivationTask.allCases.count }

    private var overallStepIndex: Int { currentStep.rawValue }

    private var canGoBack: Bool { currentStep != .profile }

    private var isSkipVisible: Bool { true }

    private var primaryButtonTitle: String {
        switch currentStep {
        case .profile:
            return FlowLocalization.system(
                "Show my metrics",
                "Pokaż moje metryki",
                "Mostrar mis métricas",
                "Zeig mir meine Messwerte",
                "Montrer mes mesures",
                "Mostrar minhas métricas"
            )
        case .metrics:
            return FlowLocalization.system(
                "Show photo check-ins",
                "Pokaż check-iny zdjęciowe",
                "Mostrar check-ins de fotos",
                "Foto-Check-ins zeigen",
                "Montrer les check-ins photo",
                "Mostrar check-ins com fotos"
            )
        case .photos:
            return FlowLocalization.system(
                "Set up Apple Health",
                "Skonfiguruj Apple Health",
                "Configurar Apple Health",
                "Apple Health einrichten",
                "Configurer Apple Health",
                "Configurar o Apple Health"
            )
        case .health:
            return FlowLocalization.system(
                "Start my journey",
                "Rozpocznij moją drogę",
                "Empezar mi camino",
                "Meine Reise starten",
                "Commencer mon parcours",
                "Começar minha jornada"
            )
        }
    }

    private var skipButtonTitle: String {
        FlowLocalization.system("Skip for now", "Pomiń na razie", "Omitir por ahora", "Vorerst überspringen", "Passer pour l'instant", "Pular por enquanto")
    }

    private var isPrimaryEnabled: Bool {
        !isRequestingHealthKit || currentStep != .health
    }

    private var resolvedPriority: OnboardingPriority {
        if let selectedPriority {
            return selectedPriority
        }
        if let storedPriority = OnboardingPriority(rawValue: onboardingPrimaryGoalRaw) {
            return storedPriority
        }
        return .improveHealth
    }

    private var resolvedPriorityTitle: String { OnboardingCopy.priorityTitle(resolvedPriority) }

    private var recommendedKinds: [MetricKind] { GoalMetricPack.recommendedKinds(for: resolvedPriority) }

    private var healthProgressTitle: String {
        switch healthAuthorizationPhase {
        case .idle:
            return ""
        case .preparing:
            return FlowLocalization.system(
                "Preparing Apple Health access…",
                "Przygotowuję dostęp do Zdrowia…",
                "Preparando acceso a Salud…",
                "Apple Health-Zugriff wird vorbereitet…",
                "Préparation de l'accès à Santé…",
                "Preparando acesso ao Health…"
            )
        case .requestingSystemPrompt:
            return FlowLocalization.system(
                "Opening Apple Health…",
                "Otwieram okno Zdrowia…",
                "Abriendo Apple Health…",
                "Apple Health wird geöffnet…",
                "Ouverture d'Apple Health…",
                "Abrindo Apple Health…"
            )
        case .importingProfile:
            return FlowLocalization.system(
                "Importing your baseline…",
                "Importuję Twój punkt startowy…",
                "Importando tu linię bazową…",
                "Deine Basis wird importiert…",
                "Import de votre base…",
                "Importando sua linha de base…"
            )
        case .completed:
            return FlowLocalization.system(
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
            return FlowLocalization.system(
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
                    .padding(.bottom, footerReservedHeight)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
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
        case .profile:
            onboardingInputCard {
                VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                    onboardingSlideHeader(
                        title: FlowLocalization.system(
                            "What's your name?",
                            "Jak masz na imię?",
                            "¿Cómo te llamas?",
                            "Wie heißt du?",
                            "Comment vous appelez-vous ?",
                            "Como você se chama?"
                        ),
                        subtitle: FlowLocalization.system(
                            "Pick your main goal so MeasureMe starts with the right signals from day one.",
                            "Wybierz główny cel, aby MeasureMe od pierwszego dnia pokazywało właściwe sygnały.",
                            "Elige tu meta principal para que MeasureMe empiece con las señales correctas desde el primer día.",
                            "Wähle dein Hauptziel, damit MeasureMe vom ersten Tag an die richtigen Signale zeigt.",
                            "Choisissez votre objectif principal pour que MeasureMe démarre avec les bons signaux dès le premier jour.",
                            "Escolha seu objetivo principal para que o MeasureMe comece com os sinais certos desde o primeiro dia."
                        ),
                        titleSize: layout.headerTitleSize
                    )

                    TextField("e.g. Alex", text: $nameInput)
                        .textInputAutocapitalization(.words)
                        .font(.system(size: layout.nameFieldFontSize, weight: .semibold, design: .rounded))
                        .padding(.vertical, layout.nameFieldVerticalPadding)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(AppColorRoles.surfaceInteractive)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                        )
                        .focused($isNameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { isNameFieldFocused = false }
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") {
                                    isNameFieldFocused = false
                                }
                            }
                        }
                        .accessibilityIdentifier("onboarding.name.field")

                    VStack(alignment: .leading, spacing: layout.groupSpacing) {
                        Text(
                            FlowLocalization.system(
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
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(isSelected ? Color.appAccent.opacity(0.12) : AppColorRoles.surfaceInteractive)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                    onboardingSlideHeader(
                        title: metricsStepTitle,
                        subtitle: metricsStepSubtitle,
                        titleSize: layout.headerTitleSize - 2
                    )

                    flowChipList(labels: recommendedKinds.map(\.title))

                    introMetricsVisual(layout: layout)
                        .frame(maxWidth: .infinity)
                }
            }
        case .photos:
            onboardingInputCard {
                VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                    onboardingSlideHeader(
                        title: FlowLocalization.system(
                            "Photos that show the change",
                            "Zdjęcia, które pokazują zmianę",
                            "Fotos que muestran el cambio",
                            "Fotos, die Veränderung zeigen",
                            "Photos qui montrent le changement",
                            "Fotos que mostram a mudança"
                        ),
                        subtitle: FlowLocalization.system(
                            "Use consistent check-ins so subtle progress becomes obvious before it feels dramatic.",
                            "Używaj spójnych check-inów, aby subtelny progres był widoczny, zanim stanie się spektakularny.",
                            "Usa check-ins consistentes para que el progreso sutil sea evidente antes de parecer drástico.",
                            "Nutze konsistente Check-ins, damit subtile Fortschritte sichtbar werden, bevor sie drastisch wirken.",
                            "Utilisez des check-ins cohérents pour rendre les progrès subtils visibles avant qu'ils ne paraissent spectaculaires.",
                            "Use check-ins consistentes para que o progresso sutil fique visível antes de parecer dramático."
                        ),
                        titleSize: layout.headerTitleSize
                    )

                    introPhotosVisual(layout: layout)

                    Text(
                        FlowLocalization.system(
                            "Front and side shots taken in similar light will make your weekly comparisons far more useful.",
                            "Zdjęcia z przodu i z boku robione w podobnym świetle sprawią, że tygodniowe porównania będą dużo bardziej użyteczne.",
                            "Las fotos de frente y de lado con luz similar harán mucho más útiles tus comparaciones semanales.",
                            "Front- und Seitenfotos bei ähnlichem Licht machen deine Wochenvergleiche deutlich nützlicher.",
                            "Des photos de face et de profil prises dans une lumière similaire rendront vos comparaisons hebdomadaires bien plus utiles.",
                            "Fotos de frente e de lado com luz parecida tornam suas comparações semanais muito mais úteis."
                        )
                    )
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                }
            }
        case .health:
            onboardingInputCard {
                VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                    onboardingSlideHeader(
                        title: FlowLocalization.system(
                            "Connect Health. Keep it private.",
                            "Połącz Zdrowie. Zachowaj prywatność.",
                            "Conecta Salud. Mantén la privacidad.",
                            "Health verbinden. Privat bleiben.",
                            "Connectez Santé. Gardez le contrôle.",
                            "Conecte o Health. Mantenha a privacidade."
                        ),
                        subtitle: FlowLocalization.system(
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

    @State private var slideBlobAnimate = false
    @State private var welcomeShimmerEnabled = true

    private var introWelcomeVisual: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                ambientBlobs(for: 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                VStack(spacing: 28) {
                    welcomeHeroLogo
                        .opacity(slideAppeared ? 1 : 0)
                        .scaleEffect(slideAppeared ? 1 : 0.85)
                        .animation(shouldAnimate ? AppMotion.sectionEnter.delay(0.1) : .none, value: slideAppeared)

                    VStack(spacing: 8) {
                        Text("MeasureMe")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.appWhite)

                        Text(OnboardingCopy.introSubtitle(index: 0))
                            .font(.system(.title3, design: .rounded).weight(.medium))
                            .foregroundStyle(AppColorRoles.textSecondary)
                            .skeletonShimmer(enabled: welcomeShimmerEnabled)
                    }
                    .multilineTextAlignment(.center)
                    .opacity(slideAppeared ? 1 : 0)
                    .offset(y: slideAppeared ? 0 : 16)
                    .animation(shouldAnimate ? AppMotion.sectionEnter.delay(0.25) : .none, value: slideAppeared)
                }
            }

            Text(FlowLocalization.system(
                "Build a simple body-tracking rhythm around metrics, photos, and insight.",
                "Zbuduj prosty rytm śledzenia ciała wokół metryk, zdjęć i wniosków.",
                "Crea un ritmo simple de seguimiento corporal con métricas, fotos e insights.",
                "Baue einen einfachen Tracking-Rhythmus aus Messwerten, Fotos und Einblicken auf.",
                "Créez un rythme simple autour des mesures, des photos et des insights.",
                "Crie um ritmo simples de acompanhamento com métricas, fotos e insights."
            ))
            .font(AppTypography.body)
            .foregroundStyle(AppColorRoles.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, 32)
            .opacity(slideAppeared ? 1 : 0)
            .animation(shouldAnimate ? AppMotion.sectionEnter.delay(0.4) : .none, value: slideAppeared)

            Spacer()
        }
        .onAppear {
            slideBlobAnimate = true
            if shouldAnimate {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    welcomeShimmerEnabled = false
                }
            } else {
                welcomeShimmerEnabled = false
            }
        }
    }

    private func ambientBlobs(for slideIndex: Int) -> some View {
        AmbientBlobsView(
            blobs: Self.blobSpecs(for: slideIndex),
            animate: slideBlobAnimate,
            shouldAnimate: shouldAnimate
        )
    }

    private var welcomeHeroLogo: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.appAccent.opacity(0.18), Color.appAccent.opacity(0.04), .clear],
                        center: .center, startRadius: 30, endRadius: 120
                    )
                )
                .frame(width: 240, height: 240)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.appAccent.opacity(0.30), .clear],
                        center: .center, startRadius: 20, endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .blur(radius: 8)

            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.appAccent.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .stroke(Color.appAccent.opacity(0.28), lineWidth: 1)
                    }
                    .shadow(color: Color.appAccent.opacity(0.30), radius: 24, y: 12)

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.appMidnight.opacity(0.92))
                    .padding(8)

                Image("BrandMark")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .padding(18)
            }
            .frame(width: 120, height: 120)
        }
        .accessibilityHidden(true)
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.appAccent.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
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

    @State private var photoAfterAppeared = false

    private func introPhotosVisual(layout: OnboardingCardLayout) -> some View {
        let beforeLabel = FlowLocalization.system("Before", "Przed", "Antes", "Vorher", "Avant", "Antes")
        let afterLabel = FlowLocalization.system("After", "Po", "Después", "Nachher", "Après", "Depois")
        let compareLabel = FlowLocalization.system("Compare", "Porównaj", "Comparar", "Vergleichen", "Comparer", "Comparar")
        let isRecomp = resolvedPriority == .improveHealth
        let photoWidth = isRecomp ? layout.photoWidth + (layout.isCompact ? 24 : 34) : layout.photoWidth
        let photoHeight = isRecomp ? layout.photoHeight + (layout.isCompact ? 24 : 34) : layout.photoHeight

        return VStack(spacing: 12) {
            OnboardingBeforeAfterSlider(
                // The "Before" / "After" assets were authored flipped; swap at the call site.
                beforeImageName: onboardingAfterAssetName,
                afterImageName: onboardingBeforeAssetName,
                beforeLabel: beforeLabel,
                afterLabel: afterLabel,
                imageAlignment: isRecomp ? .center : .top
            )
            .frame(width: photoWidth, height: photoHeight)
            .frame(maxWidth: .infinity)
            .opacity(photoAfterAppeared ? 1 : 0)
            .offset(y: photoAfterAppeared ? 0 : 18)
            .animation(shouldAnimate ? AppMotion.sectionEnter.delay(0.25) : .none, value: photoAfterAppeared)

            Capsule(style: .continuous)
                .fill(AppColorRoles.surfaceChrome.opacity(0.92))
                .frame(width: layout.compareChipWidth, height: layout.compareChipHeight)
                .overlay {
                    HStack(spacing: 10) {
                        Image(systemName: "camera.metering.none")
                        Text(compareLabel)
                    }
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
                }
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.appAccent.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: AppColorRoles.shadowSoft.opacity(0.16), radius: 12, y: 6)
        }
        .onAppear {
            if shouldAnimate {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    photoAfterAppeared = true
                }
            } else {
                photoAfterAppeared = true
            }
        }
    }

    private func photoCard(imageName: String, label: String, borderColor: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.5)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                Text(label)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                    .padding(.bottom, 14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
        }
    }

    @State private var healthCardsAppeared = false

    private var introHealthVisual: some View {
        let cards: [(String, String, String, Color)] = [
            ("Waist-to-Height", "0.47", "On track", AppColorRoles.stateSuccess),
            ("Body Fat", "18%", "On track", Color.appAccent),
            ("Shoulder-to-Waist", "1.52", "Strong", Color(hex: "#F59E0B"))
        ]
        return VStack(spacing: 14) {
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                DummyIndicatorCard(title: card.0, value: card.1, legend: card.2, tint: card.3)
                    .opacity(healthCardsAppeared ? 1 : 0)
                    .offset(y: healthCardsAppeared ? 0 : 20)
                    .animation(shouldAnimate ? AppMotion.sectionEnter.delay(Double(index) * 0.15 + 0.1) : .none, value: healthCardsAppeared)
            }
        }
        .onAppear {
            if shouldAnimate {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    healthCardsAppeared = true
                }
            } else {
                healthCardsAppeared = true
            }
        }
    }

    @State private var shieldGlowPhase = false

    private var introPrivacyVisual: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule(style: .continuous)
                .fill(Color.appAccent.opacity(0.18))
                .frame(width: 118, height: 34)
                .overlay {
                    Text("On-device")
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(Color.appAccent)
                }

            ZStack {
                AppGlassBackground(depth: .elevated, cornerRadius: 26, tint: Color.appAccent)
                VStack(spacing: 18) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(Color.appAccent)
                        .shadow(color: Color.appAccent.opacity(shieldGlowPhase ? 0.4 : 0.1), radius: 20)
                        .animation(
                            AppMotion.repeating(.easeInOut(duration: 1.25).repeatForever(autoreverses: true), enabled: shouldAnimate),
                            value: shieldGlowPhase
                        )
                    Text(FlowLocalization.system(
                        "Private by design",
                        "Prywatność od podstaw",
                        "Privacidad por diseño",
                        "Datenschutz by design",
                        "Confidentialité par conception",
                        "Privacidade desde a origem"
                    ))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.appWhite)
                    Text(FlowLocalization.system(
                        "Your photos and measurements never leave your device.",
                        "Twoje zdjęcia i pomiary nigdy nie opuszczają urządzenia.",
                        "Tus fotos y medidas nunca salen de tu dispositivo.",
                        "Deine Fotos und Messwerte verlassen dein Gerät nie.",
                        "Vos photos et mesures ne quittent jamais votre appareil.",
                        "Suas fotos e medições nunca saem do seu dispositivo."
                    ))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                }
            }
            .frame(height: 220)
            .onAppear { shieldGlowPhase = true }
        }
    }

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
                FlowLocalization.system(
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

    private var effectiveNameForGreeting: String? {
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
                return FlowLocalization.system(
                    "\(name), start with weight and waist.",
                    "\(name), zacznij od wagi i pasa.",
                    "\(name), empieza con peso y cintura.",
                    "\(name), starte mit Gewicht und Taille.",
                    "\(name), commencez par le poids et la taille.",
                    "\(name), comece com peso e cintura."
                )
            case .buildMuscle:
                return FlowLocalization.system(
                    "\(name), chest and arm size will tell the story.",
                    "\(name), klatka i ramię pokażą prawdziwy progres.",
                    "\(name), pecho y brazo contarán la historia.",
                    "\(name), Brust und Armumfang erzählen die Geschichte.",
                    "\(name), le torse et le bras raconteront l'histoire.",
                    "\(name), peito e braço vão contar a história."
                )
            case .improveHealth:
                return FlowLocalization.system(
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
            return FlowLocalization.system(
                "Start with weight and waist.",
                "Zacznij od wagi i pasa.",
                "Empieza con peso y cintura.",
                "Starte mit Gewicht und Taille.",
                "Commencez par le poids et la taille.",
                "Comece com peso e cintura."
            )
        case .buildMuscle:
            return FlowLocalization.system(
                "Chest and arm size will tell the story.",
                "Klatka i ramię pokażą prawdziwy progres.",
                "Pecho y brazo contarán la historia.",
                "Brust und Armumfang erzählen die Geschichte.",
                "Le torse et le bras raconteront l'histoire.",
                "Peito e braço vão contar a história."
            )
        case .improveHealth:
            return FlowLocalization.system(
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
            return FlowLocalization.system(
                "Weight shows pace. Waist confirms whether fat loss is actually happening.",
                "Waga pokazuje tempo. Pas potwierdza, czy utrata tkanki tłuszczowej naprawdę zachodzi.",
                "El peso muestra el ritmo. La cintura confirma si la pérdida de grasa realmente ocurre.",
                "Gewicht zeigt das Tempo. Die Taille bestätigt, ob Fettverlust wirklich passiert.",
                "Le poids montre le rythme. La taille confirme si la perte de graisse se produit vraiment.",
                "O peso mostra o ritmo. A cintura confirma se a perda de gordura está mesmo acontecendo."
            )
        case .buildMuscle:
            return FlowLocalization.system(
                "These two measurements surface muscle gain earlier than the scale will.",
                "Te dwie metryki pokażą budowę mięśni wcześniej niż sama waga.",
                "Estas dos medidas muestran ganancia muscular antes que la báscula.",
                "Diese zwei Messwerte zeigen Muskelaufbau früher als die Waage.",
                "Ces deux mesures révèlent le gain musculaire plus tôt que la balance.",
                "Essas duas medidas mostram ganho muscular antes da balança."
            )
        case .improveHealth:
            return FlowLocalization.system(
                "Waist and chest together make recomp easier to trust when weight is noisy.",
                "Pas i klatka razem ułatwiają ocenę rekompozycji, gdy waga szumi.",
                "Cintura y pecho juntos facilitan confiar en la recomposición cuando el peso mete ruido.",
                "Taille und Brust zusammen machen Recomp leichter lesbar, wenn das Gewicht rauscht.",
                "La taille et le torse ensemble rendent la recomposition plus fiable quand le poids est bruité.",
                "Cintura e peito juntos tornam a recomposição mais clara quando o peso oscila."
            )
        }
    }

    private struct MetricsPreviewCardData {
        let title: String
        let value: String
        let delta: String
        let tint: Color
        let backgroundTint: Color
        let points: [CGPoint]
    }

    private struct MetricsInsightCopy {
        let title: String
        let lineOne: String
        let lineTwo: String
        let tip: String
    }

    private var metricsPreviewCards: [MetricsPreviewCardData] {
        switch resolvedPriority {
        case .loseWeight:
            return [
                MetricsPreviewCardData(
                    title: MetricKind.weight.title,
                    value: FlowLocalization.system("79.9 kg", "79,9 kg", "79,9 kg", "79,9 kg", "79,9 kg", "79,9 kg"),
                    delta: FlowLocalization.system("-2.3 kg", "-2,3 kg", "-2,3 kg", "-2,3 kg", "-2,3 kg", "-2,3 kg"),
                    tint: Color.appAccent,
                    backgroundTint: Color.appAccent,
                    points: [
                        CGPoint(x: 0.03, y: 0.30),
                        CGPoint(x: 0.24, y: 0.38),
                        CGPoint(x: 0.45, y: 0.49),
                        CGPoint(x: 0.66, y: 0.57),
                        CGPoint(x: 0.86, y: 0.68),
                        CGPoint(x: 0.97, y: 0.74)
                    ]
                ),
                MetricsPreviewCardData(
                    title: MetricKind.waist.title,
                    value: FlowLocalization.system("84.0 cm", "84,0 cm", "84,0 cm", "84,0 cm", "84,0 cm", "84,0 cm"),
                    delta: FlowLocalization.system("-4.1 cm", "-4,1 cm", "-4,1 cm", "-4,1 cm", "-4,1 cm", "-4,1 cm"),
                    tint: Color.cyan,
                    backgroundTint: Color.cyan.opacity(0.45),
                    points: [
                        CGPoint(x: 0.03, y: 0.34),
                        CGPoint(x: 0.22, y: 0.41),
                        CGPoint(x: 0.42, y: 0.50),
                        CGPoint(x: 0.63, y: 0.58),
                        CGPoint(x: 0.83, y: 0.67),
                        CGPoint(x: 0.97, y: 0.73)
                    ]
                )
            ]
        case .buildMuscle:
            return [
                MetricsPreviewCardData(
                    title: MetricKind.chest.title,
                    value: FlowLocalization.system("109.0 cm", "109,0 cm", "109,0 cm", "109,0 cm", "109,0 cm", "109,0 cm"),
                    delta: FlowLocalization.system("+3.2 cm", "+3,2 cm", "+3,2 cm", "+3,2 cm", "+3,2 cm", "+3,2 cm"),
                    tint: Color.appAccent,
                    backgroundTint: Color.appAccent,
                    points: [
                        CGPoint(x: 0.03, y: 0.68),
                        CGPoint(x: 0.24, y: 0.62),
                        CGPoint(x: 0.45, y: 0.54),
                        CGPoint(x: 0.66, y: 0.46),
                        CGPoint(x: 0.86, y: 0.37),
                        CGPoint(x: 0.97, y: 0.31)
                    ]
                ),
                MetricsPreviewCardData(
                    title: MetricKind.leftBicep.title,
                    value: FlowLocalization.system("40.1 cm", "40,1 cm", "40,1 cm", "40,1 cm", "40,1 cm", "40,1 cm"),
                    delta: FlowLocalization.system("+1.5 cm", "+1,5 cm", "+1,5 cm", "+1,5 cm", "+1,5 cm", "+1,5 cm"),
                    tint: Color.appTeal,
                    backgroundTint: Color.appTeal.opacity(0.4),
                    points: [
                        CGPoint(x: 0.03, y: 0.71),
                        CGPoint(x: 0.22, y: 0.67),
                        CGPoint(x: 0.42, y: 0.59),
                        CGPoint(x: 0.63, y: 0.48),
                        CGPoint(x: 0.83, y: 0.40),
                        CGPoint(x: 0.97, y: 0.33)
                    ]
                )
            ]
        case .improveHealth:
            return [
                MetricsPreviewCardData(
                    title: MetricKind.waist.title,
                    value: FlowLocalization.system("82.8 cm", "82,8 cm", "82,8 cm", "82,8 cm", "82,8 cm", "82,8 cm"),
                    delta: FlowLocalization.system("-2.6 cm", "-2,6 cm", "-2,6 cm", "-2,6 cm", "-2,6 cm", "-2,6 cm"),
                    tint: Color.cyan,
                    backgroundTint: Color.cyan.opacity(0.45),
                    points: [
                        CGPoint(x: 0.03, y: 0.35),
                        CGPoint(x: 0.22, y: 0.42),
                        CGPoint(x: 0.42, y: 0.51),
                        CGPoint(x: 0.63, y: 0.58),
                        CGPoint(x: 0.83, y: 0.66),
                        CGPoint(x: 0.97, y: 0.71)
                    ]
                ),
                MetricsPreviewCardData(
                    title: MetricKind.chest.title,
                    value: FlowLocalization.system("102.4 cm", "102,4 cm", "102,4 cm", "102,4 cm", "102,4 cm", "102,4 cm"),
                    delta: FlowLocalization.system("+1.1 cm", "+1,1 cm", "+1,1 cm", "+1,1 cm", "+1,1 cm", "+1,1 cm"),
                    tint: Color.appAccent,
                    backgroundTint: Color.appAccent,
                    points: [
                        CGPoint(x: 0.03, y: 0.66),
                        CGPoint(x: 0.24, y: 0.60),
                        CGPoint(x: 0.45, y: 0.55),
                        CGPoint(x: 0.66, y: 0.50),
                        CGPoint(x: 0.86, y: 0.43),
                        CGPoint(x: 0.97, y: 0.39)
                    ]
                )
            ]
        }
    }

    private var metricsInsightCopy: MetricsInsightCopy {
        let personalizedIntro: String
        if let name = effectiveNameForGreeting {
            personalizedIntro = name
        } else {
            personalizedIntro = ""
        }

        switch resolvedPriority {
        case .loseWeight:
            let lineOne = personalizedIntro.isEmpty
                ? FlowLocalization.system(
                    "Weight is trending down and waist is tightening too.",
                    "Waga spada, a pas też się zmniejsza.",
                    "El peso baja y la cintura también se reduce.",
                    "Gewicht sinkt und die Taille wird ebenfalls kleiner.",
                    "Le poids baisse et la taille diminue aussi.",
                    "O peso está caindo e a cintura também."
                )
                : FlowLocalization.system(
                    "\(personalizedIntro), weight is trending down and waist is tightening too.",
                    "\(personalizedIntro), waga spada, a pas też się zmniejsza.",
                    "\(personalizedIntro), el peso baja y la cintura también se reduce.",
                    "\(personalizedIntro), Gewicht sinkt und die Taille wird ebenfalls kleiner.",
                    "\(personalizedIntro), le poids baisse et la taille diminue aussi.",
                    "\(personalizedIntro), o peso está caindo e a cintura também."
                )
            return MetricsInsightCopy(
                title: FlowLocalization.system("AI trend example", "Przykład trendu AI", "Ejemplo de tendencia IA", "KI-Trendbeispiel", "Exemple de tendance IA", "Exemplo de tendência de IA"),
                lineOne: lineOne,
                lineTwo: FlowLocalization.system(
                    "That is a much stronger fat-loss signal than scale weight on its own.",
                    "To dużo mocniejszy sygnał utraty tkanki tłuszczowej niż sama waga.",
                    "Eso es una señal de pérdida de grasa mucho más fuerte que el peso por sí solo.",
                    "Das ist ein deutlich stärkeres Fettverlust-Signal als das Gewicht allein.",
                    "C'est un signal de perte de graisse bien plus fort que le poids seul.",
                    "Esse é um sinal muito mais forte de perda de gordura do que o peso sozinho."
                ),
                tip: FlowLocalization.system(
                    "Keep protein high and keep your weekly movement consistent.",
                    "Trzymaj wysoko białko i utrzymuj regularny ruch w tygodniu.",
                    "Mantén alta la proteína y el movimiento semanal constante.",
                    "Halte die Proteinzufuhr hoch und deine Wochenbewegung konstant.",
                    "Gardez un apport élevé en protéines et un mouvement hebdomadaire régulier.",
                    "Mantenha proteína alta e movimento semanal consistente."
                )
            )
        case .buildMuscle:
            let lineOne = personalizedIntro.isEmpty
                ? FlowLocalization.system(
                    "Chest and left bicep are growing together.",
                    "Klatka i lewy biceps rosną razem.",
                    "Pecho y bíceps izquierdo están creciendo juntos.",
                    "Brust und linker Bizeps wachsen zusammen.",
                    "Le torse et le biceps gauche progressent ensemble.",
                    "Peito e bíceps esquerdo estão crescendo juntos."
                )
                : FlowLocalization.system(
                    "\(personalizedIntro), chest and left bicep are growing together.",
                    "\(personalizedIntro), klatka i lewy biceps rosną razem.",
                    "\(personalizedIntro), pecho y bíceps izquierdo están creciendo juntos.",
                    "\(personalizedIntro), Brust und linker Bizeps wachsen zusammen.",
                    "\(personalizedIntro), le torse et le biceps gauche progressent ensemble.",
                    "\(personalizedIntro), peito e bíceps esquerdo estão crescendo juntos."
                )
            return MetricsInsightCopy(
                title: FlowLocalization.system("AI trend example", "Przykład trendu AI", "Ejemplo de tendencia IA", "KI-Trendbeispiel", "Exemple de tendance IA", "Exemplo de tendência de IA"),
                lineOne: lineOne,
                lineTwo: FlowLocalization.system(
                    "This is the kind of signal that shows muscle gain before body weight explains it well.",
                    "To właśnie taki sygnał pokazuje budowę mięśni, zanim dobrze pokaże ją masa ciała.",
                    "Este es el tipo de señal que muestra músculo antes de que el peso lo explique.",
                    "Das ist die Art von Signal, die Muskelaufbau zeigt, bevor das Gewicht es gut erklärt.",
                    "C'est le type de signal qui montre le gain musculaire avant que le poids l'explique bien.",
                    "Esse é o tipo de sinal que mostra ganho muscular antes de o peso explicar bem."
                ),
                tip: FlowLocalization.system(
                    "Keep progressive overload steady and do not chase scale swings.",
                    "Utrzymuj progresywne przeciążenie i nie gon za wahaniami wagi.",
                    "Mantén la sobrecarga progresiva y no persigas las oscilaciones del peso.",
                    "Halte progressive Überlastung konstant und jage keinen Gewichtsschwankungen hinterher.",
                    "Gardez une surcharge progressive régulière et ne courez pas après la balance.",
                    "Mantenha a sobrecarga progressiva e não corra atrás das oscilações da balança."
                )
            )
        case .improveHealth:
            let lineOne = personalizedIntro.isEmpty
                ? FlowLocalization.system(
                    "Waist is tightening while chest stays full.",
                    "Pas się zmniejsza, a klatka zostaje pełna.",
                    "La cintura baja mientras el pecho se mantiene lleno.",
                    "Die Taille wird kleiner, während die Brust voll bleibt.",
                    "La taille diminue pendant que le torse reste plein.",
                    "A cintura está diminuindo enquanto o peito se mantém cheio."
                )
                : FlowLocalization.system(
                    "\(personalizedIntro), waist is tightening while chest stays full.",
                    "\(personalizedIntro), pas się zmniejsza, a klatka zostaje pełna.",
                    "\(personalizedIntro), la cintura baja mientras el pecho se mantiene lleno.",
                    "\(personalizedIntro), die Taille wird kleiner, während die Brust voll bleibt.",
                    "\(personalizedIntro), la taille diminue pendant que le torse reste plein.",
                    "\(personalizedIntro), a cintura está diminuindo enquanto o peito se mantém cheio."
                )
            return MetricsInsightCopy(
                title: FlowLocalization.system("AI trend example", "Przykład trendu AI", "Ejemplo de tendencia IA", "KI-Trendbeispiel", "Exemple de tendance IA", "Exemplo de tendência de IA"),
                lineOne: lineOne,
                lineTwo: FlowLocalization.system(
                    "That usually reads like recomposition, not random day-to-day noise.",
                    "To zwykle wygląda na rekompozycję, a nie losowy codzienny szum.",
                    "Eso suele parecer recomposición, no ruido diario aleatorio.",
                    "Das liest sich meist wie Recomposition, nicht wie tägliches Rauschen.",
                    "Cela ressemble généralement à une recomposition, pas à un bruit quotidien aléatoire.",
                    "Isso geralmente parece recomposição, não ruído aleatório do dia a dia."
                ),
                tip: FlowLocalization.system(
                    "Trust 2-4 week trends and keep your lifting routine boringly consistent.",
                    "Ufaj trendom z 2-4 tygodni i trzymaj nudno regularny trening siłowy.",
                    "Confía en las tendencias de 2-4 semanas y mantén tu rutina de fuerza muy constante.",
                    "Vertraue 2-4-Wochen-Trends und halte dein Krafttraining langweilig konstant.",
                    "Fiez-vous aux tendances sur 2 à 4 semaines et gardez votre routine de force très régulière.",
                    "Confie nas tendências de 2-4 semanas e mantenha sua rotina de treino consistentemente chata."
                )
            )
        }
    }

    private func privacyCard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 34, height: 34)
                    .background(Color.appAccent.opacity(0.16))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        FlowLocalization.system(
                            "Private by design",
                            "Prywatność od podstaw",
                            "Privacidad desde el diseño",
                            "Datenschutz von Anfang an",
                            "Confidentialité par conception",
                            "Privacidade desde a origem"
                        )
                    )
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)

                    Text(
                        FlowLocalization.system(
                            "Your photos and measurements never leave your device.",
                            "Twoje zdjęcia i pomiary nigdy nie opuszczają urządzenia.",
                            "Tus fotos y medidas nunca salen de tu dispositivo.",
                            "Deine Fotos und Messwerte verlassen dein Gerät nie.",
                            "Vos photos et mesures ne quittent jamais votre appareil.",
                            "Suas fotos e medições nunca saem do seu dispositivo."
                        )
                    )
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                }
            }

            Text(
                FlowLocalization.system(
                    "AI summaries run on device where available, and Apple Health access stays optional.",
                    "Podsumowania AI działają na urządzeniu tam, gdzie są dostępne, a dostęp do Apple Health pozostaje opcjonalny.",
                    "Los resúmenes de IA se ejecutan en el dispositivo cuando están disponibles y el acceso a Apple Health sigue siendo opcional.",
                    "KI-Zusammenfassungen laufen, wo verfügbar, auf dem Gerät und Apple Health bleibt optional.",
                    "Les résumés IA fonctionnent sur l'appareil lorsqu'ils sont disponibles, et l'accès à Apple Health reste facultatif.",
                    "Os resumos de IA rodam no aparelho quando disponíveis, e o acesso ao Apple Health continua opcional."
                )
            )
            .font(AppTypography.microEmphasis)
            .foregroundStyle(Color.appAccent)
        }
        .padding(compact ? 12 : 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                )
        )
        .accessibilityIdentifier("onboarding.privacy.note")
    }

    private var onboardingBeforeAssetName: String {
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

    private var onboardingAfterAssetName: String {
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
        effects.track(.onboardingStarted)
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
            signalName: "com.jacekzieba.measureme.onboarding.input.step_viewed",
            parameters: ["step": currentStep.analyticsName]
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
        case .profile:
            persistProfileSelections()
            animateToInputStep(.metrics)
        case .metrics:
            Analytics.shared.track(
                signalName: "com.jacekzieba.measureme.onboarding.input.step_completed",
                parameters: ["step": InputStep.metrics.analyticsName]
            )
            animateToInputStep(.photos)
        case .photos:
            Analytics.shared.track(
                signalName: "com.jacekzieba.measureme.onboarding.input.step_completed",
                parameters: ["step": InputStep.photos.analyticsName]
            )
            animateToInputStep(.health)
        case .health:
            onboardingSkippedHealthKit = !isSyncEnabled
            Analytics.shared.track(
                signalName: "com.jacekzieba.measureme.onboarding.input.step_completed",
                parameters: ["step": InputStep.health.analyticsName]
            )
            finishOnboarding()
        }
    }

    private func skipCurrentStep() {
        Analytics.shared.track(
            signalName: "com.jacekzieba.measureme.onboarding.input.step_skipped",
            parameters: ["step": currentStep.analyticsName]
        )

        switch currentStep {
        case .profile:
            animateToInputStep(.metrics)
        case .metrics:
            animateToInputStep(.photos)
        case .photos:
            animateToInputStep(.health)
        case .health:
            onboardingSkippedHealthKit = true
            healthStatusLines = [
                FlowLocalization.system(
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

    private func animateToInputStep(_ step: InputStep) {
        isNameFieldFocused = false
        if shouldAnimate {
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
        Analytics.shared.track(
            signalName: "com.jacekzieba.measureme.onboarding.input.step_completed",
            parameters: [
                "step": InputStep.profile.analyticsName,
                "priority": priority.analyticsValue
            ]
        )
    }

    private func applyMetricPackIfNeeded() {
        guard !effects.hasCustomizedMetrics() else { return }
        effects.applyMetricPack(recommendedKinds)
    }

    private func requestHealthAccess() {
        guard !isRequestingHealthKit else { return }
        isRequestingHealthKit = true
        updateHealthAuthorizationPhase(.preparing)
        Analytics.shared.track(
            signalName: "com.jacekzieba.measureme.onboarding.health.prompt_shown",
            parameters: ["source": "onboarding"]
        )

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
                    FlowLocalization.system("Health connected", "Health połączone", "Salud conectada", "Health verbunden", "Santé connectée", "Health conectado")
                ]
                if profile.age != nil {
                    imported.append(FlowLocalization.system("Age imported", "Zaimportowano wiek", "Edad importada", "Alter importiert", "Âge importé", "Idade importada"))
                }
                if profile.height != nil {
                    imported.append(FlowLocalization.system("Height imported", "Zaimportowano wzrost", "Altura importada", "Größe importiert", "Taille importée", "Altura importada"))
                }
                healthStatusLines = imported
                updateHealthAuthorizationPhase(.completed)

                Analytics.shared.track(
                    signalName: "com.jacekzieba.measureme.onboarding.health.accepted",
                    parameters: ["source": "onboarding"]
                )
            } catch {
                isSyncEnabled = false
                onboardingSkippedHealthKit = true
                updateHealthAuthorizationPhase(.idle)
                healthStatusLines = [
                    FlowLocalization.system(
                        "You can connect Health later in Settings.",
                        "Health możesz połączyć później w Ustawieniach.",
                        "Puedes conectar Salud más tarde en Ajustes.",
                        "Du kannst Health später in den Einstellungen verbinden.",
                        "Vous pourrez connecter Santé plus tard dans Réglages.",
                        "Você pode conectar o Health depois nos Ajustes."
                    )
                ]
                Analytics.shared.track(
                    signalName: "com.jacekzieba.measureme.onboarding.health.declined",
                    parameters: ["source": "onboarding"]
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
        onboardingFlowVersion = 2
        activationCurrentTaskID = ActivationTask.firstMeasurement.rawValue
        activationCompletedTaskIDsRaw = ""
        activationSkippedTaskIDsRaw = ""
        activationIsDismissed = false
        effects.track(.onboardingCompleted)

        if shouldAnimate {
            withAnimation(AppMotion.quick) {
                hasCompletedOnboarding = true
            }
        } else {
            hasCompletedOnboarding = true
        }

        Analytics.shared.track(
            signalName: "com.jacekzieba.measureme.onboarding.completed_v2",
            parameters: [
                "priority": priority.analyticsValue,
                "health_connected": isSyncEnabled ? "true" : "false"
            ]
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

fileprivate struct AmbientBlobSpec {
    let color: Color
    let innerOpacity: Double
    let outerOpacity: Double
    let size: CGFloat
    let blurRadius: CGFloat
    let startRadius: CGFloat
    let endRadius: CGFloat
    let offsetA: CGSize
    let offsetB: CGSize
}

private struct AmbientBlobsView: View {
    let blobs: [AmbientBlobSpec]
    let animate: Bool
    let shouldAnimate: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(blobs.enumerated()), id: \.offset) { _, spec in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [spec.color.opacity(spec.innerOpacity), spec.color.opacity(spec.outerOpacity), .clear],
                                center: .center, startRadius: spec.startRadius, endRadius: spec.endRadius
                            )
                        )
                        .frame(width: spec.size, height: spec.size)
                        .offset(x: animate ? spec.offsetA.width : spec.offsetB.width, y: animate ? spec.offsetA.height : spec.offsetB.height)
                        .blur(radius: spec.blurRadius)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(
                AppMotion.repeating(.easeInOut(duration: 5).repeatForever(autoreverses: true), enabled: shouldAnimate),
                value: animate
            )
        }
        .allowsHitTesting(false)
    }
}

private struct DummyLineChart: View {
    @State private var chartProgress: CGFloat = 0
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let points: [CGPoint] = [
                CGPoint(x: 0.05, y: 0.72),
                CGPoint(x: 0.20, y: 0.68),
                CGPoint(x: 0.38, y: 0.55),
                CGPoint(x: 0.58, y: 0.46),
                CGPoint(x: 0.78, y: 0.30),
                CGPoint(x: 0.95, y: 0.24)
            ]

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.clear)
                Path { path in
                    for index in 0..<4 {
                        let y = proxy.size.height * CGFloat(index) / 4
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                }
                .stroke(AppColorRoles.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [5, 6]))

                Path { path in
                    for (index, point) in points.enumerated() {
                        let resolved = CGPoint(x: proxy.size.width * point.x, y: proxy.size.height * point.y)
                        if index == 0 {
                            path.move(to: resolved)
                        } else {
                            path.addLine(to: resolved)
                        }
                    }
                }
                .trim(from: 0, to: chartProgress)
                .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        .onAppear {
            let shouldAnimate = AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
            if shouldAnimate {
                withAnimation(AppMotion.emphasized.delay(0.3)) {
                    chartProgress = 1
                }
            } else {
                chartProgress = 1
            }
        }
    }
}

private struct DummyChartLegendItem {
    let label: String
    let color: Color
}

private struct OnboardingCardLayout {
    let isCompact: Bool
    let headerTitleSize: CGFloat
    let sectionSpacing: CGFloat
    let groupSpacing: CGFloat
    let nameFieldFontSize: CGFloat
    let nameFieldVerticalPadding: CGFloat
    let photoWidth: CGFloat
    let photoHeight: CGFloat
    let compareChipWidth: CGFloat
    let compareChipHeight: CGFloat
    let chartRowSpacing: CGFloat

    static let regular = OnboardingCardLayout(
        isCompact: false,
        headerTitleSize: 34,
        sectionSpacing: 14,
        groupSpacing: 8,
        nameFieldFontSize: 24,
        nameFieldVerticalPadding: 8,
        photoWidth: 220,
        photoHeight: 296,
        compareChipWidth: 152,
        compareChipHeight: 38,
        chartRowSpacing: 14
    )

    static let compact = OnboardingCardLayout(
        isCompact: true,
        headerTitleSize: 30,
        sectionSpacing: 12,
        groupSpacing: 6,
        nameFieldFontSize: 22,
        nameFieldVerticalPadding: 7,
        photoWidth: 190,
        photoHeight: 264,
        compareChipWidth: 142,
        compareChipHeight: 36,
        chartRowSpacing: 12
    )
}

private enum IntroMetricsLayout {
    static let columnSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 12
    static let chartCardHeight: CGFloat = 186
    static let compactChartCardHeight: CGFloat = 164
    static let chartHeight: CGFloat = 78
    static let compactChartHeight: CGFloat = 62
    static let legendHeight: CGFloat = 16
    static let valueBlockHeight: CGFloat = 42
    static let compactValueBlockHeight: CGFloat = 36
}

private struct DummyMiniMetricChartCard: View {
    let title: String
    let value: String
    let delta: String
    let tint: Color
    let backgroundTint: Color
    let points: [CGPoint]
    var targetY: CGFloat? = nil
    var targetX: CGFloat? = nil
    var legends: [DummyChartLegendItem] = []
    var compact = false

    var body: some View {
        ZStack {
            AppGlassBackground(depth: .elevated, cornerRadius: 24, tint: backgroundTint)

            VStack(alignment: .leading, spacing: compact ? 4 : AppSpacing.xs) {
                Text(title)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textSecondary)

                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        Path { path in
                            for index in 0..<4 {
                                let y = proxy.size.height * CGFloat(index) / 4
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                            }
                        }
                        .stroke(AppColorRoles.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [4, 5]))

                        if let targetY {
                            Path { path in
                                let y = proxy.size.height * targetY
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                            }
                            .stroke(Color.appAccent.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        }

                        Path { path in
                            for (index, point) in points.enumerated() {
                                let resolved = CGPoint(x: proxy.size.width * point.x, y: proxy.size.height * point.y)
                                if index == 0 {
                                    path.move(to: resolved)
                                } else {
                                    path.addLine(to: resolved)
                                }
                            }
                        }
                        .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                        if let targetY, let targetX {
                            Circle()
                                .fill(Color.appAccent)
                                .frame(width: 8, height: 8)
                                .overlay {
                                    Circle()
                                        .stroke(Color.white.opacity(0.7), lineWidth: 2)
                                }
                                .position(x: proxy.size.width * targetX, y: proxy.size.height * targetY)
                        }
                    }
                }
                .frame(height: compact ? IntroMetricsLayout.compactChartHeight : IntroMetricsLayout.chartHeight)

                HStack(spacing: AppSpacing.xs) {
                    if !legends.isEmpty {
                        ForEach(Array(legends.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 4) {
                                Capsule(style: .continuous)
                                    .fill(item.color)
                                    .frame(width: 12, height: 4)
                                Text(item.label)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppColorRoles.textSecondary)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: IntroMetricsLayout.legendHeight, alignment: .leading)
                .opacity(legends.isEmpty ? 0 : 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(value)
                        .font(.system(size: compact ? 20 : 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.appWhite)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(delta)
                        .font(.system(size: compact ? 12 : 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: compact ? IntroMetricsLayout.compactValueBlockHeight : IntroMetricsLayout.valueBlockHeight,
                    alignment: .bottomLeading
                )
            }
            .padding(IntroMetricsLayout.cardPadding)
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact ? IntroMetricsLayout.compactChartCardHeight : IntroMetricsLayout.chartCardHeight)
    }
}

private struct DummyAIInsightCard: View {
    let title: String
    let lineOne: String
    let lineTwo: String
    let tip: String
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(alignment: .center, spacing: compact ? 8 : 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .foregroundStyle(AppColorRoles.accentPrimary)
                    .frame(width: compact ? 26 : 30, height: compact ? 26 : 30)
                    .background(AppColorRoles.accentPrimary.opacity(0.14))
                    .clipShape(Circle())

                Text(title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
            }

            VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                Text(lineOne)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(lineTwo)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: compact ? 6 : 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .foregroundStyle(AppColorRoles.accentPrimary)
                    .padding(.top, 1)

                Text(tip)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.accentPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppColorRoles.accentPrimary.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppColorRoles.accentPrimary.opacity(0.24), lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, compact ? 12 : 14)
        .padding(.vertical, compact ? 10 : 12)
        .background {
            AppGlassBackground(depth: .base, cornerRadius: 20, tint: AppColorRoles.accentPrimary.opacity(0.05))
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct OnboardingBeforeAfterSlider: View {
    let beforeImageName: String
    let afterImageName: String
    let beforeLabel: String
    let afterLabel: String
    let imageAlignment: Alignment

    @State private var sliderPosition: CGFloat = 0.5
    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let clampedSlider = min(max(sliderPosition, 0), 1)

            ZStack {
                AppColorRoles.surfaceChrome.opacity(0.86)

                onboardingPhoto(beforeImageName, width: width, height: height)

                onboardingPhoto(afterImageName, width: width, height: height)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: width * clampedSlider)
                    }

                LinearGradient(
                    colors: [
                        .black.opacity(0.24),
                        .clear,
                        .black.opacity(0.42)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack {
                    sliderLabel(beforeLabel)
                        .opacity(clampedSlider > 0.18 ? 1 : 0.35)

                    Spacer()

                    sliderLabel(afterLabel)
                        .opacity(clampedSlider < 0.82 ? 1 : 0.35)
                }
                .padding(14)
                .frame(maxHeight: .infinity, alignment: .bottom)

                sliderHandle(height: height)
                    .position(x: width * clampedSlider, y: height / 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.appAccent.opacity(0.38), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let newPosition = value.location.x / width
                        guard newPosition.isFinite else { return }
                        sliderPosition = min(max(newPosition, 0), 1)
                    }
                    .onEnded { _ in
                        isDragging = false
                        if abs(sliderPosition - 0.5) < 0.05 {
                            withAnimation(AppMotion.standard) {
                                sliderPosition = 0.5
                            }
                        }
                    }
            )
        }
    }

    private func onboardingPhoto(_ imageName: String, width: CGFloat, height: CGFloat) -> some View {
        Image(imageName)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height, alignment: imageAlignment)
            .clipped()
    }

    private func sliderLabel(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.captionEmphasis)
            .foregroundStyle(Color.appWhite)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.34), in: Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
    }

    private func sliderHandle(height: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.appWhite.opacity(0.94))
                .frame(width: isDragging ? 4 : 3, height: height)
                .shadow(color: .black.opacity(0.24), radius: 8)

            Circle()
                .fill(Color.appWhite)
                .frame(width: isDragging ? 52 : 46, height: isDragging ? 52 : 46)
                .shadow(color: .black.opacity(0.32), radius: 10, y: 4)
                .overlay {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColorRoles.textTertiary)
                }
        }
    }
}

private struct DummyIndicatorCard: View {
    let title: String
    let value: String
    let legend: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(tint.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay {
                    Circle()
                        .fill(tint)
                        .frame(width: 14, height: 14)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
                Text(legend)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
            }

            Spacer()

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.appWhite)
        }
        .padding(18)
        .background(
            AppGlassBackground(depth: .base, cornerRadius: 22, tint: tint)
        )
    }
}

private struct OnboardingSilhouette: View {
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 18, height: 18)
            Capsule(style: .continuous)
                .fill(tint)
                .frame(width: 22, height: 38)
            HStack(spacing: 6) {
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: 9, height: 28)
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: 9, height: 28)
            }
        }
    }
}

private struct OnboardingConfettiView: View {
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    private let particles: [(color: Color, x: CGFloat, delay: Double)] = {
        let colors: [Color] = [.appAccent, Color(hex: "#46B8FF"), Color(hex: "#29C7B8"), Color(hex: "#F59E0B"), Color(hex: "#7C8CFF")]
        return (0..<24).map { i in
            let color = colors[i % colors.count]
            let x = CGFloat.random(in: 0.05...0.95)
            let delay = Double.random(in: 0...0.4)
            return (color, x, delay)
        }
    }()

    var body: some View {
        let shouldAnimate = AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
        GeometryReader { geo in
            ForEach(Array(particles.enumerated()), id: \.offset) { index, particle in
                let size: CGFloat = CGFloat.random(in: 4...8)
                RoundedRectangle(cornerRadius: size > 6 ? 2 : size / 2, style: .continuous)
                    .fill(particle.color)
                    .frame(width: size, height: size)
                    .position(
                        x: geo.size.width * particle.x,
                        y: shouldAnimate && animate ? geo.size.height * CGFloat.random(in: 0.5...1.0) : -10
                    )
                    .opacity(shouldAnimate && animate ? 0 : 1)
                    .animation(
                        shouldAnimate ? .easeIn(duration: Double.random(in: 1.0...1.8)).delay(particle.delay) : .none,
                        value: animate
                    )
            }
        }
        .allowsHitTesting(false)
        .onAppear { animate = true }
    }
}
