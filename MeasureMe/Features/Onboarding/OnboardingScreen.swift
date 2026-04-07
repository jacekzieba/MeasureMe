import SwiftUI

struct OnboardingView: View {
    private enum Phase: Equatable {
        case intro
        case input(InputStep)
    }

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

    @State private var phase: Phase = .intro
    @State private var introIndex: Int = 0
    @State private var inputStep: InputStep = .name
    @State private var nameInput: String = ""
    @State private var selectedPriorities: Set<OnboardingPriority> = []
    @State private var isRequestingHealthKit = false
    @State private var isRequestingNotifications = false
    @State private var healthStatusLines: [String] = []
    @State private var healthAuthorizationPhase: HealthAuthorizationPhase = .idle
    @State private var healthAuthorizationVisualProgress: CGFloat = 0
    @State private var didPrewarmHealthKitAuthorization = false
    @State private var didAutoAdvancePersonalizing = false
    @State private var hasTrackedStart = false
    @State private var slideAppeared = false
    @State private var inputContentAppeared = false
    @State private var personalizingTextIndex = 0
    @State private var personalizingProgress: CGFloat = 0
    @State private var completionAppeared = false
    @State private var completionRippleScale: CGFloat = 0.5
    @State private var completionRippleOpacity: Double = 0.6

    private let isUITestOnboardingMode = UITestArgument.isPresent(.onboardingMode)

    init(effects: OnboardingEffects = .live) {
        self.effects = effects
    }

    private var shouldAnimate: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    private var totalIntroSlides: Int { 5 }
    private var activationTasksCount: Int { ActivationTask.allCases.count }

    private var overallStepIndex: Int {
        switch phase {
        case .intro:
            return introIndex
        case .input(let step):
            return totalIntroSlides + step.rawValue
        }
    }

    private var canGoBack: Bool {
        switch phase {
        case .intro:
            return introIndex > 0
        case .input(let step):
            return step != .name || introIndex > 0
        }
    }

    private var isSkipVisible: Bool {
        switch phase {
        case .intro:
            return false
        case .input(let step):
            return step != .personalizing
        }
    }

    private var primaryButtonTitle: String {
        switch phase {
        case .intro:
            return AppLocalization.systemString("Continue")
        case .input(let step):
            if step == .completion {
                return FlowLocalization.system(
                    "Go to dashboard",
                    "Przejdź do dashboardu",
                    "Ir al panel",
                    "Zum Dashboard",
                    "Aller au tableau de bord",
                    "Ir para o dashboard"
                )
            }
            return AppLocalization.systemString("Continue")
        }
    }

    private var skipButtonTitle: String {
        switch phase {
        case .intro:
            return ""
        case .input(let step):
            if step == .notifications {
                return AppLocalization.systemString("Skip for now")
            }
            return FlowLocalization.system("Skip", "Pomiń", "Omitir", "Überspringen", "Passer", "Pular")
        }
    }

    private var isPrimaryEnabled: Bool {
        switch phase {
        case .intro:
            return true
        case .input(let step):
            switch step {
            case .personalizing:
                return false
            case .priority:
                return !selectedPriorities.isEmpty
            case .health:
                return !isRequestingHealthKit
            case .notifications:
                return !isRequestingNotifications
            default:
                return true
            }
        }
    }

    private var resolvedPriorities: [OnboardingPriority] {
        let ordered = OnboardingPriority.allCases.filter { selectedPriorities.contains($0) }
        return ordered.isEmpty ? [.improveHealth] : ordered
    }

    private var resolvedPriority: OnboardingPriority {
        resolvedPriorities.first ?? .improveHealth
    }

    private var resolvedPriorityTitles: String {
        resolvedPriorities
            .map(OnboardingCopy.priorityTitle)
            .joined(separator: ", ")
    }

