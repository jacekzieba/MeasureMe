import SwiftUI

struct OnboardingView: View {
    private enum Phase: Equatable {
        case intro
        case input(InputStep)
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
    @State private var selectedPriority: OnboardingPriority?
    @State private var isRequestingHealthKit = false
    @State private var isRequestingNotifications = false
    @State private var healthStatusLines: [String] = []
    @State private var didAutoAdvancePersonalizing = false
    @State private var hasTrackedStart = false

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
            case .health:
                return !isRequestingHealthKit
            case .notifications:
                return !isRequestingNotifications
            default:
                return true
            }
        }
    }

    private var resolvedPriority: OnboardingPriority {
        selectedPriority ?? .improveHealth
    }

    private var recommendedKinds: [MetricKind] {
        GoalMetricPack.recommendedKinds(for: resolvedPriority)
    }

    var body: some View {
        ZStack {
            AppBackground()

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
                .transition(.opacity)
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
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 10)

            onboardingSlideHeader(
                title: OnboardingCopy.introTitle(index: index),
                subtitle: OnboardingCopy.introSubtitle(index: index)
            )

            Group {
                switch index {
                case 0:
                    introWelcomeVisual
                case 1:
                    introMetricsVisual
                case 2:
                    introPhotosVisual
                case 3:
                    introHealthVisual
                default:
                    introPrivacyVisual
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Spacer(minLength: 0)
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
                        Button {
                            Haptics.selection()
                            selectedPriority = priority
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

                                Image(systemName: selectedPriority == priority ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(selectedPriority == priority ? Color.appAccent : AppColorRoles.textTertiary)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(selectedPriority == priority ? Color.appAccent.opacity(0.12) : AppColorRoles.surfaceInteractive)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(selectedPriority == priority ? Color.appAccent.opacity(0.45) : AppColorRoles.borderSubtle, lineWidth: 1)
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
                    ProgressView()
                        .controlSize(.large)
                    Text(OnboardingCopy.personalizingTitle)
                        .font(AppTypography.displaySection)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    Text(OnboardingCopy.prioritySubtitle(resolvedPriority))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textSecondary)
                }
            }
            .task {
                guard !didAutoAdvancePersonalizing else { return }
                didAutoAdvancePersonalizing = true
                try? await Task.sleep(for: .milliseconds(1250))
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

                    flowChipList(labels: OnboardingCopy.recommendedMetricTitles(for: resolvedPriority))

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
                        Text(OnboardingCopy.healthAllowCTA)
                            .foregroundStyle(AppColorRoles.textOnAccent)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
                    }
                    .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
                    .disabled(isRequestingHealthKit)
                    .accessibilityIdentifier("onboarding.health.allow")
                }
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
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(AppColorRoles.stateSuccess)
                    Text(OnboardingCopy.completionTitle)
                        .font(AppTypography.displaySection)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    Text(OnboardingCopy.completionBody)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textSecondary)

                    VStack(alignment: .leading, spacing: 10) {
                        flowSummaryRow(
                            title: FlowLocalization.system("Priority", "Priorytet", "Prioridad", "Priorität", "Priorité", "Prioridade"),
                            value: OnboardingCopy.priorityTitle(resolvedPriority)
                        )
                        flowSummaryRow(
                            title: FlowLocalization.system("Health", "Health", "Salud", "Health", "Santé", "Health"),
                            value: isSyncEnabled ? FlowLocalization.system("Connected", "Połączono", "Conectado", "Verbunden", "Connecté", "Conectado") : FlowLocalization.system("Skipped", "Pominięto", "Omitido", "Übersprungen", "Passé", "Ignorado")
                        )
                    }
                }
            }
        }
    }

    private var introWelcomeVisual: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.appAccent.opacity(0.24), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 220)
                .overlay {
                    VStack(spacing: 14) {
                        Image(systemName: "scope")
                            .font(.system(size: 58, weight: .light))
                            .foregroundStyle(Color.appAccent)
                        Text(OnboardingCopy.motto)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.appWhite)
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
        }
    }

    private var introMetricsVisual: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(AppColorRoles.surfacePrimary.opacity(0.78))
                .frame(height: 220)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Waist")
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(AppColorRoles.textSecondary)

                        DummyLineChart()
                            .frame(height: 100)

                        HStack {
                            Text("84.0 cm")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.appWhite)
                            Spacer()
                            Text("-2.4 cm")
                                .font(AppTypography.captionEmphasis)
                                .foregroundStyle(Color.appAccent)
                        }
                    }
                    .padding(18)
                }

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
                .frame(height: 84)
                .overlay {
                    HStack(spacing: 14) {
                        GlassPillIcon(systemName: "ruler.fill")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Add metric")
                                .font(AppTypography.bodyEmphasis)
                                .foregroundStyle(AppColorRoles.textPrimary)
                            Text("Waist 84.0 cm")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColorRoles.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }
        }
    }

    private var introPhotosVisual: some View {
        HStack(spacing: 14) {
            ForEach(0..<2, id: \.self) { index in
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(index == 0 ? Color.white.opacity(0.06) : Color.appAccent.opacity(0.18))
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: index == 0 ? "figure.stand" : "figure.strengthtraining.traditional")
                                .font(.system(size: 54, weight: .light))
                                .foregroundStyle(index == 0 ? AppColorRoles.textSecondary : Color.appAccent)
                            Text(index == 0 ? "Before" : "After")
                                .font(AppTypography.captionEmphasis)
                                .foregroundStyle(AppColorRoles.textPrimary)
                        }
                    }
            }
        }
        .frame(height: 280)
        .overlay(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.34))
                .frame(width: 160, height: 42)
                .overlay {
                    HStack(spacing: 10) {
                        Image(systemName: "camera.metering.none")
                        Text("Compare")
                    }
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(Color.appWhite)
                }
                .offset(y: 24)
        }
    }

    private var introHealthVisual: some View {
        VStack(spacing: 14) {
            DummyIndicatorCard(title: "Waist-to-Height", value: "0.47", legend: "On track", tint: AppColorRoles.stateSuccess)
            DummyIndicatorCard(title: "Body Fat", value: "18%", legend: "On track", tint: Color.appAccent)
            DummyIndicatorCard(title: "Shoulder-to-Waist", value: "1.52", legend: "Strong", tint: Color(hex: "#F59E0B"))
        }
    }

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

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(AppColorRoles.surfacePrimary.opacity(0.82))
                .frame(height: 220)
                .overlay {
                    VStack(spacing: 18) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 54))
                            .foregroundStyle(Color.appAccent)
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
        }
    }

    private func onboardingInputCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
            }
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppColorRoles.surfacePrimary.opacity(0.86))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                    )
            )
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
    }

    private func flowSummaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
            Spacer()
            Text(value)
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(AppColorRoles.textPrimary)
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
        if shouldAnimate {
            withAnimation(AppMotion.reveal) {
                phase = .input(step)
                inputStep = step
            }
        } else {
            phase = .input(step)
            inputStep = step
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
        let priority = resolvedPriority
        onboardingPrimaryGoalRaw = priority.rawValue
        applyMetricPackIfNeeded(priority: priority)
        Analytics.shared.track(
            signalName: "com.jacekzieba.measureme.onboarding.input.step_completed",
            parameters: ["step": InputStep.priority.analyticsName, "priority": priority.analyticsValue]
        )
    }

    private func applyMetricPackIfNeeded(priority: OnboardingPriority) {
        guard !effects.hasCustomizedMetrics() else { return }
        effects.applyMetricPack(GoalMetricPack.recommendedKinds(for: priority))
    }

    private func requestHealthAccess() {
        guard !isRequestingHealthKit else { return }
        isRequestingHealthKit = true
        Analytics.shared.track(
            signalName: "com.jacekzieba.measureme.onboarding.health.prompt_shown",
            parameters: ["source": "onboarding"]
        )

        Task { @MainActor in
            defer { isRequestingHealthKit = false }
            do {
                try await effects.requestHealthKitAuthorization()
                isSyncEnabled = true
                onboardingSkippedHealthKit = false

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

                Analytics.shared.track(
                    signalName: "com.jacekzieba.measureme.onboarding.health.accepted",
                    parameters: ["source": "onboarding"]
                )
            } catch {
                isSyncEnabled = false
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
                Analytics.shared.track(
                    signalName: "com.jacekzieba.measureme.onboarding.health.declined",
                    parameters: ["source": "onboarding"]
                )
            }
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
            parameters: ["priority": priority.analyticsValue, "health_connected": isSyncEnabled ? "true" : "false"]
        )
    }
}

private struct DummyLineChart: View {
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
                .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
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
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppColorRoles.surfacePrimary.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                )
        )
    }
}
