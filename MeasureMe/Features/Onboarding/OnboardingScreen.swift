import SwiftUI

@MainActor
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
    @State private var healthStatusLines: [String] = []
    @State private var healthAuthorizationPhase: HealthAuthorizationPhase = .idle
    @State private var healthAuthorizationVisualProgress: CGFloat = 0
    @State private var didPrewarmHealthKitAuthorization = false
    @State private var hasTrackedStart = false
    @State private var slideAppeared = false
    @State private var inputContentAppeared = false
    @State private var completionAppeared = false
    @State private var completionRippleScale: CGFloat = 0.5
    @State private var completionRippleOpacity: Double = 0.6

    private let isUITestOnboardingMode = UITestArgument.isPresent(.onboardingMode)

    init(effects: OnboardingEffects? = nil) {
        self.effects = effects ?? .live
    }

    private var shouldAnimate: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    private var totalIntroSlides: Int { 3 }
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
            if step == .name {
                return true
            }
            if step == .health {
                return !onboardingSkippedHealthKit && !isSyncEnabled
            }
            return false
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
        case .input:
            return FlowLocalization.system("Skip", "Pomiń", "Omitir", "Überspringen", "Passer", "Pular")
        }
    }

    private var isPrimaryEnabled: Bool {
        switch phase {
        case .intro:
            return true
        case .input(let step):
            switch step {
            case .name:
                return !nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .priority:
                return !selectedPriorities.isEmpty
            case .health:
                return !isRequestingHealthKit
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

            Spacer()

            introSkipLink
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var introSkipLink: some View {
        if case .intro = phase, introIndex > 0 {
            Button {
                skipCurrentStep()
            } label: {
                Text(FlowLocalization.system("Skip intro", "Pomiń intro", "Saltar intro", "Intro überspringen", "Passer l'intro", "Pular intro"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .frame(width: 92, alignment: .trailing)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.intro.skip")
        } else {
            Color.clear
                .frame(width: 92, height: 44)
                .accessibilityHidden(true)
        }
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
        ZStack {
            ambientBlobs(for: index)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            VStack(alignment: .leading, spacing: 22) {
                Spacer(minLength: 10)

                onboardingSlideHeader(
                    title: OnboardingCopy.introTitle(index: index),
                    subtitle: OnboardingCopy.introSubtitle(index: index)
                )
                .opacity(slideAppeared ? 1 : 0)
                .offset(y: slideAppeared ? 0 : 20)
                .animation(shouldAnimate ? AppMotion.sectionEnter.delay(0.05) : .none, value: slideAppeared)

                Group {
                    switch index {
                    case 0:
                        introMetricsVisual
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.top, AppSpacing.sm)
                    case 1:
                        introPhotosVisual
                    default:
                        introPrivacyVisual
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(slideAppeared ? 1 : 0)
                .offset(y: slideAppeared ? 0 : 24)
                .animation(shouldAnimate ? AppMotion.sectionEnter.delay(0.10) : .none, value: slideAppeared)

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
        case .priority:
            onboardingInputCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(OnboardingCopy.priorityPrompt(name: effectiveNameForGreeting))
                        .font(AppTypography.displaySection)
                        .foregroundStyle(AppColorRoles.textPrimary)

                    Text(OnboardingCopy.priorityHelper)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)

                    ForEach(OnboardingPriority.allCases, id: \.self) { priority in
                        let isSelected = selectedPriorities.contains(priority)
                        Button {
                            Haptics.selection()
                            selectedPriorities = OnboardingPrioritySelectionPolicy.toggled(priority, in: selectedPriorities)
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

    private var introMetricsVisual: some View {
        let weightLabel = FlowLocalization.system("Weight", "Waga", "Peso", "Gewicht", "Poids", "Peso")
        let waistLabel = FlowLocalization.system("Waist", "Pas", "Cintura", "Taille", "Taille", "Cintura")
        let weightValueLabel = FlowLocalization.system("75.0 kg", "75,0 kg", "75,0 kg", "75,0 kg", "75,0 kg", "75,0 kg")
        let waistValueLabel = FlowLocalization.system("84.0 cm", "84,0 cm", "84,0 cm", "84,0 cm", "84,0 cm", "84,0 cm")
        let weightDeltaLabel = FlowLocalization.system("-2.1 kg", "-2,1 kg", "-2,1 kg", "-2,1 kg", "-2,1 kg", "-2,1 kg")
        let waistDeltaLabel = FlowLocalization.system("-4.0 cm", "-4,0 cm", "-4,0 cm", "-4,0 cm", "-4,0 cm", "-4,0 cm")
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

            DummyAIInsightCard()
        }
    }

    @State private var photoAfterAppeared = false

    private var introPhotosVisual: some View {
        let beforeLabel = FlowLocalization.system("Before", "Przed", "Antes", "Vorher", "Avant", "Antes")
        let afterLabel = FlowLocalization.system("After", "Po", "Después", "Nachher", "Après", "Depois")
        let compareLabel = FlowLocalization.system("Compare", "Porównaj", "Comparar", "Vergleichen", "Comparer", "Comparar")

        return VStack(spacing: 12) {
            OnboardingBeforeAfterSlider(
                beforeImageName: "onboarding-before",
                afterImageName: "onboarding-after",
                beforeLabel: beforeLabel,
                afterLabel: afterLabel
            )
            .frame(width: 188, height: 280)
            .frame(maxWidth: .infinity)
            .opacity(photoAfterAppeared ? 1 : 0)
            .offset(y: photoAfterAppeared ? 0 : 18)
            .animation(shouldAnimate ? AppMotion.sectionEnter.delay(0.25) : .none, value: photoAfterAppeared)

            Capsule(style: .continuous)
                .fill(AppColorRoles.surfaceChrome.opacity(0.92))
                .frame(width: 168, height: 42)
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
        ScrollView {
            AppGlassCard(depth: .elevated, cornerRadius: 28, tint: Color.appAccent, contentPadding: 22) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
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

    private var effectiveNameForGreeting: String? {
        let trimmedInput = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInput.isEmpty { return trimmedInput }
        let trimmedStored = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStored.isEmpty { return trimmedStored }
        return nil
    }

    private func handleAppear() {
        guard !hasTrackedStart else { return }
        hasTrackedStart = true
        nameInput = userName
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
        guard isPrimaryEnabled else { return }
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
                animateToInputStep(.priority)
            case .priority:
                persistPriority()
                animateToInputStep(.health)
            case .health:
                onboardingSkippedHealthKit = !isSyncEnabled
                if isSyncEnabled {
                    animateToInputStep(.completion)
                } else {
                    finishOnboarding()
                }
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
                animateToInputStep(.priority)
            case .priority:
                persistPriority()
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

    private func finishOnboarding() {
        let priority = resolvedPriority
        persistPriority()
        onboardingFlowVersion = 2
        activationCurrentTaskID = onboardingSkippedHealthKit
            ? ActivationTask.firstMeasurement.rawValue
            : ActivationTask.initial.rawValue
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

private enum IntroMetricsLayout {
    static let columnSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 20
    static let cardPadding: CGFloat = 14
    static let chartCardHeight: CGFloat = 210
    static let chartHeight: CGFloat = 90
    static let legendHeight: CGFloat = 16
    static let valueBlockHeight: CGFloat = 48
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

                VStack(alignment: .leading, spacing: 3) {
                    Text(value)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.appWhite)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(delta)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
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

private struct DummyAIInsightCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColorRoles.accentPrimary)
                    .frame(width: 30, height: 30)
                    .background(AppColorRoles.accentPrimary.opacity(0.14))
                    .clipShape(Circle())

                Text(healthSummaryTitle)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
            }

            VStack(alignment: .leading, spacing: 6) {
                summaryLineOne
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                summaryLineTwo
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColorRoles.accentPrimary)
                    .padding(.top, 1)

                Text(tipText)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            AppGlassBackground(depth: .base, cornerRadius: 20, tint: AppColorRoles.accentPrimary.opacity(0.05))
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var healthSummaryTitle: String {
        FlowLocalization.system(
            "Health Summary",
            "Podsumowanie zdrowia",
            "Resumen de salud",
            "Gesundheitsübersicht",
            "Résumé santé",
            "Resumo de saúde"
        )
    }

    private var summaryLineOne: Text {
        Text(FlowLocalization.system(
            "Weight is down ",
            "Waga spadła o ",
            "El peso bajó ",
            "Gewicht ist um ",
            "Le poids baisse de ",
            "O peso caiu "
        ))
        + Text(FlowLocalization.system(
            "-2.1 kg",
            "-2,1 kg",
            "-2,1 kg",
            "-2,1 kg",
            "-2,1 kg",
            "-2,1 kg"
        ))
        .foregroundColor(AppColorRoles.stateSuccess)
        + Text(FlowLocalization.system(
            " and waist is ",
            ", a talia ",
            " y la cintura ",
            " und Taille um ",
            " et le tour de taille ",
            " e a cintura "
        ))
        + Text(FlowLocalization.system(
            "-4.0 cm",
            "-4,0 cm",
            "-4,0 cm",
            "-4,0 cm",
            "-4,0 cm",
            "-4,0 cm"
        ))
        .foregroundColor(AppColorRoles.accentPrimary)
        + Text(FlowLocalization.system(
            " over recent check-ins.",
            " w ostatnich zapisach.",
            " en los últimos registros.",
            " in den letzten Check-ins.",
            " sur les derniers relevés.",
            " nos check-ins recentes."
        ))
    }

    private var summaryLineTwo: Text {
        Text(FlowLocalization.system(
            "Core indicators are moving in the right direction, not just scale weight.",
            "Kluczowe wskaźniki idą w dobrym kierunku, nie tylko waga.",
            "Los indicadores clave van en la dirección correcta, no solo el peso.",
            "Die Kernwerte bewegen sich in die richtige Richtung, nicht nur das Gewicht.",
            "Les indicateurs clés vont dans la bonne direction, pas seulement le poids.",
            "Os indicadores principais estão indo na direção certa, não só o peso."
        ))
    }

    private var tipText: String {
        FlowLocalization.system(
            "Keep the same routine this week and add one protein-focused meal.",
            "Utrzymaj rutynę w tym tygodniu i dodaj jeden posiłek z większą ilością białka.",
            "Mantén la rutina esta semana y añade una comida con más proteína.",
            "Bleib diese Woche bei der Routine und ergänze eine proteinreiche Mahlzeit.",
            "Gardez la même routine cette semaine et ajoutez un repas riche en protéines.",
            "Mantenha a rotina esta semana e adicione uma refeição com mais proteína."
        )
    }
}

private struct OnboardingBeforeAfterSlider: View {
    let beforeImageName: String
    let afterImageName: String
    let beforeLabel: String
    let afterLabel: String

    @State private var sliderPosition: CGFloat = 0.5
    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let clampedSlider = min(max(sliderPosition, 0), 1)

            ZStack {
                AppColorRoles.surfaceChrome.opacity(0.86)

                Image(beforeImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width, height: height)

                Image(afterImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width, height: height)
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