    private var recommendedKinds: [MetricKind] {
        var seen = Set<MetricKind>()
        var result: [MetricKind] = []

        for priority in resolvedPriorities {
            for kind in GoalMetricPack.recommendedKinds(for: priority) where seen.insert(kind).inserted {
                result.append(kind)
            }
        }

        return result
    }

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
        isRequestingHealthKit ? healthProgressTitle : OnboardingCopy.healthAllowCTA
    }

    var body: some View {
        ZStack {
            AppScreenBackground(topHeight: 400, tint: Color.appAccent.opacity(0.2))

            VStack(spacing: 0) {
                topBar

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.md)

                footer
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, 18)
                    .padding(.top, AppSpacing.md)
            }
        }
        .onAppear(perform: handleAppear)
        .onChange(of: introIndex) { _, _ in
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

            if case .intro = phase {
                introDots
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, 12)
    }

    private var introDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalIntroSlides, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == introIndex ? Color.appAccent : AppColorRoles.borderSubtle)
                    .frame(width: index == introIndex ? 28 : 8, height: 6)
                    .animation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimate), value: introIndex)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .intro:
            TabView(selection: $introIndex) {
                ForEach(0..<totalIntroSlides, id: \.self) { index in
                    introSlide(index: index)
                        .tag(index)
                        .accessibilityIdentifier("onboarding.intro.\(index)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        case .input(let step):
            inputStepView(step)
                .id(step.rawValue)
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
            if isSkipVisible {
                Button(skipButtonTitle) {
                    skipCurrentStep()
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColorRoles.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("onboarding.skip")
            }

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
    private func introSlide(index: Int) -> some View {
        if index == 0 {
            VStack(spacing: 0) {
                Spacer(minLength: 10)

                introWelcomeVisual
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 22) {
                Spacer(minLength: 10)

                onboardingSlideHeader(
                    title: OnboardingCopy.introTitle(index: index),
                    subtitle: OnboardingCopy.introSubtitle(index: index)
                )
                .opacity(slideAppeared ? 1 : 0)
                .offset(y: slideAppeared ? 0 : 20)
                .animation(shouldAnimate ? AppMotion.sectionEnter.delay(0.1) : .none, value: slideAppeared)

                Group {
                    switch index {
                    case 1:
                        introMetricsVisual
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.top, AppSpacing.sm)
                    case 2:
                        introPhotosVisual
                    case 3:
                        introHealthVisual
                    default:
                        introPrivacyVisual
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(slideAppeared ? 1 : 0)
                .offset(y: slideAppeared ? 0 : 24)
                .animation(shouldAnimate ? AppMotion.sectionEnter.delay(0.25) : .none, value: slideAppeared)

                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func inputStepView(_ step: InputStep) -> some View {
        switch step {
        case .name:
            onboardingInputCard {
                VStack(alignment: .leading, spacing: 18) {
                    Text(OnboardingCopy.namePrompt)
                        .font(AppTypography.displaySection)
                        .foregroundStyle(AppColorRoles.textPrimary)

                    TextField("e.g. Alex", text: $nameInput)
                        .textInputAutocapitalization(.words)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(AppColorRoles.surfaceInteractive)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                        )
                        .accessibilityIdentifier("onboarding.name.field")
                }
            }
        case .greeting:
            onboardingInputCard {
                VStack(alignment: .leading, spacing: 18) {
                    Text("👋")
                        .font(.system(size: 44))
                    Text(OnboardingCopy.greeting(name: effectiveName))
                        .font(AppTypography.displaySection)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    Text(OnboardingCopy.greetingBody)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textSecondary)
                }
            }
        case .priority:
            onboardingInputCard {
                VStack(alignment: .leading, spacing: 18) {
                    Text(OnboardingCopy.priorityPrompt)
                        .font(AppTypography.displaySection)
                        .foregroundStyle(AppColorRoles.textPrimary)

                    ForEach(OnboardingPriority.allCases, id: \.self) { priority in
                        let isSelected = selectedPriorities.contains(priority)
                        Button {
                            Haptics.selection()
                            if isSelected {
                                selectedPriorities.remove(priority)
                            } else {
                                selectedPriorities.insert(priority)
                            }
                        } label: {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(OnboardingCopy.priorityTitle(priority))
                                        .font(AppTypography.bodyEmphasis)
                                        .foregroundStyle(AppColorRoles.textPrimary)
                                    Text(OnboardingCopy.prioritySubtitle(priority))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColorRoles.textSecondary)
                                        .multilineTextAlignment(.leading)
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
            }
        case .personalizing:
            onboardingInputCard {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 10) {
                        SkeletonBlock(cornerRadius: AppRadius.sm)
                            .frame(maxWidth: .infinity)
                            .frame(height: 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.trailing, UIScreen.main.bounds.width * 0.22)
                            .skeletonShimmer(enabled: true)
                        SkeletonBlock(cornerRadius: AppRadius.sm)
                            .frame(height: 14)
                            .padding(.trailing, UIScreen.main.bounds.width * 0.08)
                            .skeletonShimmer(enabled: true)
                        SkeletonBlock(cornerRadius: AppRadius.sm)
                            .frame(height: 14)
                            .padding(.trailing, UIScreen.main.bounds.width * 0.36)
                            .skeletonShimmer(enabled: true)
                    }

                    Text(personalizingStatusText)
                        .font(AppTypography.displaySection)
                        .foregroundStyle(AppColorRoles.textPrimary)
                        .contentTransition(.opacity)

                    Capsule(style: .continuous)
                        .fill(Color.appAccent)
                        .frame(height: 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(x: personalizingProgress, anchor: .leading)
                        .animation(shouldAnimate ? .linear(duration: 1.2) : .none, value: personalizingProgress)
                }
            }
            .task {
                guard !didAutoAdvancePersonalizing else { return }
                didAutoAdvancePersonalizing = true
                personalizingProgress = 1.0
                let texts = personalizingTexts
                for i in 1..<texts.count {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard phase == .input(.personalizing) else { return }
                    if shouldAnimate {
                        withAnimation(AppMotion.standard) {
                            personalizingTextIndex = i
                        }
                    } else {
                        personalizingTextIndex = i
                    }
                }
                try? await Task.sleep(for: .milliseconds(450))
                guard phase == .input(.personalizing) else { return }
                animateToInputStep(.health)
            }
        case .health:
            onboardingInputCard {
                VStack(alignment: .leading, spacing: 18) {
                    Text(OnboardingCopy.healthPromptTitle)
                        .font(AppTypography.displaySection)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    Text(OnboardingCopy.healthPromptBody)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textSecondary)

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

                    Button {
                        requestHealthAccess()
                    } label: {
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
                    .disabled(isRequestingHealthKit)
                    .accessibilityIdentifier("onboarding.health.allow")
                }
            }
            .task {
                guard !didPrewarmHealthKitAuthorization else { return }
                didPrewarmHealthKitAuthorization = true
                await effects.prewarmHealthKitAuthorization()
            }
        case .notifications:
            onboardingInputCard {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(Color.appAccent)
                    Text(OnboardingCopy.notificationsTitle)
                        .font(AppTypography.displaySection)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    Text(OnboardingCopy.notificationsBody)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textSecondary)

                    Button {
                        requestNotificationAccess()
                    } label: {
                        Text(OnboardingCopy.notificationsCTA)
                            .foregroundStyle(AppColorRoles.textOnAccent)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
                    }
                    .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
                    .disabled(isRequestingNotifications)
                    .accessibilityIdentifier("onboarding.notifications.allow")
                }
            }
        case .completion:
            onboardingInputCard {
                ZStack(alignment: .top) {
                    if completionAppeared {
                        OnboardingConfettiView()
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        ZStack {
                            Circle()
                                .stroke(AppColorRoles.stateSuccess.opacity(completionRippleOpacity), lineWidth: 2)
                                .frame(width: 72, height: 72)
                                .scaleEffect(completionRippleScale)
                                .opacity(completionRippleOpacity)

                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 52))
                                .foregroundStyle(AppColorRoles.stateSuccess)
                                .scaleEffect(completionAppeared ? 1.0 : 0)
                        }
                        .animation(shouldAnimate ? AppMotion.emphasized : .none, value: completionAppeared)

                        Text(OnboardingCopy.completionTitle)
                            .font(AppTypography.displayHero)
                            .foregroundStyle(AppColorRoles.textPrimary)
                            .opacity(completionAppeared ? 1 : 0)
                            .offset(y: completionAppeared ? 0 : 12)
                            .animation(shouldAnimate ? AppMotion.sectionEnter.delay(0.15) : .none, value: completionAppeared)

                        Text(OnboardingCopy.completionBody)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColorRoles.textSecondary)
                            .opacity(completionAppeared ? 1 : 0)
                            .animation(shouldAnimate ? AppMotion.sectionEnter.delay(0.25) : .none, value: completionAppeared)

                        AppGlassCard(depth: .base, cornerRadius: AppRadius.lg, tint: Color.appAccent, contentPadding: 12) {
                            VStack(alignment: .leading, spacing: 10) {
                                flowSummaryRow(
                                    title: FlowLocalization.system("Priority", "Priorytet", "Prioridad", "Priorität", "Priorité", "Prioridade"),
                                    value: resolvedPriorityTitles,
                                    multilineValue: true
                                )
                                flowSummaryRow(
                                    title: FlowLocalization.system("Health", "Health", "Salud", "Health", "Santé", "Health"),
                                    value: isSyncEnabled ? FlowLocalization.system("Connected", "Połączono", "Conectado", "Verbunden", "Connecté", "Conectado") : FlowLocalization.system("Skipped", "Pominięto", "Omitido", "Übersprungen", "Passé", "Ignorado")
                                )
                            }
                        }
                        .opacity(completionAppeared ? 1 : 0)
                        .animation(shouldAnimate ? AppMotion.sectionEnter.delay(0.35) : .none, value: completionAppeared)
                    }
                }
            }
            .onAppear {
                if shouldAnimate {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(AppMotion.emphasized) {
                            completionAppeared = true
                        }
                        withAnimation(.easeOut(duration: 0.8)) {
                            completionRippleScale = 2.0
                            completionRippleOpacity = 0
                        }
                    }
                } else {
                    completionAppeared = true
                    completionRippleOpacity = 0
                }
            }
        }
    }

    @State private var welcomeBlobAnimate = false
    @State private var welcomeShimmerEnabled = true

    private var introWelcomeVisual: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                welcomeAmbientBlobs
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
            welcomeBlobAnimate = true
            if shouldAnimate {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    welcomeShimmerEnabled = false
                }
            } else {
                welcomeShimmerEnabled = false
            }
        }
    }

    private var welcomeAmbientBlobs: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.appAccent.opacity(0.40), Color.appAccent.opacity(0.10), .clear],
                            center: .center, startRadius: 30, endRadius: 220
                        )
                    )
                    .frame(width: 440, height: 440)
                    .offset(x: welcomeBlobAnimate ? 40 : -30, y: welcomeBlobAnimate ? -40 : 20)
                    .blur(radius: 30)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.cyan.opacity(0.25), Color.cyan.opacity(0.06), .clear],
                            center: .center, startRadius: 20, endRadius: 180
                        )
                    )
                    .frame(width: 360, height: 360)
                    .offset(x: welcomeBlobAnimate ? -50 : 30, y: welcomeBlobAnimate ? 40 : -20)
                    .blur(radius: 24)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.appIndigo.opacity(0.20), Color.appIndigo.opacity(0.04), .clear],
                            center: .center, startRadius: 10, endRadius: 150
                        )
                    )
                    .frame(width: 280, height: 280)
                    .offset(x: welcomeBlobAnimate ? 20 : -40, y: welcomeBlobAnimate ? -30 : 40)
                    .blur(radius: 20)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(
                AppMotion.repeating(.easeInOut(duration: 5).repeatForever(autoreverses: true), enabled: shouldAnimate),
                value: welcomeBlobAnimate
            )
        }
        .allowsHitTesting(false)
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

    private var introMetricsVisual: some View {
        let weightLabel = FlowLocalization.system("Weight", "Waga", "Peso", "Gewicht", "Poids", "Peso")
        let waistLabel = FlowLocalization.system("Waist", "Pas", "Cintura", "Taille", "Taille", "Cintura")
        let weightValueLabel = FlowLocalization.system("75.0 kg", "75,0 kg", "75,0 kg", "75,0 kg", "75,0 kg", "75,0 kg")
        let waistValueLabel = FlowLocalization.system("84.0 cm", "84,0 cm", "84,0 cm", "84,0 cm", "84,0 cm", "84,0 cm")
        let weightDeltaLabel = FlowLocalization.system("-2.1 kg", "-2,1 kg", "-2,1 kg", "-2,1 kg", "-2,1 kg", "-2,1 kg")
        let waistDeltaLabel = FlowLocalization.system("-4.0 cm", "-4,0 cm", "-4,0 cm", "-4,0 cm", "-4,0 cm", "-4,0 cm")
        let addLabel = FlowLocalization.system("Add metric", "Dodaj metrykę", "Añadir métrica", "Messung hinzufügen", "Ajouter une mesure", "Adicionar métrica")
        let goalLabel = FlowLocalization.system("Goal", "Cel", "Meta", "Ziel", "Objectif", "Meta")
        let trendLabel = FlowLocalization.system("Trend", "Trend", "Tendencia", "Trend", "Tendance", "Tendência")

        return VStack(spacing: IntroMetricsLayout.rowSpacing) {
            HStack(alignment: .top, spacing: IntroMetricsLayout.columnSpacing) {
                DummyMiniMetricChartCard(
                    title: weightLabel,
                    value: weightValueLabel,
                    delta: weightDeltaLabel,
                    tint: Color.appAccent,
                    backgroundTint: Color.appAccent,
                    points: [
                        CGPoint(x: 0.03, y: 0.72),
                        CGPoint(x: 0.23, y: 0.69),
                        CGPoint(x: 0.46, y: 0.56),
                        CGPoint(x: 0.67, y: 0.48),
                        CGPoint(x: 0.86, y: 0.33),
                        CGPoint(x: 0.97, y: 0.29)
                    ]
                )

                DummyMiniMetricChartCard(
                    title: waistLabel,
                    value: waistValueLabel,
                    delta: waistDeltaLabel,
                    tint: Color.cyan,
                    backgroundTint: Color.cyan.opacity(0.45),
                    points: [
                        CGPoint(x: 0.03, y: 0.34),
                        CGPoint(x: 0.22, y: 0.40),
                        CGPoint(x: 0.42, y: 0.49),
                        CGPoint(x: 0.63, y: 0.58),
                        CGPoint(x: 0.83, y: 0.65),
                        CGPoint(x: 0.97, y: 0.71)
                    ],
                    targetY: 0.62,
                    targetX: 0.84,
                    legends: [
                        DummyChartLegendItem(label: goalLabel, color: Color.appAccent),
                        DummyChartLegendItem(label: trendLabel, color: Color.cyan)
                    ]
                )
            }

            HStack(alignment: .top, spacing: IntroMetricsLayout.columnSpacing) {
                DummyMiniAddMetricCard(
                    systemName: "scalemass.fill",
                    title: addLabel,
                    subtitle: "\(weightLabel) \(weightValueLabel)"
                )

                DummyMiniAddMetricCard(
                    systemName: "ruler.fill",
                    title: addLabel,
                    subtitle: "\(waistLabel) \(waistValueLabel)"
                )
            }
        }
    }

    @State private var photoAfterAppeared = false

    private var introPhotosVisual: some View {
        let beforeLabel = FlowLocalization.system("Before", "Przed", "Antes", "Vorher", "Avant", "Antes")
        let afterLabel = FlowLocalization.system("After", "Po", "Después", "Nachher", "Après", "Depois")
        let compareLabel = FlowLocalization.system("Compare", "Porównaj", "Comparar", "Vergleichen", "Comparer", "Comparar")

        return HStack(spacing: 14) {
            // Before card
            ZStack {
                AppGlassBackground(depth: .base, cornerRadius: 26)
                VStack(spacing: 12) {
                    OnboardingSilhouette(tint: AppColorRoles.textTertiary.opacity(0.4))
                        .frame(width: 54, height: 90)
                    Text(beforeLabel)
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)
                }
            }

            // After card
            ZStack {
                AppGlassBackground(depth: .base, cornerRadius: 26, tint: Color.appAccent)
                VStack(spacing: 12) {
                    OnboardingSilhouette(tint: Color.appAccent)
                        .frame(width: 54, height: 90)
                    Text(afterLabel)
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)
                }
            }
            .opacity(photoAfterAppeared ? 1 : 0)
            .offset(x: photoAfterAppeared ? 0 : 40)
            .animation(shouldAnimate ? AppMotion.sectionEnter.delay(0.4) : .none, value: photoAfterAppeared)
        }
        .frame(height: 280)
        .overlay(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.34))
                .frame(width: 160, height: 42)
                .overlay {
                    HStack(spacing: 10) {
                        Image(systemName: "camera.metering.none")
                        Text(compareLabel)
                    }
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(Color.appWhite)
                }
                .offset(y: 24)
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
                        "Your photos and measurements stay on your device unless you choose otherwise.",
                        "Twoje zdjęcia i pomiary pozostają na urządzeniu, chyba że sam zdecydujesz inaczej.",
                        "Tus fotos y medidas permanecen en tu dispositivo salvo que elijas lo contrario.",
                        "Deine Fotos und Messwerte bleiben auf deinem Gerät, sofern du nichts anderes entscheidest.",
                        "Vos photos et mesures restent sur votre appareil sauf choix contraire.",
                        "Suas fotos e medições ficam no seu dispositivo, a menos que você escolha o contrário."
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
        ScrollView {
            AppGlassCard(depth: .elevated, cornerRadius: 28, tint: Color.appAccent, contentPadding: 22) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
    }

    private var personalizingTexts: [String] {
        [
            FlowLocalization.system("Analyzing your goals…", "Analizuję Twoje cele…", "Analizando tus objetivos…", "Deine Ziele werden analysiert…", "Analyse de vos objectifs…", "Analisando seus objetivos…"),
            FlowLocalization.system("Setting up your metrics…", "Konfiguruję Twoje metryki…", "Configurando tus métricas…", "Messwerte werden eingerichtet…", "Configuration de vos mesures…", "Configurando suas métricas…"),
            FlowLocalization.system("Almost there…", "Prawie gotowe…", "Casi listo…", "Fast fertig…", "Presque prêt…", "Quase pronto…")
        ]
    }

    private var personalizingStatusText: String {
        let texts = personalizingTexts
        return texts[min(personalizingTextIndex, texts.count - 1)]
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

    private var effectiveName: String {
        let trimmedInput = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInput.isEmpty { return trimmedInput }
        let trimmedStored = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStored.isEmpty { return trimmedStored }
        return FlowLocalization.system("there", "tam", "ahí", "da", "là", "aí")
    }

    private func handleAppear() {
        guard !hasTrackedStart else { return }
        hasTrackedStart = true
        nameInput = userName
        effects.track(.onboardingStarted)
        trackCurrentStep()
        syncUITestBridge(stepIndex: overallStepIndex)
        triggerSlideAppearance()
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
        switch phase {
        case .intro:
            Analytics.shared.track(
                signalName: "com.jacekzieba.measureme.onboarding.intro.slide_viewed",
                parameters: ["slide": "\(introIndex + 1)"]
            )
        case .input(let step):
            Analytics.shared.track(
                signalName: "com.jacekzieba.measureme.onboarding.input.step_viewed",
                parameters: ["step": step.analyticsName]
            )
        }
    }

    private func syncUITestBridge(stepIndex: Int) {
        guard isUITestOnboardingMode else { return }
        OnboardingUITestBridge.shared.update(currentStepIndex: stepIndex)
    }

    private func goToPreviousStep() {
        switch phase {
        case .intro:
            guard introIndex > 0 else { return }
            introIndex -= 1
        case .input(let step):
            guard canGoBack else { return }
            if let previous = InputStep(rawValue: step.rawValue - 1) {
                animateToInputStep(previous)
            } else {
                phase = .intro
                introIndex = totalIntroSlides - 1
            }
        }
    }

    private func goToNextStep() {
        switch phase {
        case .intro:
            if introIndex < totalIntroSlides - 1 {
                introIndex += 1
            } else {
                animateToInputStep(.name)
            }
        case .input(let step):
            switch step {
            case .name:
                persistNameIfNeeded()
                animateToInputStep(.greeting)
            case .greeting:
                animateToInputStep(.priority)
            case .priority:
                persistPriority()
                animateToInputStep(.personalizing)
            case .personalizing:
                break
            case .health:
                onboardingSkippedHealthKit = !isSyncEnabled
                animateToInputStep(.notifications)
            case .notifications:
                animateToInputStep(.completion)
            case .completion:
                finishOnboarding()
            }
        }
    }

    private func skipCurrentStep() {
        switch phase {
        case .intro:
            animateToInputStep(.name)
        case .input(let step):
            Analytics.shared.track(
                signalName: "com.jacekzieba.measureme.onboarding.input.step_skipped",
                parameters: ["step": step.analyticsName]
            )
            switch step {
            case .name:
                animateToInputStep(.greeting)
            case .greeting:
                animateToInputStep(.priority)
            case .priority:
                persistPriority()
                animateToInputStep(.health)
            case .personalizing:
                animateToInputStep(.health)
            case .health:
                onboardingSkippedHealthKit = true
                animateToInputStep(.notifications)
            case .notifications:
                onboardingSkippedReminders = true
                animateToInputStep(.completion)
            case .completion:
                finishOnboarding()
            }
        }
    }

    private func animateToInputStep(_ step: InputStep) {
        inputContentAppeared = false
        if shouldAnimate {
            withAnimation(AppMotion.emphasized) {
                phase = .input(step)
                inputStep = step
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(AppMotion.sectionEnter) {
                    inputContentAppeared = true
                }
            }
        } else {
            phase = .input(step)
            inputStep = step
            inputContentAppeared = true
        }
    }

    private func persistNameIfNeeded() {
        let trimmed = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            userName = trimmed
        }
        Analytics.shared.track(
            signalName: "com.jacekzieba.measureme.onboarding.input.step_completed",
            parameters: ["step": InputStep.name.analyticsName]
        )
    }

    private func persistPriority() {
        let priorities = resolvedPriorities
        let primaryPriority = priorities.first ?? .improveHealth
        onboardingPrimaryGoalRaw = priorities.map(\.rawValue).joined(separator: ",")
        applyMetricPackIfNeeded(priorities: priorities)
        Analytics.shared.track(
            signalName: "com.jacekzieba.measureme.onboarding.input.step_completed",
            parameters: [
                "step": InputStep.priority.analyticsName,
                "priority": primaryPriority.analyticsValue,
                "priorities": priorities.map(\.analyticsValue).joined(separator: ",")
            ]
        )
    }

    private func applyMetricPackIfNeeded(priorities: [OnboardingPriority]) {
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

    private func requestNotificationAccess() {
        guard !isRequestingNotifications else { return }
        isRequestingNotifications = true
        Analytics.shared.track(
            signalName: "com.jacekzieba.measureme.onboarding.notifications.prompt_shown",
            parameters: ["source": "onboarding"]
        )

        Task { @MainActor in
            let granted = await effects.requestNotificationAuthorization()
            effects.setNotificationsEnabled(granted)
            onboardingSkippedReminders = !granted
            isRequestingNotifications = false

            Analytics.shared.track(
                signalName: granted
                    ? "com.jacekzieba.measureme.onboarding.notifications.accepted"
                    : "com.jacekzieba.measureme.onboarding.notifications.declined",
                parameters: ["source": "onboarding"]
            )

            if granted {
                animateToInputStep(.completion)
            }
        }
    }

    private func finishOnboarding() {
        let priority = resolvedPriority
        persistPriority()
        onboardingFlowVersion = 2
        activationCurrentTaskID = ActivationTask.initial.rawValue
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
                "priorities": resolvedPriorities.map(\.analyticsValue).joined(separator: ","),
                "health_connected": isSyncEnabled ? "true" : "false"
            ]
        )
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

