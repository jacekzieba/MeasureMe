import SwiftUI
import SwiftData
import UIKit

struct OnboardingView: View {
    private let effects: OnboardingEffects
    @AppSetting(\.onboarding.hasCompletedOnboarding) private var hasCompletedOnboarding: Bool = false
    @AppSetting(\.health.isSyncEnabled) private var isSyncEnabled: Bool = false
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @AppSetting(\.onboarding.onboardingSkippedHealthKit) private var onboardingSkippedHealthKit: Bool = false
    // Kept because HomeScreen reads it to decide checklist reminders item visibility
    @AppSetting(\.onboarding.onboardingSkippedReminders) private var onboardingSkippedReminders: Bool = false
    @AppSetting(\.onboarding.onboardingChecklistShow) private var showOnboardingChecklistOnHome: Bool = true
    @AppSetting(\.onboarding.onboardingChecklistPremiumExplored) private var onboardingChecklistPremiumExplored: Bool = false
    @AppSetting(\.onboarding.onboardingPrimaryGoal) private var onboardingPrimaryGoalsRaw: String = ""
    @AppSetting(\.onboarding.onboardingActivationCompleted) private var onboardingActivationCompleted: Bool = false
    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var premiumStore: PremiumStore

    @State private var currentStepIndex: Int
    @State private var scrolledStepID: Int?

    @State private var isRequestingHealthKit: Bool = false
    @State private var healthKitStatusText: String?
    @State private var selectedWelcomeGoals: Set<WelcomeGoal> = []

    // First measurement state (step 2)
    @State private var measurementEntries: [MetricKind: String] = [:]
    @State private var didSaveFirstMeasurement: Bool = false

    @State private var animateBackdrop: Bool = false
    private let isUITestOnboardingMode = UITestArgument.isPresent(.onboardingMode)

    init(
        initialStepIndex: Int = 0,
        effects: OnboardingEffects = .live
    ) {
        self.effects = effects
        let clamped = max(0, min(initialStepIndex, Step.allCases.count - 1))
        _currentStepIndex = State(initialValue: clamped)
    }

    private var shouldAnimate: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    private var currentStep: Step {
        Step(rawValue: currentStepIndex) ?? .welcome
    }

    private var totalSteps: Int {
        Step.allCases.count
    }

    private var progressSteps: [Step] { Step.progressSteps }

    private var progressIndex: Int {
        progressSteps.firstIndex(of: currentStep) ?? 0
    }

    private var stepStatusText: String? {
        switch currentStep {
        case .firstMeasurement:
            return nil
        default:
            return nil
        }
    }

    private var nextButtonTitle: String {
        AppLocalization.systemString("Continue")
    }

    /// Whether the Continue button should be enabled.
    private var isNextEnabled: Bool {
        switch currentStep {
        case .firstMeasurement:
            return hasAtLeastOneValidEntry || isSyncEnabled
        default:
            return true
        }
    }

    /// Whether the Skip button should be visible.
    private var isSkipVisible: Bool {
        switch currentStep {
        case .welcome, .firstMeasurement:
            return true
        }
    }

    private var sortedWelcomeGoals: [WelcomeGoal] {
        selectedWelcomeGoals.sorted { $0.rawValue < $1.rawValue }
    }

    /// Recommended metric kinds based on selected goals.
    private var recommendedKinds: [MetricKind] {
        GoalMetricPack.recommendedKinds(for: selectedWelcomeGoals)
    }

