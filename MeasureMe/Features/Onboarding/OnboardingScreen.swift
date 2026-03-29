import SwiftUI
import UIKit

struct OnboardingView: View {
    private let effects: OnboardingEffects
    @AppSetting(\.onboarding.hasCompletedOnboarding) private var hasCompletedOnboarding: Bool = false
    @AppSetting(\.profile.userName) private var userName: String = ""
    @AppSetting(\.profile.userAge) private var userAge: Int = 0
    @AppSetting(\.profile.userGender) private var userGender: String = "notSpecified"
    @AppSetting(\.profile.manualHeight) private var manualHeight: Double = 0.0
    @AppSetting(\.health.isSyncEnabled) private var isSyncEnabled: Bool = false
    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @AppSetting(\.onboarding.onboardingSkippedHealthKit) private var onboardingSkippedHealthKit: Bool = false
    @AppSetting(\.onboarding.onboardingSkippedReminders) private var onboardingSkippedReminders: Bool = false
    @AppSetting(\.onboarding.onboardingChecklistShow) private var showOnboardingChecklistOnHome: Bool = true
    @AppSetting(\.onboarding.onboardingChecklistPremiumExplored) private var onboardingChecklistPremiumExplored: Bool = false
    @AppSetting(\.onboarding.onboardingPrimaryGoal) private var onboardingPrimaryGoalsRaw: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @EnvironmentObject private var premiumStore: PremiumStore

    @State private var currentStepIndex: Int
    @State private var scrolledStepID: Int?
    @FocusState private var focusedField: FocusField?

    @State private var nameInput: String = ""
    @State private var ageInput: String = ""
    @State private var heightInput: String = ""
    @State private var feetInput: String = ""
    @State private var inchesInput: String = ""

    @State private var isRequestingHealthKit: Bool = false
    @State private var isRequestingNotifications: Bool = false
    @State private var isReminderScheduled: Bool = false
    @State private var showReminderSetupSheet: Bool = false
    @State private var reminderWeekday: Int = 2
    @State private var reminderTime: Date = AppClock.now
    @State private var reminderRepeat: ReminderRepeat = .weekly
    @State private var reminderOnceDate: Date = AppClock.now
    @State private var healthKitStatusText: String?
    @State private var notificationsStatusText: String?
    @State private var selectedWelcomeGoals: Set<WelcomeGoal> = []

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

    private var stepStatusText: String? {
        switch currentStep {
        case .boosters:
            return notificationsStatusText ?? healthKitStatusText
        default:
            return nil
        }
    }

    private var nextButtonTitle: String {
        AppLocalization.systemString("Continue")
    }

