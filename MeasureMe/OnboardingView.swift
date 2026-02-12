import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userAge") private var userAge: Int = 0
    @AppStorage("userGender") private var userGender: String = "notSpecified"
    @AppStorage("manualHeight") private var manualHeight: Double = 0.0
    @AppStorage("isSyncEnabled") private var isSyncEnabled: Bool = false
    @AppStorage("unitsSystem") private var unitsSystem: String = "metric"
    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var metricsStore: ActiveMetricsStore
    @EnvironmentObject private var premiumStore: PremiumStore

    @State private var step: Step = .intro
    @State private var nameInput: String = ""
    @State private var ageInput: String = ""
    @State private var heightInput: String = ""
    @State private var feetInput: String = ""
    @State private var inchesInput: String = ""

    @State private var healthKitToggle: Bool = false
    @State private var notificationsToggle: Bool = false
    @State private var isRequestingHealthKit: Bool = false
    @State private var isImportingHealthDataInBackground: Bool = false
    @State private var isRequestingNotifications: Bool = false
    @State private var healthKitStatusText: String?
    @State private var notificationsStatusText: String?
    @State private var animateGlow: Bool = false
    @State private var animateCelebration: Bool = false
    @State private var animateHero: Bool = false
    @State private var showQuickAddSheet: Bool = false
    @State private var showAddPhotoSheet: Bool = false

    private var shouldAnimate: Bool {
        animationsEnabled && !reduceMotion
    }

    private enum Step: Int, CaseIterable {
        case intro
        case name
        case age
        case gender
        case units
        case height
        case healthKit
        case notifications
        case measurements
        case quickAdd
        case chart
        case photo
        case settings
        case premium

        var title: String {
            switch self {
            case .intro: return AppLocalization.systemString("MeasureMe")
            case .measurements: return AppLocalization.systemString("Measurements Matter")
            case .name: return AppLocalization.systemString("Welcome")
            case .age: return AppLocalization.systemString("Your Age")
            case .gender: return AppLocalization.systemString("Your Gender")
            case .units: return AppLocalization.systemString("Your Units")
            case .height: return AppLocalization.systemString("Your Height")
            case .healthKit: return AppLocalization.systemString("Health Sync")
            case .notifications: return AppLocalization.systemString("Notifications")
            case .quickAdd: return AppLocalization.systemString("Add Your First Data")
            case .chart: return AppLocalization.systemString("See the Trend")
            case .photo: return AppLocalization.systemString("Photo Progress")
            case .settings: return AppLocalization.systemString("Your Settings")
            case .premium: return AppLocalization.systemString("Premium Edition")
            }
        }

        var subtitle: String {
            switch self {
            case .intro: return AppLocalization.systemString("Body tracking that feels grounded and motivating.")
            case .measurements: return AppLocalization.systemString("Body changes show up in measurements first.")
            case .name: return AppLocalization.systemString("Let’s personalize your experience.")
            case .age: return AppLocalization.systemString("A quick detail for accurate metrics.")
            case .gender: return AppLocalization.systemString("Used only for gender-specific formulas.")
            case .units: return AppLocalization.systemString("Pick the units that feel natural.")
            case .height: return AppLocalization.systemString("Used for core health calculations.")
            case .healthKit: return AppLocalization.systemString("Keep measurements in sync with Apple Health.")
            case .notifications: return AppLocalization.systemString("Get gentle reminders to stay consistent.")
            case .quickAdd: return AppLocalization.systemString("Log a measurement in seconds.")
            case .chart: return AppLocalization.systemString("Trends matter more than daily noise.")
            case .photo: return AppLocalization.systemString("See changes that numbers miss.")
            case .settings: return AppLocalization.systemString("Tune your tracking anytime.")
            case .premium: return AppLocalization.systemString("Optional support, stronger insights.")
            }
        }

        var explanation: String {
            switch self {
            case .intro:
                return AppLocalization.systemString("You can skip any step and change everything later in Settings.")
            case .measurements:
                return AppLocalization.systemString("Waist and body composition often tell a clearer story than weight alone.")
            case .name:
                return AppLocalization.systemString("Why we ask: we use your name to personalize insights and goals.")
            case .age:
                return AppLocalization.systemString("Why we ask: age adjusts BMI and body composition ranges for accuracy.")
            case .gender:
                return AppLocalization.systemString("Why we ask: some formulas (like RFM and body fat ranges) differ by gender.")
            case .units:
                return AppLocalization.systemString("Why we ask: units keep measurements readable and consistent across the app.")
            case .height:
                return AppLocalization.systemString("Why we ask: height powers metrics like WHtR and BMI.")
            case .healthKit:
                return AppLocalization.systemString("Why we ask: HealthKit sync keeps measurements up to date automatically.")
            case .notifications:
                return AppLocalization.systemString("Why we ask: reminders help you build a consistent tracking habit.")
            case .quickAdd:
                return AppLocalization.systemString("Why we ask: consistent entries turn into reliable trends.")
            case .chart:
                return AppLocalization.systemString("Why we ask: a single data point never tells the full story.")
            case .photo:
                return AppLocalization.systemString("Why we ask: photos capture composition changes that scales miss.")
            case .settings:
                return AppLocalization.systemString("Why we ask: you’re always in control of what you track.")
            case .premium:
                return AppLocalization.systemString("Premium is optional, but it unlocks deeper insights and keeps MeasureMe growing.")
            }
        }
    }

    var body: some View {
        ZStack {
            AppBackground()
            animatedBackdrop

            VStack(spacing: 0) {
                header

                VStack(alignment: .leading, spacing: 20) {
                    Text(step.title)
                        .font(AppTypography.displayMedium)
                        .foregroundStyle(Color.appWhite)

                    Text(step.subtitle)
                        .font(AppTypography.body)
                        .foregroundStyle(Color.appGray)

                    ZStack {
                        stepContent
                            .id(step)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }

                    Text(step.explanation)
                        .font(AppTypography.caption)
                        .foregroundStyle(Color.appGray)
                        .padding(.top, 6)

                    if let statusText = statusText {
                        Text(statusText)
                            .font(AppTypography.caption)
                            .foregroundStyle(Color.appAccent)
                    }

                    privacyNote
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

                Spacer(minLength: 0)

                footer
            }
            .safeAreaPadding(.top, 24)
        }
        .onAppear {
            hydrate()
            animateGlow = true
            animateHero = true
        }
        .sheet(isPresented: $showQuickAddSheet) {
            QuickAddContainerView {
                showQuickAddSheet = false
            }
            .environmentObject(metricsStore)
        }
        .sheet(isPresented: $showAddPhotoSheet) {
            AddPhotoView(onSaved: {})
                .environmentObject(metricsStore)
        }
        .animation(shouldAnimate ? .easeInOut(duration: 0.25) : nil, value: step)
        .preferredColorScheme(.dark)
    }

    private var animatedBackdrop: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.appAccent.opacity(0.35), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 220
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: animateGlow ? 140 : 80, y: animateGlow ? -220 : -160)
                .blur(radius: 8)
                .animation(shouldAnimate ? .easeInOut(duration: 6).repeatForever(autoreverses: true) : nil, value: animateGlow)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.12), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 180
                    )
                )
                .frame(width: 260, height: 260)
                .offset(x: animateGlow ? -130 : -80, y: animateGlow ? 140 : 200)
                .blur(radius: 10)
                .animation(shouldAnimate ? .easeInOut(duration: 7).repeatForever(autoreverses: true) : nil, value: animateGlow)
        }
        .allowsHitTesting(false)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                .tint(Color.appAccent)

            HStack {
                Text(AppLocalization.systemString("Step %d of %d", step.rawValue + 1, Step.allCases.count))
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(Color.appGray)

                Spacer()

                Button(AppLocalization.systemString("Skip")) {
                    skipStep()
                }
                .font(AppTypography.microEmphasis)
                .foregroundStyle(Color.appGray)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .intro:
            VStack(alignment: .leading, spacing: 16) {
                Text(AppLocalization.systemString("\"What is measured is managed\"\n- Peter Drucker"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(Color.appGray)

                Text(AppLocalization.systemString("Built for real-life change"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(Color.appWhite)

                OnboardingHeroView(animate: animateHero)

                VStack(spacing: 12) {
                    OnboardingFeatureCard(
                        icon: "chart.line.uptrend.xyaxis",
                        title: AppLocalization.systemString("See trends that matter"),
                        detail: AppLocalization.systemString("Track weight, waist, and body composition with clear signals - not noise.")
                    )

                    OnboardingFeatureCard(
                        icon: "figure.walk",
                        title: AppLocalization.systemString("Stay consistent"),
                        detail: AppLocalization.systemString("Gentle check-ins help habits stick for diet, training, or health goals.")
                    )

                    OnboardingFeatureCard(
                        icon: "sparkles",
                        title: AppLocalization.systemString("Understand your body"),
                        detail: AppLocalization.systemString("Smart metrics like WHtR and BMI give context to the numbers.")
                    )
                }

                Text(AppLocalization.systemString("Set a calm baseline, then focus on small, repeatable wins."))
                    .font(AppTypography.caption)
                    .foregroundStyle(Color.appGray)
            }
        case .measurements:
            VStack(alignment: .leading, spacing: 16) {
                Text(AppLocalization.systemString("Measurements beat the scale"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(Color.appWhite)

                OnboardingFeatureCard(
                    icon: "ruler.fill",
                    title: AppLocalization.systemString("Waist + hips show real change"),
                    detail: AppLocalization.systemString("You can build muscle and lose fat at the same time, so weight alone can mislead.")
                )

                OnboardingFeatureCard(
                    icon: "figure.strengthtraining.traditional",
                    title: AppLocalization.systemString("Composition beats weight"),
                    detail: AppLocalization.systemString("Track body fat and lean mass to see your true progress.")
                )
            }
        case .name:
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalization.systemString("What should we call you?"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(Color.appWhite)

                TextField(AppLocalization.systemString("Your name"), text: $nameInput)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            }
        case .age:
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalization.systemString("How old are you?"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(Color.appWhite)

                TextField(AppLocalization.systemString("Age in years"), text: $ageInput)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
            }
        case .gender:
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalization.systemString("Select your gender"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(Color.appWhite)

                Picker(AppLocalization.systemString("Gender"), selection: $userGender) {
                    Text(AppLocalization.systemString("Not specified")).tag("notSpecified")
                    Text(AppLocalization.systemString("Male")).tag("male")
                    Text(AppLocalization.systemString("Female")).tag("female")
                }
                .pickerStyle(.segmented)
            }
        case .units:
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalization.systemString("Choose your units"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(Color.appWhite)

                Picker(AppLocalization.systemString("Units"), selection: $unitsSystem) {
                    Text(AppLocalization.systemString("Metric")).tag("metric")
                    Text(AppLocalization.systemString("Imperial")).tag("imperial")
                }
                .pickerStyle(.segmented)
            }
        case .height:
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalization.systemString("Enter your height"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(Color.appWhite)

                if unitsSystem == "imperial" {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(AppLocalization.systemString("Feet"))
                                .font(AppTypography.caption)
                                .foregroundStyle(Color.appGray)
                            TextField("0", text: $feetInput)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(AppLocalization.systemString("Inches"))
                                .font(AppTypography.caption)
                                .foregroundStyle(Color.appGray)
                            TextField("0", text: $inchesInput)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLocalization.systemString("Centimeters"))
                            .font(AppTypography.caption)
                            .foregroundStyle(Color.appGray)
                        TextField("0.0", text: $heightInput)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        case .healthKit:
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalization.systemString("Sync with Health"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(Color.appWhite)

                Toggle(isOn: $healthKitToggle) {
                    Text(healthKitToggle ? AppLocalization.systemString("Enabled") : AppLocalization.systemString("Not now"))
                        .foregroundStyle(Color.appWhite)
                }
                .tint(Color.appAccent)
                .disabled(isRequestingHealthKit)
                .onChange(of: healthKitToggle) { _, newValue in
                    handleHealthKitToggle(newValue)
                }

                if isImportingHealthDataInBackground {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.appAccent)
                        Text(AppLocalization.systemString("Importing Health data in background. You can continue."))
                            .font(AppTypography.caption)
                            .foregroundStyle(Color.appGray)
                    }
                }
            }
        case .notifications:
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalization.systemString("Allow notifications"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(Color.appWhite)

                Toggle(isOn: $notificationsToggle) {
                    Text(notificationsToggle ? AppLocalization.systemString("Enabled") : AppLocalization.systemString("Not now"))
                        .foregroundStyle(Color.appWhite)
                }
                .tint(Color.appAccent)
                .disabled(isRequestingNotifications)
                .onChange(of: notificationsToggle) { _, newValue in
                    handleNotificationsToggle(newValue)
                }

                if animateCelebration {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.appAccent)
                        Text(AppLocalization.systemString("You’re all set."))
                            .font(AppTypography.caption)
                            .foregroundStyle(Color.appGray)
                    }
                    .transition(.opacity.combined(with: .scale))
                }
            }
        case .quickAdd:
            VStack(alignment: .leading, spacing: 16) {
                Text(AppLocalization.systemString("Add a quick measurement"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(Color.appWhite)

                OnboardingFeatureCard(
                    icon: "plus.circle.fill",
                    title: AppLocalization.systemString("Log in seconds"),
                    detail: AppLocalization.systemString("Quick Add lets you update multiple metrics without extra taps.")
                )

                OnboardingEmptyStateCard(
                    icon: "chart.bar.doc.horizontal",
                    title: AppLocalization.systemString("No measurements yet"),
                    detail: AppLocalization.systemString("Add your first measurement to unlock trends and goal progress.")
                )

                Button {
                    showQuickAddSheet = true
                } label: {
                    Text(AppLocalization.systemString("Add your first measurement"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.appAccent)
            }
        case .chart:
            VStack(alignment: .leading, spacing: 16) {
                Text(AppLocalization.systemString("Charts show momentum"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(Color.appWhite)

                OnboardingFeatureCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: AppLocalization.systemString("Focus on trends"),
                    detail: AppLocalization.systemString("We highlight 30-day changes so you can see what’s working.")
                )

                OnboardingEmptyStateCard(
                    icon: "waveform.path.ecg",
                    title: AppLocalization.systemString("No measurements yet."),
                    detail: AppLocalization.systemString("Add your first measurement to unlock charts and progress.")
                )
            }
        case .photo:
            VStack(alignment: .leading, spacing: 16) {
                Text(AppLocalization.systemString("Capture the visual wins"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(Color.appWhite)

                Text(AppLocalization.systemString("You’ll soon see changes with MeasureMe — capture them in photos."))
                    .font(AppTypography.caption)
                    .foregroundStyle(Color.appGray)

                OnboardingEmptyStateCard(
                    icon: "photo.on.rectangle.angled",
                    title: AppLocalization.systemString("No photos yet. Capture progress photos to see changes beyond the scale."),
                    detail: AppLocalization.systemString("Photos make body-composition change easier to notice week to week.")
                )

                Button {
                    showAddPhotoSheet = true
                } label: {
                    Text(AppLocalization.systemString("Add your first photo"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.appAccent)
            }
        case .settings:
            VStack(alignment: .leading, spacing: 16) {
                Text(AppLocalization.systemString("You’re in control"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(Color.appWhite)

                OnboardingFeatureCard(
                    icon: "slider.horizontal.3",
                    title: AppLocalization.systemString("Choose your metrics"),
                    detail: AppLocalization.systemString("Pick the measurements that matter most to you.")
                )

                OnboardingFeatureCard(
                    icon: "bell.fill",
                    title: AppLocalization.systemString("Set reminders"),
                    detail: AppLocalization.systemString("Stay consistent with gentle nudges.")
                )
            }
        case .premium:
            VStack(alignment: .leading, spacing: 16) {
                Text(AppLocalization.systemString("Premium stays optional"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(Color.appWhite)

                OnboardingFeatureCard(
                    icon: "sparkles",
                    title: AppLocalization.systemString("Deeper insights"),
                    detail: AppLocalization.systemString("Apple Intelligence insights, Health Indicators, and photo comparison.")
                )

                Text(AppLocalization.systemString("Premium helps you stay consistent, hit your goals, and supports a small business from Poland."))
                    .font(AppTypography.caption)
                    .foregroundStyle(Color.appGray)

                Text(AppLocalization.systemString("Core tracking stays free. Premium unlocks deeper analysis only when you need it."))
                    .font(AppTypography.caption)
                    .foregroundStyle(Color.appGray)

                Button {
                    premiumStore.presentPaywall(reason: .onboarding)
                } label: {
                    Text(AppLocalization.systemString("View Premium options"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.appAccent)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                goBack()
            } label: {
                Text(AppLocalization.systemString("Back"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Color.appGray.opacity(0.3))
            .disabled(step == .intro)

            Button {
                goForward()
            } label: {
                Text(step == .premium ? AppLocalization.systemString("Finish") : AppLocalization.systemString("Continue"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appAccent)
            .disabled(!canContinue)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
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

    private var canContinue: Bool {
        switch step {
        case .name:
            return !nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .age:
            return isValidAge
        case .height:
            return isValidHeight
        default:
            return true
        }
    }

    private var isValidAge: Bool {
        guard let age = Int(ageInput) else { return false }
        return age >= 5 && age <= 120
    }

    private var isValidHeight: Bool {
        if unitsSystem == "imperial" {
            guard let feet = Int(feetInput), let inches = Int(inchesInput) else { return false }
            return feet >= 0 && inches >= 0 && inches < 12 && (feet > 0 || inches > 0)
        }

        guard let value = Double(heightInput) else { return false }
        return value > 0
    }

    private var statusText: String? {
        switch step {
        case .healthKit:
            return healthKitStatusText
        case .notifications:
            return notificationsStatusText
        default:
            return nil
        }
    }

    private func goBack() {
        guard step.rawValue > 0 else { return }
        if let previous = Step(rawValue: step.rawValue - 1) {
            transition(to: previous)
        }
    }

    private func goForward() {
        switch step {
        case .name:
            userName = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        case .age:
            if let age = Int(ageInput) {
                userAge = age
            }
        case .height:
            saveHeight()
        case .premium:
            if shouldAnimate {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    animateCelebration = true
                }
            } else {
                animateCelebration = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                hasCompletedOnboarding = true
            }
        default:
            break
        }

        if let next = Step(rawValue: step.rawValue + 1) {
            transition(to: next)
        }
    }

    private func skipStep() {
        if step == .premium {
            hasCompletedOnboarding = true
            return
        }

        if let next = Step(rawValue: step.rawValue + 1) {
            transition(to: next)
        }
    }

    private func transition(to next: Step) {
        if shouldAnimate {
            withAnimation(.easeInOut(duration: 0.25)) {
                step = next
            }
        } else {
            step = next
        }
    }

    private func hydrate() {
        if !userName.isEmpty {
            nameInput = userName
        }

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

        healthKitToggle = isSyncEnabled
        notificationsToggle = NotificationManager.shared.notificationsEnabled
    }

    private func saveHeight() {
        if unitsSystem == "imperial" {
            let feet = Int(feetInput) ?? 0
            let inches = Int(inchesInput) ?? 0
            let totalInches = Double(feet * 12 + inches)
            manualHeight = MetricKind.height.valueToMetric(fromDisplay: totalInches, unitsSystem: unitsSystem)
        } else if let value = Double(heightInput) {
            manualHeight = MetricKind.height.valueToMetric(fromDisplay: value, unitsSystem: unitsSystem)
        }
    }

    private func handleHealthKitToggle(_ newValue: Bool) {
        if !newValue {
            isSyncEnabled = false
            isImportingHealthDataInBackground = false
            healthKitStatusText = nil
            return
        }

        isRequestingHealthKit = true
        healthKitStatusText = AppLocalization.systemString("Requesting Health access...")

        Task { @MainActor in
            do {
                try await HealthKitManager.shared.requestAuthorization()
                isSyncEnabled = true
                healthKitStatusText = AppLocalization.systemString("Health sync enabled.")
                isRequestingHealthKit = false
                isImportingHealthDataInBackground = true
                healthKitStatusText = AppLocalization.systemString("Health sync enabled. Importing data in background.")
                importFromHealthKitIfPossibleInBackground()
            } catch {
                isSyncEnabled = false
                healthKitToggle = false
                healthKitStatusText = AppLocalization.systemString("Health access denied. You can enable it later in Settings.")
                isRequestingHealthKit = false
                isImportingHealthDataInBackground = false
            }
        }
    }

    private func handleNotificationsToggle(_ newValue: Bool) {
        if !newValue {
            NotificationManager.shared.notificationsEnabled = false
            notificationsStatusText = nil
            return
        }

        isRequestingNotifications = true
        notificationsStatusText = AppLocalization.systemString("Requesting notification permission...")

        Task { @MainActor in
            let granted = await NotificationManager.shared.requestAuthorization()
            NotificationManager.shared.notificationsEnabled = granted
            if granted {
                notificationsStatusText = AppLocalization.systemString("Notifications enabled.")
            } else {
                notificationsToggle = false
                notificationsStatusText = AppLocalization.systemString("Notifications denied. You can enable them later in Settings.")
            }
            isRequestingNotifications = false
        }
    }

    private func importFromHealthKitIfPossibleInBackground() {
        Task {
            do {
                var importedAny = false
                var importedAge: Int?
                var importedHeight: Double?

                if userAge == 0, let birthDate = try HealthKitManager.shared.fetchDateOfBirth() {
                    importedAge = HealthKitManager.calculateAge(from: birthDate)
                    importedAny = importedAge != nil || importedAny
                }

                if manualHeight == 0, let height = try await HealthKitManager.shared.fetchLatestHeightInCentimeters() {
                    importedHeight = height.value
                    importedAny = true
                }

                await MainActor.run {
                    if let importedAge {
                        userAge = importedAge
                        ageInput = "\(importedAge)"
                    }

                    if let importedHeight {
                        manualHeight = importedHeight
                        let display = MetricKind.height.valueForDisplay(fromMetric: importedHeight, unitsSystem: unitsSystem)
                        if unitsSystem == "imperial" {
                            let totalInches = Int(display.rounded())
                            feetInput = "\(totalInches / 12)"
                            inchesInput = "\(totalInches % 12)"
                        } else {
                            heightInput = String(format: "%.1f", display)
                        }
                    }

                    isImportingHealthDataInBackground = false
                    if importedAny {
                        healthKitStatusText = AppLocalization.systemString("Health data imported in background.")
                    }
                }
            } catch {
                await MainActor.run {
                    isImportingHealthDataInBackground = false
                    healthKitStatusText = AppLocalization.systemString("Health sync enabled, but we couldn’t import data.")
                }
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(ActiveMetricsStore())
        .environmentObject(PremiumStore())
}