    /// Whether at least one measurement field has a valid numeric value.
    private var hasAtLeastOneValidEntry: Bool {
        measurementEntries.values.contains { text in
            guard let value = parseDecimal(text), value > 0 else { return false }
            return true
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AppBackground()
            backdrop

            GeometryReader { proxy in
                let baseReserve: CGFloat = {
                    if currentStep == .welcome && !dynamicTypeSize.isAccessibilitySize { return 110 }
                    return (stepStatusText == nil) ? 122 : 146
                }()
                let accessibilityReserve: CGFloat = dynamicTypeSize.isAccessibilitySize ? 68 : 0
                let bottomReserve = baseReserve + accessibilityReserve
                let extra: CGFloat = dynamicTypeSize.isAccessibilitySize ? 8 : 20
                let cardHeight = safeCardHeight(from: proxy.size.height, reserved: bottomReserve, extra: extra)

                VStack(spacing: 0) {
                    topBar

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: AppSpacing.sm) {
                            slideCard {
                                OnboardingWelcomeStep(
                                    selectedGoals: $selectedWelcomeGoals,
                                    onGoalToggled: toggleWelcomeGoal
                                )
                            }
                            .containerRelativeFrame(.horizontal)
                            .id(Step.welcome.rawValue)

                            slideCard {
                                OnboardingFirstMeasurementStep(
                                    recommendedKinds: recommendedKinds,
                                    entries: $measurementEntries,
                                    unitsSystem: unitsSystem,
                                    isHealthKitSyncEnabled: isSyncEnabled,
                                    isRequestingHealthKit: isRequestingHealthKit,
                                    healthKitStatusText: healthKitStatusText,
                                    onRequestHealthKit: requestHealthKitAccess
                                )
                            }
                            .containerRelativeFrame(.horizontal)
                            .id(Step.firstMeasurement.rawValue)

                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $scrolledStepID)
                    .contentMargins(.horizontal, AppSpacing.md, for: .scrollContent)
                    .padding(.top, AppSpacing.sm)
                    .frame(height: cardHeight)

                    if let stepStatusText {
                        Text(stepStatusText)
                            .font(AppTypography.caption)
                            .foregroundStyle(Color.appAccent)
                            .padding(.top, 10)
                    }

                    privacyNote
                        .padding(.top, 6)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.bottom, 2)
                }
                .safeAreaPadding(.top, 10)
            }
        }
        .onAppear {
            hydrate()
            animateBackdrop = true
            scrolledStepID = currentStepIndex
            syncUITestBridge()
            effects.track(.onboardingStarted)
            if let signal = AnalyticsSignal.onboardingStepViewed(stepIndex: currentStepIndex) {
                effects.track(signal)
            }
        }
        .onChange(of: scrolledStepID) { _, newValue in
            guard let newValue, newValue != currentStepIndex else { return }
            currentStepIndex = newValue
        }
        .onChange(of: currentStepIndex) { _, _ in
            Haptics.selection()
            syncUITestBridge()
            if let signal = AnalyticsSignal.onboardingStepViewed(stepIndex: currentStepIndex) {
                effects.track(signal)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                footer
            }
            .padding(.bottom, 8)
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

    // MARK: - Shared sub-views

    private var backdrop: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.appAccent.opacity(0.30), .clear],
                        center: .center,
                        startRadius: 30,
                        endRadius: 240
                    )
                )
                .frame(width: 320, height: 320)
                .offset(x: animateBackdrop ? 120 : 70, y: animateBackdrop ? -210 : -160)
                .blur(radius: 12)
                .animation(
                    AppMotion.repeating(.easeInOut(duration: 4.2).repeatForever(autoreverses: true), enabled: shouldAnimate),
                    value: animateBackdrop
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColorRoles.surfacePrimary.opacity(0.8), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 190
                    )
                )
                .frame(width: 250, height: 250)
                .offset(x: animateBackdrop ? -120 : -80, y: animateBackdrop ? 170 : 210)
                .blur(radius: 12)
                .animation(
                    AppMotion.repeating(.easeInOut(duration: 5.2).repeatForever(autoreverses: true), enabled: shouldAnimate),
                    value: animateBackdrop
                )
        }
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<progressSteps.count, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index <= progressIndex ? Color.appAccent : AppColorRoles.borderSubtle)
                        .frame(maxWidth: .infinity)
                        .frame(height: 5)
                }
            }
            .frame(maxWidth: .infinity)

            if isSkipVisible {
                Button(AppLocalization.systemString("Skip")) {
                    skipCurrentStep()
                }
                .font(AppTypography.microEmphasis)
                .foregroundStyle(Color.appGray)
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                .accessibilityIdentifier("onboarding.skip")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 24)
    }

    private func slideCard<Content: View>(
        isScrollEnabled: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        AppGlassCard(
            depth: .floating,
            cornerRadius: 26,
            tint: Color.appAccent.opacity(0.16),
            contentPadding: 0
        ) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    content()
                }
                .padding(dynamicTypeSize.isAccessibilitySize ? 20 : 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollDisabled(!isScrollEnabled)
        }
        .shadow(color: .clear, radius: 0, x: 0, y: 0)
    }

    private var privacyNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.appGray)

            Text(AppLocalization.systemString("Your data stays on this device by default. You can change backup and sync options later in Settings."))
                .font(AppTypography.micro)
                .foregroundStyle(Color.appGray)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.privacy.note")
    }

    private var footer: some View {
        HStack(spacing: AppSpacing.sm) {
            Button {
                goToPreviousStep()
            } label: {
                Text(AppLocalization.systemString("Back"))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(AppSecondaryButtonStyle(cornerRadius: AppRadius.md))
            .disabled(currentStepIndex == 0)
            .appHitTarget()
            .accessibilityIdentifier("onboarding.back")
            .accessibilitySortPriority(2)

            Button {
                goToNextStep()
            } label: {
                Text(nextButtonTitle)
                    .foregroundStyle(AppColorRoles.textOnAccent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
            .disabled(!isNextEnabled)
            .appHitTarget()
            .accessibilityIdentifier("onboarding.next")
            .accessibilitySortPriority(3)
        }
        .padding(.horizontal, AppSpacing.lg)
    }

    private func syncUITestBridge() {
        guard isUITestOnboardingMode else { return }
        OnboardingUITestBridge.shared.update(
            currentStepIndex: currentStepIndex
        )
    }

    // MARK: - Navigation

    private func goToPreviousStep() {
        guard currentStepIndex > 0 else { return }
        animateToStep(currentStepIndex - 1)
    }

    private func goToNextStep() {
        switch currentStep {
        case .welcome:
            applyGoalMetricPackIfNeeded()
        case .firstMeasurement:
            saveFirstMeasurementIfNeeded()
        }

        let next = min(currentStepIndex + 1, totalSteps - 1)
        if next == currentStepIndex {
            finishOnboarding()
            return
        }
        animateToStep(next)
    }

    private func skipCurrentStep() {
        effects.track(.onboardingSkipped)

        let next = min(currentStepIndex + 1, totalSteps - 1)
        if next == currentStepIndex {
            finishOnboarding()
            return
        }
        animateToStep(next)
    }

    private func animateToStep(_ index: Int) {
        if shouldAnimate {
            withAnimation(AppMotion.reveal) {
                scrolledStepID = index
            }
        } else {
            scrolledStepID = index
        }
    }

    private func finishOnboarding() {
        persistWelcomeGoals()
        persistHealthKitOutcome()
        applyGoalMetricPackIfNeeded()
        showOnboardingChecklistOnHome = true
        onboardingChecklistPremiumExplored = onboardingChecklistPremiumExplored || premiumStore.isPremium
        // Mark activation as completed since we now handle it inline
        onboardingActivationCompleted = true
        Haptics.success()
        effects.track(.onboardingCompleted)

        if shouldAnimate {
            withAnimation(AppMotion.quick) {
                hasCompletedOnboarding = true
            }
        } else {
            hasCompletedOnboarding = true
        }
    }

    // MARK: - Data

    private func hydrate() {
        selectedWelcomeGoals = parseWelcomeGoals(from: onboardingPrimaryGoalsRaw)
    }

    private func toggleWelcomeGoal(_ goal: WelcomeGoal) {
        var updated = selectedWelcomeGoals
        if updated.contains(goal) {
            updated.remove(goal)
        } else {
            updated.insert(goal)
            recordWelcomeGoalSelectionStat(for: goal)
        }
        selectedWelcomeGoals = updated
        persistWelcomeGoals()
    }

    private func parseWelcomeGoals(from raw: String) -> Set<WelcomeGoal> {
        let parts = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let values = parts.compactMap(WelcomeGoal.init(rawValue:))
        return Set(values)
    }

    private func persistWelcomeGoals() {
        onboardingPrimaryGoalsRaw = sortedWelcomeGoals.map(\.rawValue).joined(separator: ",")
    }

    private func recordWelcomeGoalSelectionStat(for goal: WelcomeGoal) {
        effects.incrementWelcomeGoalSelectionStat(goalRawValue: goal.rawValue)

        switch goal {
        case .loseWeight:  effects.track(.onboardingGoalLoseWeight)
        case .buildMuscle: effects.track(.onboardingGoalBuildMuscle)
        case .trackHealth: effects.track(.onboardingGoalTrackHealth)
        }
    }

    private func persistHealthKitOutcome() {
        onboardingSkippedHealthKit = !isSyncEnabled
    }

    private func applyGoalMetricPackIfNeeded() {
        guard !effects.hasCustomizedMetrics() else { return }
        let kinds = GoalMetricPack.recommendedKinds(for: selectedWelcomeGoals)
        effects.applyMetricPack(kinds)
        effects.track(.activationRecommendedMetricsAccepted)
    }

    // MARK: - First measurement

    /// Parses entered values and saves them via QuickAddSaveService.
    private func saveFirstMeasurementIfNeeded() {
        guard !didSaveFirstMeasurement else { return }

        var entries: [QuickAddSaveService.Entry] = []

        for kind in recommendedKinds {
            guard let text = measurementEntries[kind],
                  let displayValue = parseDecimal(text),
                  displayValue > 0 else { continue }

            // Convert display value back to metric (base) units for storage
            let metricValue = kind.valueToMetric(fromDisplay: displayValue, unitsSystem: unitsSystem)
            entries.append(QuickAddSaveService.Entry(kind: kind, metricValue: metricValue))
        }

        guard !entries.isEmpty else { return }

        do {
            try effects.saveFirstMeasurement(
                entries: entries,
                date: Date(),
                unitsSystem: unitsSystem,
                context: modelContext
            )
            didSaveFirstMeasurement = true
        } catch {
            AppLog.debug("⚠️ Failed to save first measurement during onboarding: \(error.localizedDescription)")
        }
    }

    /// Parses a decimal string, accepting both . and , as decimal separators.
    private func parseDecimal(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    // MARK: - Effects

    private func requestHealthKitAccess() {
        guard !isSyncEnabled else { return }
        guard !isRequestingHealthKit else { return }

        isRequestingHealthKit = true
        healthKitStatusText = AppLocalization.systemString("Requesting Health access...")
        effects.track(.onboardingHealthSyncPromptShown)

        Task { @MainActor in
            do {
                try await effects.requestHealthKitAuthorization()
                isSyncEnabled = true
                healthKitStatusText = AppLocalization.systemString("Health sync enabled. Importing data in background.")
                effects.track(.onboardingHealthSyncAccepted)
                Haptics.success()
                isRequestingHealthKit = false
            } catch {
                isSyncEnabled = false
                healthKitStatusText = HealthKitManager.userFacingSyncErrorMessage(for: error)
                effects.track(.onboardingHealthSyncDeclined)
                Haptics.error()
                isRequestingHealthKit = false
            }
        }
    }
}