    private var sortedWelcomeGoals: [WelcomeGoal] {
        selectedWelcomeGoals.sorted { $0.rawValue < $1.rawValue }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AppBackground()
            backdrop

            GeometryReader { proxy in
                let baseReserve: CGFloat = {
                    // Podczas edycji (widoczna klawiatura) utrzymuj minimalna przerwe
                    if focusedField != nil { return 8 }
                    // W przeciwnym razie rezerwuj miejsce na stopke i elementy statusu
                    if currentStep == .welcome && !dynamicTypeSize.isAccessibilitySize { return 110 }
                    return (stepStatusText == nil) ? 122 : 146
                }()
                let accessibilityReserve: CGFloat = dynamicTypeSize.isAccessibilitySize ? 68 : 0
                let keyboardReserve: CGFloat = 0
                let bottomReserve = baseReserve + keyboardReserve + accessibilityReserve
                let extra: CGFloat = (focusedField != nil) ? 0 : (dynamicTypeSize.isAccessibilitySize ? 8 : 20)
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
                                OnboardingProfileStep(
                                    nameInput: $nameInput,
                                    ageInput: $ageInput,
                                    heightInput: $heightInput,
                                    feetInput: $feetInput,
                                    inchesInput: $inchesInput,
                                    userGender: $userGender,
                                    unitsSystem: unitsSystem,
                                    focused: $focusedField
                                )
                            }
                            .containerRelativeFrame(.horizontal)
                            .id(Step.profile.rawValue)

                            slideCard {
                                OnboardingBoostersStep(
                                    isSyncEnabled: isSyncEnabled,
                                    isReminderScheduled: isReminderScheduled,
                                    isRequestingHealthKit: isRequestingHealthKit,
                                    isRequestingNotifications: isRequestingNotifications,
                                    onRequestHealthKit: requestHealthKitAccess,
                                    onSetupReminder: { showReminderSetupSheet = true }
                                )
                            }
                            .containerRelativeFrame(.horizontal)
                            .id(Step.boosters.rawValue)
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

                    if focusedField == nil {
                        privacyNote
                            .padding(.top, 6)
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.bottom, 2)
                    }
                }
                .safeAreaPadding(.top, 10)
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                if focusedField != nil {
                    dismissKeyboard()
                }
            }
        )
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
            dismissKeyboard()
            Haptics.selection()
            syncUITestBridge()
            if let signal = AnalyticsSignal.onboardingStepViewed(stepIndex: currentStepIndex) {
                effects.track(signal)
            }
        }
        .sheet(isPresented: $showReminderSetupSheet) {
            OnboardingReminderSetupSheet(
                repeatRule: $reminderRepeat,
                weekday: $reminderWeekday,
                time: $reminderTime,
                onceDate: $reminderOnceDate
            ) {
                showReminderSetupSheet = false
                setupReminder()
            }
        }
        .overlay(alignment: .topLeading) {
            if showReminderSetupSheet {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("onboarding.reminder.sheet.visible")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focusedField == nil {
                VStack(spacing: 10) {
                    footer
                }
                .padding(.bottom, 8)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: effects.notificationsDidChangeName)) { _ in
            isReminderScheduled = effects.isReminderScheduled()
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
                ForEach(0..<totalSteps, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index <= currentStepIndex ? Color.appAccent : AppColorRoles.borderSubtle)
                        .frame(maxWidth: .infinity)
                        .frame(height: 5)
                }
            }
            .frame(maxWidth: .infinity)

            Button(AppLocalization.systemString("Skip")) {
                skipCurrentStep()
            }
            .font(AppTypography.microEmphasis)
            .foregroundStyle(Color.appGray)
            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            .accessibilityIdentifier("onboarding.skip")
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
            .scrollDisabled(!isScrollEnabled)
            .scrollDismissesKeyboard(.immediately)
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
            .buttonStyle(.bordered)
            .tint(Color.appGray.opacity(0.34))
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
            .buttonStyle(.borderedProminent)
            .tint(Color.appAccent)
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
        dismissKeyboard()
        guard currentStepIndex > 0 else { return }
        animateToStep(currentStepIndex - 1)
    }

    private func goToNextStep() {
        dismissKeyboard()
        switch currentStep {
        case .welcome:
            break
        case .profile:
            persistProfile()
        case .boosters:
            persistBoostersOutcome()
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
        dismissKeyboard()
        if currentStep == .boosters {
            persistBoostersOutcome()
        }

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            dismissKeyboard()
        }
    }

    private func finishOnboarding() {
        persistWelcomeGoals()
        persistProfile()
        persistBoostersOutcome()
        showOnboardingChecklistOnHome = true
        onboardingChecklistPremiumExplored = onboardingChecklistPremiumExplored || premiumStore.isPremium
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
        nameInput = userName
        selectedWelcomeGoals = parseWelcomeGoals(from: onboardingPrimaryGoalsRaw)

        if userAge > 0 {
            ageInput = "\(userAge)"
        }

        if manualHeight > 0 {
            let display = MetricKind.height.valueForDisplay(fromMetric: manualHeight, unitsSystem: unitsSystem)
            if unitsSystem == "imperial" {
                let totalInches = Int(display.rounded())
                feetInput = "\(totalInches / 12)"
                inchesInput = "\(totalInches % 12)"
            } else {
                heightInput = String(format: "%.1f", display)
            }
        }

        let reminderSeed = effects.loadReminderSeed(defaultWeeklyReminderDate: defaultWeeklyReminderDate())
        reminderRepeat = reminderSeed.repeatRule
        reminderWeekday = reminderSeed.reminderWeekday
        reminderTime = reminderSeed.reminderTime
        reminderOnceDate = reminderSeed.reminderOnceDate
        isReminderScheduled = reminderSeed.isReminderScheduled
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

    private func persistProfile() {
        userName = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if let parsedAge = Int(ageInput), (5...120).contains(parsedAge) {
            userAge = parsedAge
        }

        if unitsSystem == "imperial" {
            if let feet = Int(feetInput), let inches = Int(inchesInput), feet >= 0, inches >= 0, inches < 12, (feet > 0 || inches > 0) {
                let totalInches = Double(feet * 12 + inches)
                manualHeight = MetricKind.height.valueToMetric(fromDisplay: totalInches, unitsSystem: unitsSystem)
            }
        } else if let value = parseLocalizedDouble(heightInput), value > 0 {
            manualHeight = MetricKind.height.valueToMetric(fromDisplay: value, unitsSystem: unitsSystem)
        }
    }

    private func persistBoostersOutcome() {
        onboardingSkippedHealthKit = !isSyncEnabled
        onboardingSkippedReminders = !isReminderScheduled
    }

    // MARK: - Effects

    private func requestHealthKitAccess() {
        guard !isSyncEnabled else { return }
        guard !isRequestingHealthKit else { return }

        dismissKeyboard()
        isRequestingHealthKit = true
        healthKitStatusText = AppLocalization.systemString("Requesting Health access...")

        Task { @MainActor in
            do {
                try await effects.requestHealthKitAuthorization()
                isSyncEnabled = true
                healthKitStatusText = AppLocalization.systemString("Health sync enabled. Importing data in background.")
                Haptics.success()
                isRequestingHealthKit = false
            } catch {
                isSyncEnabled = false
                healthKitStatusText = HealthKitManager.userFacingSyncErrorMessage(for: error)
                Haptics.error()
                isRequestingHealthKit = false
            }
        }
    }

    private func setupReminder() {
        guard !isReminderScheduled else { return }
        guard !isRequestingNotifications else { return }

        dismissKeyboard()
        isRequestingNotifications = true
        notificationsStatusText = AppLocalization.string("Requesting notification permission...")

        Task { @MainActor in
            let granted = await effects.requestNotificationAuthorization()
            guard granted else {
                effects.setNotificationsEnabled(false)
                notificationsStatusText = AppLocalization.string("Notifications denied. You can enable them later in Settings.")
                isRequestingNotifications = false
                Haptics.error()
                return
            }

            effects.setNotificationsEnabled(true)

            let targetDate: Date
            switch reminderRepeat {
            case .weekly:
                targetDate = reminderDate(weekday: reminderWeekday, time: reminderTime)
                effects.setSmartTime(reminderTime)
            case .daily:
                targetDate = dailyReminderDate(time: reminderTime)
                effects.setSmartTime(reminderTime)
            case .once:
                targetDate = reminderOnceDate
                effects.setSmartTime(reminderOnceDate)
            }

            effects.upsertReminder(date: targetDate, repeatRule: reminderRepeat)
            isReminderScheduled = effects.isReminderScheduled()
            notificationsStatusText = AppLocalization.string("Reminder is set.")
            isRequestingNotifications = false
            Haptics.success()
        }
    }

    private func defaultWeeklyReminderDate() -> Date {
        reminderDate(weekday: 2, time: defaultReminderTime())
    }

    private func defaultReminderTime() -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: AppClock.now)
        components.hour = 7
        components.minute = 0
        return calendar.date(from: components) ?? AppClock.now
    }

    private func dailyReminderDate(time: Date, from now: Date = AppClock.now) -> Date {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        var todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        todayComponents.hour = timeComponents.hour
        todayComponents.minute = timeComponents.minute
        let todayTarget = calendar.date(from: todayComponents) ?? now
        if todayTarget > now {
            return todayTarget
        }
        return calendar.date(byAdding: .day, value: 1, to: todayTarget) ?? todayTarget
    }

    private func reminderDate(weekday: Int, time: Date, from now: Date = AppClock.now) -> Date {
        let calendar = Calendar.current
        let clampedWeekday = min(max(weekday, 1), 7)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        let hour = timeComponents.hour ?? 7
        let minute = timeComponents.minute ?? 0

        let components = DateComponents(hour: hour, minute: minute, weekday: clampedWeekday)
        return calendar.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .nextTime,
            direction: .forward
        ) ?? now.addingTimeInterval(7 * 24 * 3600)
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