private enum IntroMetricsLayout {
    static let columnSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 14
    static let cardPadding: CGFloat = 14
    static let chartCardHeight: CGFloat = 166
    static let addCardHeight: CGFloat = 76
    static let chartHeight: CGFloat = 68
    static let legendHeight: CGFloat = 16
    static let valueBlockHeight: CGFloat = 42
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

    var body: some View {
        ZStack {
            AppGlassBackground(depth: .elevated, cornerRadius: 24, tint: backgroundTint)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
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
                .frame(height: IntroMetricsLayout.chartHeight)

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

                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.appWhite)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(delta)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                }
                .frame(maxWidth: .infinity, minHeight: IntroMetricsLayout.valueBlockHeight, alignment: .bottomLeading)
            }
            .padding(IntroMetricsLayout.cardPadding)
        }
        .frame(maxWidth: .infinity)
        .frame(height: IntroMetricsLayout.chartCardHeight)
    }
}

private struct DummyMiniAddMetricCard: View {
    let systemName: String
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            AppGlassBackground(depth: .base, cornerRadius: 20)

            HStack(spacing: AppSpacing.sm) {
                GlassPillIcon(systemName: systemName)
                    .frame(width: 54)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColorRoles.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: IntroMetricsLayout.addCardHeight)
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
