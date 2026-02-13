import SwiftUI
import UIKit
import Charts
import StoreKit

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userAge") private var userAge: Int = 0
    @AppStorage("userGender") private var userGender: String = "notSpecified"
    @AppStorage("manualHeight") private var manualHeight: Double = 0.0
    @AppStorage("isSyncEnabled") private var isSyncEnabled: Bool = false
    @AppStorage("unitsSystem") private var unitsSystem: String = "metric"
    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true
    @AppStorage("onboarding_skipped_healthkit") private var onboardingSkippedHealthKit: Bool = false
    @AppStorage("onboarding_skipped_reminders") private var onboardingSkippedReminders: Bool = false
    @AppStorage("onboarding_checklist_show") private var showOnboardingChecklistOnHome: Bool = true
    @AppStorage("onboarding_checklist_premium_explored") private var onboardingChecklistPremiumExplored: Bool = false
    @AppStorage("onboarding_primary_goal") private var onboardingPrimaryGoalsRaw: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var premiumStore: PremiumStore

    @State private var currentStepIndex: Int = 0
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
    @State private var reminderTime: Date = .now
    @State private var healthKitStatusText: String?
    @State private var notificationsStatusText: String?
    @State private var selectedWelcomeGoals: Set<WelcomeGoal> = []
    @State private var onboardingSelectedPremiumProductID: String? = PremiumConstants.yearlyProductID

    @State private var animateBackdrop: Bool = false

    private enum FocusField: Hashable {
        case name
        case age
        case height
        case feet
        case inches
    }

    private enum WelcomeGoal: String, CaseIterable {
        case loseWeight
        case buildMuscle
        case trackHealth

        var title: String {
            switch self {
            case .loseWeight:
                return AppLocalization.systemString("Lose weight")
            case .buildMuscle:
                return AppLocalization.systemString("Build muscles")
            case .trackHealth:
                return AppLocalization.systemString("Improve my health")
            }
        }
    }

    private enum Step: Int, CaseIterable {
        case welcome
        case profile
        case boosters
        case premium

        var title: String {
            switch self {
            case .welcome:
                return AppLocalization.systemString("MeasureMe")
            case .profile:
                return AppLocalization.systemString("A few details")
            case .boosters:
                return AppLocalization.systemString("Boosters")
            case .premium:
                return AppLocalization.systemString("Premium Edition")
            }
        }

        var subtitle: String {
            switch self {
            case .welcome:
                return ""
            case .profile:
                return AppLocalization.systemString("Optional details for more accurate health indicators.")
            case .boosters:
                return AppLocalization.systemString("Optional automations to keep momentum.")
            case .premium:
                return ""
            }
        }
    }

    private var shouldAnimate: Bool {
        animationsEnabled && !reduceMotion
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
        switch currentStep {
        case .premium:
            return AppLocalization.systemString("Continue free")
        default:
            return AppLocalization.systemString("Continue")
        }
    }

    private var sortedWelcomeGoals: [WelcomeGoal] {
        selectedWelcomeGoals.sorted { $0.rawValue < $1.rawValue }
    }

    private var yearlyProduct: Product? {
        premiumStore.products.first { $0.id == PremiumConstants.yearlyProductID }
    }

    private var monthlyProduct: Product? {
        premiumStore.products.first { $0.id == PremiumConstants.monthlyProductID }
    }

    private var onboardingPremiumProducts: [Product] {
        premiumStore.products
            .filter { $0.id == PremiumConstants.monthlyProductID || $0.id == PremiumConstants.yearlyProductID }
            .sorted { $0.price < $1.price }
    }

    private var onboardingSelectedPremiumProduct: Product? {
        if let onboardingSelectedPremiumProductID {
            return onboardingPremiumProducts.first { $0.id == onboardingSelectedPremiumProductID }
        }
        return yearlyProduct ?? monthlyProduct
    }

    private var onboardingYearlySavingsPercent: Int? {
        guard let monthlyProduct, let yearlyProduct else { return nil }
        let yearlyFromMonthly = monthlyProduct.price * Decimal(12)
        guard yearlyFromMonthly > 0 else { return nil }
        let savings = (yearlyFromMonthly - yearlyProduct.price) / yearlyFromMonthly
        guard savings > 0 else { return nil }
        let percent = NSDecimalNumber(decimal: savings * Decimal(100)).doubleValue
        return Int(percent.rounded())
    }

    var body: some View {
        ZStack {
            AppBackground()
            backdrop

            GeometryReader { proxy in
                let baseReserve: CGFloat = {
                    // When editing (keyboard visible), keep the gap minimal
                    if focusedField != nil { return 8 }
                    // Otherwise, reserve space for footer and status elements
                    return (stepStatusText == nil) ? 122 : 146
                }()
                let keyboardReserve: CGFloat = 0
                let bottomReserve = baseReserve + keyboardReserve
                let extra: CGFloat = (focusedField != nil) ? 0 : 20
                let cardHeight = safeCardHeight(from: proxy.size.height, reserved: bottomReserve, extra: extra)

                VStack(spacing: 0) {
                    topBar

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 0) {
                            slideCard {
                                welcomeSlide
                            }
                            .containerRelativeFrame(.horizontal)
                            .id(Step.welcome.rawValue)

                            slideCard {
                                profileSlide
                            }
                            .containerRelativeFrame(.horizontal)
                            .id(Step.profile.rawValue)

                            slideCard {
                                boostersSlide
                            }
                            .containerRelativeFrame(.horizontal)
                            .id(Step.boosters.rawValue)

                            slideCard {
                                premiumSlide
                            }
                            .containerRelativeFrame(.horizontal)
                            .id(Step.premium.rawValue)
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $scrolledStepID)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
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
                            .padding(.horizontal, 24)
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
            if onboardingSelectedPremiumProductID == nil {
                onboardingSelectedPremiumProductID = PremiumConstants.yearlyProductID
            }
        }
        .onChange(of: scrolledStepID) { _, newValue in
            guard let newValue, newValue != currentStepIndex else { return }
            currentStepIndex = newValue
        }
        .onChange(of: currentStepIndex) { _, _ in
            dismissKeyboard()
            Haptics.selection()
            if currentStep == .premium, onboardingPremiumProducts.isEmpty {
                Task { await premiumStore.loadProducts() }
            }
        }
        .sheet(isPresented: $showReminderSetupSheet) {
            OnboardingReminderSetupSheet(
                weekday: $reminderWeekday,
                time: $reminderTime
            ) {
                showReminderSetupSheet = false
                setupWeeklyReminder(weekday: reminderWeekday, time: reminderTime)
            }
        }
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focusedField == nil {
                VStack(spacing: 10) {
                    footer
                }
                .padding(.bottom, 8)
            }
        }
    }

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
                .animation(shouldAnimate ? .easeInOut(duration: 4.2).repeatForever(autoreverses: true) : nil, value: animateBackdrop)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.08), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 190
                    )
                )
                .frame(width: 250, height: 250)
                .offset(x: animateBackdrop ? -120 : -80, y: animateBackdrop ? 170 : 210)
                .blur(radius: 12)
                .animation(shouldAnimate ? .easeInOut(duration: 5.2).repeatForever(autoreverses: true) : nil, value: animateBackdrop)
        }
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index <= currentStepIndex ? Color.appAccent : Color.white.opacity(0.16))
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
        }
        .padding(.horizontal, 24)
    }

    private func slideCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        AppGlassCard(
            depth: .floating,
            cornerRadius: 26,
            tint: Color.appAccent.opacity(0.16),
            contentPadding: 0
        ) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    content()
                }
                .padding(18)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private var welcomeSlide: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                slideHeader(title: Step.welcome.title, subtitle: Step.welcome.subtitle)
                Spacer(minLength: 0)
                Image("BrandMark")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
            }

            welcomeGoalSelector
            welcomeExamplePreview
        }
    }

    private var profileSlide: some View {
        VStack(alignment: .leading, spacing: 14) {
            slideHeader(title: Step.profile.title, subtitle: Step.profile.subtitle)

            profileField(title: AppLocalization.systemString("Name")) {
                TextField(AppLocalization.systemString("e.g., Jacek"), text: $nameInput)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .name)
            }

            profileField(title: AppLocalization.systemString("Height")) {
                if unitsSystem == "imperial" {
                    HStack(spacing: 10) {
                        TextField(AppLocalization.systemString("Feet"), text: $feetInput)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .feet)
                        TextField(AppLocalization.systemString("Inches"), text: $inchesInput)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .inches)
                    }
                } else {
                    TextField(AppLocalization.systemString("Centimeters"), text: $heightInput)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .height)
                }
            }

            HStack(spacing: 10) {
                profileField(title: AppLocalization.systemString("Sex")) {
                    Picker("", selection: $userGender) {
                        Text(AppLocalization.systemString("Not specified")).tag("notSpecified")
                        Text(AppLocalization.systemString("Male")).tag("male")
                        Text(AppLocalization.systemString("Female")).tag("female")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }

            profileField(title: AppLocalization.systemString("Age")) {
                TextField(AppLocalization.systemString("Age in years"), text: $ageInput)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .age)
            }

            VStack(alignment: .leading, spacing: 8) {
                reasonRow(icon: "person.fill", text: AppLocalization.systemString("Name helps personalize your experience."))
                reasonRow(icon: "figure.stand", text: AppLocalization.systemString("Height improves BMI and waist-to-height indicators."))
                reasonRow(icon: "calendar", text: AppLocalization.systemString("Age and sex tune ranges for selected indicators."))
            }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(AppLocalization.systemString("You can skip and fill this later."))
                .font(AppTypography.caption)
                .foregroundStyle(Color.appGray)
        }
    }

    private var boostersSlide: some View {
        VStack(alignment: .leading, spacing: 14) {
            slideHeader(title: Step.boosters.title, subtitle: Step.boosters.subtitle)

            boosterCard(
                icon: "heart.text.square",
                title: AppLocalization.systemString("Sync with Apple Health"),
                detail: AppLocalization.systemString("Import history and keep measurements updated automatically."),
                why: AppLocalization.systemString("Why: your charts start with more context."),
                buttonTitle: isSyncEnabled ? AppLocalization.systemString("Connected") : AppLocalization.systemString("Connect"),
                isLoading: isRequestingHealthKit,
                isComplete: isSyncEnabled,
                action: requestHealthKitAccess
            )

            boosterCard(
                icon: "bell.badge",
                title: AppLocalization.systemString("Weekly reminder"),
                detail: AppLocalization.systemString("One gentle nudge per week keeps momentum."),
                why: AppLocalization.systemString("Why: consistency beats intensity."),
                buttonTitle: isReminderScheduled ? AppLocalization.systemString("Scheduled") : AppLocalization.systemString("Set schedule"),
                isLoading: isRequestingNotifications,
                isComplete: isReminderScheduled,
                action: { showReminderSetupSheet = true }
            )
        }
    }

    private var premiumSlide: some View {
        VStack(alignment: .leading, spacing: 14) {
            slideHeader(title: Step.premium.title, subtitle: Step.premium.subtitle)

            premiumUnlockBundleTile
            onboardingPlanPicker

            Button {
                onboardingChecklistPremiumExplored = true
                Haptics.light()
                if let product = onboardingSelectedPremiumProduct {
                    Task { await premiumStore.purchase(product) }
                } else {
                    premiumStore.presentPaywall(reason: .onboarding)
                }
            } label: {
                Text(AppLocalization.systemString("Start my 14-day free trial"))
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 24)
            }
            .buttonStyle(.bordered)
            .tint(Color.appAccent)
            .controlSize(.small)

            onboardingBilledAfterTrialText
                .font(AppTypography.micro)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func slideHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.72)
                .lineLimit(2)
                .foregroundStyle(Color.appWhite)

            if !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(subtitle)
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.appGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var welcomeGoalSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLocalization.systemString("What's your goal?"))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(Color.appWhite)

            VStack(spacing: 8) {
                ForEach(WelcomeGoal.allCases, id: \.self) { goal in
                    welcomeGoalOptionRow(goal)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func welcomeGoalOptionRow(_ goal: WelcomeGoal) -> some View {
        let isSelected = selectedWelcomeGoals.contains(goal)
        return Button {
            toggleWelcomeGoal(goal)
            Haptics.selection()
        } label: {
            HStack(spacing: 10) {
                Text(goal.title)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.86))

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.appAccent : Color.white.opacity(0.35))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.appAccent.opacity(0.14) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.appAccent.opacity(0.7) : Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private struct WelcomeTrendPoint: Identifiable {
        let id: Int
        let week: Int
        let value: Double
    }

    private var welcomeTrendPoints: [WelcomeTrendPoint] {
        [
            WelcomeTrendPoint(id: 0, week: 1, value: 82.4),
            WelcomeTrendPoint(id: 1, week: 2, value: 82.3),
            WelcomeTrendPoint(id: 2, week: 3, value: 82.0),
            WelcomeTrendPoint(id: 3, week: 4, value: 82.1),
            WelcomeTrendPoint(id: 4, week: 5, value: 81.8),
            WelcomeTrendPoint(id: 5, week: 6, value: 81.6),
            WelcomeTrendPoint(id: 6, week: 7, value: 81.7),
            WelcomeTrendPoint(id: 7, week: 8, value: 81.3),
            WelcomeTrendPoint(id: 8, week: 9, value: 81.1),
            WelcomeTrendPoint(id: 9, week: 10, value: 81.0),
            WelcomeTrendPoint(id: 10, week: 11, value: 80.9),
            WelcomeTrendPoint(id: 11, week: 12, value: 80.6),
            WelcomeTrendPoint(id: 12, week: 13, value: 80.7),
            WelcomeTrendPoint(id: 13, week: 14, value: 80.4),
            WelcomeTrendPoint(id: 14, week: 15, value: 80.2),
            WelcomeTrendPoint(id: 15, week: 16, value: 80.1),
            WelcomeTrendPoint(id: 16, week: 17, value: 79.9),
            WelcomeTrendPoint(id: 17, week: 18, value: 79.7)
        ]
    }

    private var welcomeGoalValue: Double {
        79.0
    }

    private var welcomeXAxisValues: [Int] {
        [1, 4, 7, 10, 13, 16, 18]
    }

    private var welcomeLastTrendPoint: WelcomeTrendPoint? {
        welcomeTrendPoints.last
    }

    private var welcomeWeekDomain: ClosedRange<Int> {
        guard let firstWeek = welcomeTrendPoints.first?.week,
              let lastWeek = welcomeTrendPoints.last?.week,
              firstWeek < lastWeek else {
            return 1...2
        }
        return firstWeek...lastWeek
    }

    private var welcomeTrendDomain: ClosedRange<Double> {
        let values = (welcomeTrendPoints.map(\.value) + [welcomeGoalValue]).filter(\.isFinite)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }

        let padding = max((maxValue - minValue) * 0.18, 0.5)
        let lower = minValue - padding
        let upper = maxValue + padding

        guard lower.isFinite, upper.isFinite, lower < upper else {
            return 0...1
        }

        return lower...upper
    }

    private var welcomeTrendPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                Text(AppLocalization.systemString("onboarding.trend.delta"))
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(Color(hex: "#22C55E"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "#22C55E").opacity(0.16))
                    .clipShape(Capsule(style: .continuous))

                Text(AppLocalization.systemString("onboarding.goal.badge", welcomeGoalValue))
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(Color(hex: "#22C55E"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "#22C55E").opacity(0.16))
                    .clipShape(Capsule(style: .continuous))
            }

            Chart {
                RuleMark(y: .value("Goal", welcomeGoalValue))
                    .lineStyle(StrokeStyle(lineWidth: 1.1, dash: [5, 4]))
                    .foregroundStyle(Color(hex: "#22C55E").opacity(0.9))

                ForEach(welcomeTrendPoints) { point in
                    AreaMark(
                        x: .value("Week", point.week),
                        yStart: .value("Baseline", welcomeTrendDomain.lowerBound),
                        yEnd: .value("Weight", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.appAccent.opacity(0.28), Color.appAccent.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Week", point.week),
                        y: .value("Weight", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.appAccent)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

                    if let lastPoint = welcomeLastTrendPoint, lastPoint.id == point.id {
                        PointMark(
                            x: .value("Week", point.week),
                            y: .value("Weight", point.value)
                        )
                        .symbolSize(44)
                        .foregroundStyle(Color.appAccent)

                        PointMark(
                            x: .value("Week", point.week),
                            y: .value("Goal", welcomeGoalValue)
                        )
                        .symbolSize(36)
                        .foregroundStyle(Color(hex: "#22C55E"))
                    }
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .padding(.bottom, 8)
            }
            .chartXAxis {
                AxisMarks(values: welcomeXAxisValues) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8))
                        .foregroundStyle(Color.white.opacity(0.08))
                    AxisTick(stroke: StrokeStyle(lineWidth: 0.8))
                        .foregroundStyle(Color.white.opacity(0.18))
                    AxisValueLabel {
                        if let week = value.as(Int.self) {
                            Text(AppLocalization.systemString("onboarding.week.label", week))
                                .font(AppTypography.micro)
                                .foregroundStyle(Color.appGray)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 1)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8))
                        .foregroundStyle(Color.white.opacity(0.08))
                    AxisTick(stroke: StrokeStyle(lineWidth: 0.8))
                        .foregroundStyle(Color.white.opacity(0.18))
                }
            }
            .chartXScale(domain: welcomeWeekDomain)
            .chartYScale(domain: welcomeTrendDomain)
            .frame(height: 122)
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var welcomeInsightPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            MetricInsightCard(
                text: AppLocalization.systemString("You’re trending down steadily. Keep 3 strength sessions and 8k+ steps this week."),
                compact: false,
                isLoading: false
            )
        }
    }

    private var welcomeExamplePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 20, height: 20)
                    .background(Color.appAccent.opacity(0.18))
                    .clipShape(Circle())

                Text(AppLocalization.systemString("onboarding.example.label"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.96))
            }

            welcomeTrendPreview
            welcomeInsightPreview
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appAccent.opacity(0.26), lineWidth: 1)
        )
    }

    private var premiumUnlockBundleTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.appAccent.opacity(0.26))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.appAccent)
                    )

                Text(AppLocalization.string("premium.unlock.bundle.title"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.92))
            }

            premiumUnlockBenefitRow(icon: "sparkles", tint: Color(hex: "#4ADE80"), textKey: "premium.carousel.unlock.item.ai")
            premiumUnlockBenefitRow(icon: "photo.on.rectangle.angled", tint: Color(hex: "#60A5FA"), textKey: "premium.carousel.unlock.item.compare")
            premiumUnlockBenefitRow(icon: "heart.text.square.fill", tint: Color(hex: "#34D399"), textKey: "premium.carousel.unlock.item.health")
            premiumUnlockBenefitRow(icon: "doc.text.fill", tint: Color(hex: "#FBBF24"), textKey: "premium.carousel.unlock.item.export")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.09), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        )
    }

    private func premiumUnlockBenefitRow(icon: String, tint: Color, textKey: String) -> some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18, alignment: .leading)

            Text(AppLocalization.string(textKey))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "#FCA311"))
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var onboardingPlanPicker: some View {
        VStack(spacing: 10) {
            if onboardingPremiumProducts.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(Color.appAccent)
                    Text(AppLocalization.string("premium.subscription.loading"))
                        .font(AppTypography.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
            } else {
                ForEach(onboardingPremiumProducts, id: \.id) { product in
                    onboardingPlanRow(product: product)
                }
            }
        }
    }

    private func onboardingPlanRow(product: Product) -> some View {
        let isSelected = product.id == onboardingSelectedPremiumProductID
        let badge = onboardingPlanBadge(for: product)

        return Button {
            onboardingSelectedPremiumProductID = product.id
            Haptics.selection()
        } label: {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(onboardingPlanTitle(for: product))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                        Text(onboardingPlanSubtitle(for: product))
                            .font(AppTypography.caption)
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(onboardingPriceLine(for: product))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.9)

                        if product.id == PremiumConstants.yearlyProductID,
                           let onboardingYearlySavingsPercent {
                            Text(AppLocalization.string("premium.plan.save.percent", onboardingYearlySavingsPercent))
                                .font(AppTypography.micro)
                                .foregroundStyle(.white.opacity(0.64))
                        }
                    }
                    .padding(.top, badge == nil ? 0 : 16)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .padding(.top, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? Color.appAccent.opacity(0.16) : Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isSelected ? Color.appAccent : Color.white.opacity(0.14), lineWidth: 1)
                        )
                )

                if let badge {
                    Text(badge.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.92))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.appAccent)
                        )
                        .offset(y: -9)
                        .padding(.trailing, 10)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func onboardingPlanTitle(for product: Product) -> String {
        switch product.id {
        case PremiumConstants.monthlyProductID:
            return AppLocalization.string("premium.plan.monthly")
        case PremiumConstants.yearlyProductID:
            return AppLocalization.string("premium.plan.yearly")
        default:
            return product.displayName
        }
    }

    private func onboardingPlanSubtitle(for product: Product) -> String {
        switch product.id {
        case PremiumConstants.monthlyProductID:
            return AppLocalization.string("premium.plan.billing.monthly")
        case PremiumConstants.yearlyProductID:
            return AppLocalization.string("premium.plan.billing.yearly")
        default:
            return AppLocalization.string("premium.plan.billing.default")
        }
    }

    private func onboardingPlanBadge(for product: Product) -> String? {
        guard product.id == PremiumConstants.yearlyProductID else { return nil }
        return AppLocalization.string("premium.plan.best.value")
    }

    private func onboardingPriceLine(for product: Product) -> String {
        switch product.id {
        case PremiumConstants.monthlyProductID:
            return "\(product.displayPrice)/\(AppLocalization.string("premium.plan.period.month"))"
        case PremiumConstants.yearlyProductID:
            let monthlyEquivalent = product.price / Decimal(12)
            let monthlyEquivalentDisplay = monthlyEquivalent.formatted(product.priceFormatStyle)
            return AppLocalization.string("premium.plan.just.monthly.dynamic", monthlyEquivalentDisplay)
        default:
            return product.displayPrice
        }
    }

    private var onboardingBilledAfterTrialText: Text {
        let product = onboardingSelectedPremiumProduct ?? yearlyProduct ?? monthlyProduct
        guard let product else {
            return Text(AppLocalization.string("premium.cta.billed.after.trial.fallback"))
        }

        let periodLabel: String
        if product.id == PremiumConstants.yearlyProductID {
            periodLabel = AppLocalization.string("premium.plan.period.year")
        } else {
            periodLabel = AppLocalization.string("premium.plan.period.month")
        }

        let amountWithPeriod = "\(product.displayPrice)/\(periodLabel)"
        let prefix = AppLocalization.string("premium.cta.billed.prefix")
        let suffix = AppLocalization.string("premium.cta.billed.suffix")

        var attributed = AttributedString("\(prefix)\(amountWithPeriod)\(suffix)")
        if let emphasizedRange = attributed.range(of: amountWithPeriod) {
            attributed[emphasizedRange].inlinePresentationIntent = .stronglyEmphasized
        }
        return Text(attributed)
    }

    private func profileField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(Color.appWhite)
            content()
        }
    }

    private func reasonRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.appAccent)
                .frame(width: 16)
            Text(text)
                .font(AppTypography.caption)
                .foregroundStyle(Color.appGray)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func boosterCard(
        icon: String,
        title: String,
        detail: String,
        why: String,
        buttonTitle: String,
        isLoading: Bool,
        isComplete: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            OnboardingFeatureCard(icon: icon, title: title, detail: detail)

            Text(why)
                .font(AppTypography.caption)
                .foregroundStyle(Color.appGray)

            Button {
                action()
            } label: {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.appAccent)
                    }
                    Text(buttonTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .tint(Color.appAccent)
            .disabled(isLoading || isComplete)
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var privacyNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.appGray)

            Text(AppLocalization.systemString("Your data stays on this device. Nothing is shared with us."))
                .font(AppTypography.micro)
                .foregroundStyle(Color.appGray)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                goToPreviousStep()
            } label: {
                Text(AppLocalization.systemString("Back"))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 32)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(Color.appGray.opacity(0.34))
            .disabled(currentStepIndex == 0)

            Button {
                goToNextStep()
            } label: {
                Text(nextButtonTitle)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Color.appAccent)
        }
        .padding(.horizontal, 24)
    }

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
        case .premium:
            finishOnboarding()
            return
        }

        let next = min(currentStepIndex + 1, totalSteps - 1)
        if next == currentStepIndex {
            finishOnboarding()
            return
        }
        animateToStep(next)
    }

    private func skipCurrentStep() {
        dismissKeyboard()
        if currentStep == .boosters {
            persistBoostersOutcome()
        }

        if currentStep == .premium {
            finishOnboarding()
            return
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
            withAnimation(.easeOut(duration: 0.35)) {
                scrolledStepID = index
                currentStepIndex = index
            }
        } else {
            scrolledStepID = index
            currentStepIndex = index
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

        if shouldAnimate {
            withAnimation(.easeInOut(duration: 0.18)) {
                hasCompletedOnboarding = true
            }
        } else {
            hasCompletedOnboarding = true
        }
    }

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

        let reminders = NotificationManager.shared.loadReminders()
        if let weeklyReminder = reminders.first(where: { $0.repeatRule == .weekly }) {
            let calendar = Calendar.current
            reminderWeekday = calendar.component(.weekday, from: weeklyReminder.date)
            reminderTime = weeklyReminder.date
        } else {
            let defaultReminder = defaultWeeklyReminderDate()
            let calendar = Calendar.current
            reminderWeekday = calendar.component(.weekday, from: defaultReminder)
            reminderTime = defaultReminder
        }
        isReminderScheduled = NotificationManager.shared.notificationsEnabled && !reminders.isEmpty
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

    private func safeCardHeight(from containerHeight: CGFloat, reserved: CGFloat, extra: CGFloat = 0) -> CGFloat {
        guard containerHeight.isFinite, containerHeight > 0 else { return 1 }
        let safeReserved = reserved.isFinite ? max(reserved, 0) : 82
        let safeExtra = extra.isFinite ? extra : 0
        let candidate = containerHeight - safeReserved + safeExtra
        let minimumCardHeight = min(max(containerHeight * 0.55, 180), containerHeight)
        let maximumCardHeight = max(containerHeight - 20, minimumCardHeight)
        guard candidate.isFinite else {
            return minimumCardHeight
        }
        return min(max(candidate, minimumCardHeight), maximumCardHeight)
    }

    private func recordWelcomeGoalSelectionStat(for goal: WelcomeGoal) {
        let defaults = UserDefaults.standard
        let key = "onboarding_goal_selection_stat_\(goal.rawValue)"
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
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

    private func parseLocalizedDouble(_ raw: String) -> Double? {
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func requestHealthKitAccess() {
        guard !isSyncEnabled else { return }
        guard !isRequestingHealthKit else { return }

        dismissKeyboard()
        isRequestingHealthKit = true
        healthKitStatusText = AppLocalization.systemString("Requesting Health access...")

        Task { @MainActor in
            do {
                try await HealthKitManager.shared.requestAuthorization()
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

    private func setupWeeklyReminder(weekday: Int, time: Date) {
        guard !isReminderScheduled else { return }
        guard !isRequestingNotifications else { return }

        dismissKeyboard()
        isRequestingNotifications = true
        notificationsStatusText = AppLocalization.systemString("Requesting notification permission...")

        Task { @MainActor in
            let granted = await NotificationManager.shared.requestAuthorization()
            guard granted else {
                NotificationManager.shared.notificationsEnabled = false
                notificationsStatusText = AppLocalization.systemString("Notifications denied. You can enable them later in Settings.")
                isRequestingNotifications = false
                Haptics.error()
                return
            }

            NotificationManager.shared.notificationsEnabled = true
            let weeklyDate = reminderDate(weekday: weekday, time: time)
            var reminders = NotificationManager.shared.loadReminders()

            if let weeklyIndex = reminders.firstIndex(where: { $0.repeatRule == .weekly }) {
                let existing = reminders[weeklyIndex]
                reminders[weeklyIndex] = MeasurementReminder(
                    id: existing.id,
                    date: weeklyDate,
                    repeatRule: .weekly
                )
            } else {
                reminders.append(MeasurementReminder(date: weeklyDate, repeatRule: .weekly))
            }

            NotificationManager.shared.smartTime = time
            NotificationManager.shared.saveReminders(reminders)
            NotificationManager.shared.scheduleAllReminders(reminders)

            isReminderScheduled = true
            notificationsStatusText = AppLocalization.systemString("Weekly reminder is set.")
            isRequestingNotifications = false
            Haptics.success()
        }
    }

    private func defaultWeeklyReminderDate() -> Date {
        reminderDate(weekday: 2, time: defaultReminderTime())
    }

    private func defaultReminderTime() -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 7
        components.minute = 0
        return calendar.date(from: components) ?? Date()
    }

    private func reminderDate(weekday: Int, time: Date, from now: Date = Date()) -> Date {
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

private struct OnboardingReminderSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var weekday: Int
    @Binding var time: Date
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Picker(AppLocalization.systemString("Reminder day"), selection: $weekday) {
                    ForEach(1...7, id: \.self) { index in
                        Text(weekdayTitle(index)).tag(index)
                    }
                }

                DatePicker(
                    AppLocalization.systemString("Reminder time"),
                    selection: $time,
                    displayedComponents: .hourAndMinute
                )
            }
            .navigationTitle(AppLocalization.systemString("Reminder schedule"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.systemString("Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.systemString("Set reminder")) {
                        onConfirm()
                        dismiss()
                    }
                }
            }
        }
    }

    private func weekdayTitle(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols[safe: weekday - 1] ?? symbols.first ?? "—"
    }
}

private struct OnboardingRulerSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    @State private var dragStartValue: Double? = nil
    @State private var lastHapticStep: Int? = nil

    private let pointsPerStep: CGFloat = 10
    private let horizontalInset: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let drawableWidth = max(width - horizontalInset * 2, 1)
            let span = max(range.upperBound - range.lowerBound, 0.0001)
            let ratio = min(max((value - range.lowerBound) / span, 0), 1)
            let indicatorX = horizontalInset + CGFloat(ratio) * drawableWidth

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.26))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )

                let tickCount = max(8, min(50, Int(span / max(step * 5, 1)) + 1))
                ForEach(0..<tickCount, id: \.self) { index in
                    let tickX = horizontalInset + CGFloat(index) * (drawableWidth / CGFloat(max(tickCount - 1, 1)))
                    let isMajor = index.isMultiple(of: 5)
                    Rectangle()
                        .fill(Color.white.opacity(isMajor ? 0.55 : 0.28))
                        .frame(width: 1, height: isMajor ? height * 0.55 : height * 0.32)
                        .position(x: tickX, y: height / 2)
                }

                Rectangle()
                    .fill(Color.appAccent)
                    .frame(width: 2, height: height * 0.72)
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

                        let stepIndex = Int((clamped - range.lowerBound) / step)
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

