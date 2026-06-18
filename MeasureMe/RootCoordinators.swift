import SwiftUI

@MainActor
enum RootDeferredStartupCoordinator {
    static func run(
        hasCompletedOnboarding: Bool,
        premiumStore: PremiumStore,
        pendingPhotoSaveStore: PendingPhotoSaveStore
    ) async {
        AppRuntimeConfigurator.configureDeferredServicesIfNeeded()

        if hasCompletedOnboarding {
            try? await Task.sleep(for: .milliseconds(1200))
        }

        premiumStore.startIfNeeded()

        let pendingRestoreState = StartupInstrumentation.begin("PendingRestore")
        StartupInstrumentation.event("PendingRestoreStart")
        await pendingPhotoSaveStore.restoreAndResumeAsync()
        StartupInstrumentation.event("PendingRestoreEnd")
        StartupInstrumentation.end("PendingRestore", state: pendingRestoreState)
    }
}

struct RootContentLayer: View {
    let autoCheckPaywallPrompt: Bool
    let isShowingOnboarding: Bool
    let showsOnboardingUITestOverlay: Bool
    let showsOnboardingUITestStepMarker: Bool
    let showsTrialReminderDebugOverlay: Bool
    let isUITestMode: Bool
    let onboardingUITestBridge: OnboardingUITestBridge
    let postOnboardingUITestNext: () -> Void
    let postOnboardingUITestBack: () -> Void
    let postOnboardingUITestSkip: () -> Void
    let dismissTrialReminderOptIn: () -> Void
    let confirmTrialReminderOptIn: () -> Void
    let premiumStore: PremiumStore
    let metricsStore: ActiveMetricsStore
    let pendingPhotoSaveStore: PendingPhotoSaveStore

    var body: some View {
        ZStack {
            TabBarContainer(
                autoCheckPaywallPrompt: autoCheckPaywallPrompt,
                premiumStore: premiumStore
            )

            if isShowingOnboarding {
                OnboardingView()
                    .environmentObject(metricsStore)
                    .environmentObject(premiumStore)
                    .environmentObject(pendingPhotoSaveStore)
                    .transition(.opacity)
                    .zIndex(2)
            }

            if showsOnboardingUITestOverlay {
                OnboardingUITestOverlay(
                    bridge: onboardingUITestBridge,
                    onNext: postOnboardingUITestNext,
                    onBack: postOnboardingUITestBack,
                    onSkip: postOnboardingUITestSkip
                )
                .zIndex(3)
            }

            if showsOnboardingUITestStepMarker {
                OnboardingUITestControlHooks(
                    bridge: onboardingUITestBridge,
                    onNext: postOnboardingUITestNext,
                    onBack: postOnboardingUITestBack,
                    onSkip: postOnboardingUITestSkip
                )
                    .zIndex(3)
            }

            if showsTrialReminderDebugOverlay {
                TrialReminderPromptOverlay(
                    declineTitle: AppLocalization.string("premium.trial.reminder.prompt.decline"),
                    confirmTitle: AppLocalization.string("premium.trial.reminder.prompt.confirm"),
                    onDecline: dismissTrialReminderOptIn,
                    onConfirm: confirmTrialReminderOptIn
                )
            }

            if isUITestMode {
                RootReadyMarker()
            }
        }
    }
}

private struct OnboardingUITestControlHooks: View {
    @ObservedObject var bridge: OnboardingUITestBridge
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            testButton(label: "UITest Next", identifier: "onboarding.test.next", action: onNext)
            testButton(label: "UITest Back", identifier: "onboarding.test.back", action: onBack)
            testButton(label: "UITest Skip", identifier: "onboarding.test.skip", action: onSkip)

            Text(verbatim: "step:\(bridge.currentStepIndex)")
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("root.onboarding.test.step")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private func testButton(
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Color.clear
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

struct RootPresentationModifier: ViewModifier {
    let isAuditCaptureEnabled: Bool
    let premiumStore: PremiumStore
    let trialReminderOptInPrompt: Binding<Bool>
    let trialThankYouAlert: Binding<Bool>
    let trialNotificationPermissionPrompt: Binding<Bool>
    let isPaywallPresented: Binding<Bool>
    let showPostPurchaseSetup: Binding<Bool>
    let dismissTrialReminderOptIn: () -> Void
    let confirmTrialReminderOptIn: () -> Void
    let dismissTrialNotificationPermissionOptIn: () -> Void
    let confirmTrialNotificationPermissionOptIn: () -> Void

    private var trialReminderPromptBinding: Binding<Bool> {
        if isAuditCaptureEnabled {
            return .constant(false)
        }
        return trialReminderOptInPrompt
    }

    private var trialThankYouAlertBinding: Binding<Bool> {
        if isAuditCaptureEnabled {
            return .constant(false)
        }
        return trialThankYouAlert
    }

    private var trialNotificationPermissionPromptBinding: Binding<Bool> {
        if isAuditCaptureEnabled {
            return .constant(false)
        }
        return trialNotificationPermissionPrompt
    }

    func body(content: Content) -> some View {
        content
            .alert(
                AppLocalization.string("premium.trial.reminder.prompt.title"),
                isPresented: trialReminderPromptBinding
            ) {
                Button(AppLocalization.string("premium.trial.reminder.prompt.decline"), role: .cancel, action: dismissTrialReminderOptIn)
                    .accessibilityIdentifier("premium.trial.reminder.prompt.decline")
                Button(AppLocalization.string("premium.trial.reminder.prompt.confirm"), action: confirmTrialReminderOptIn)
                    .accessibilityIdentifier("premium.trial.reminder.prompt.confirm")
            } message: {
                Text(AppLocalization.string("premium.trial.reminder.prompt.message"))
            }
            .confirmationDialog(
                AppLocalization.string("premium.trial.notification_permission.prompt.title"),
                isPresented: trialNotificationPermissionPromptBinding,
                titleVisibility: .visible
            ) {
                Button(AppLocalization.string("Not now"), role: .cancel, action: dismissTrialNotificationPermissionOptIn)
                Button(AppLocalization.string("premium.trial.notification_permission.prompt.confirm"), action: confirmTrialNotificationPermissionOptIn)
            } message: {
                Text(AppLocalization.string("premium.trial.notification_permission.prompt.message"))
            }
            .alert(
                AppLocalization.string("premium.trial.thankyou.title"),
                isPresented: trialThankYouAlertBinding
            ) {
                Button(AppLocalization.string("OK"), role: .cancel) {}
            } message: {
                Text(AppLocalization.string("premium.trial.thankyou.message"))
            }
            .sheet(isPresented: isPaywallPresented) {
                PremiumPaywallView()
                    .environmentObject(premiumStore)
            }
            .onChange(of: isPaywallPresented.wrappedValue) { _, isPresented in
                guard !isPresented else { return }
                premiumStore.handlePaywallDismissed()
            }
            .sheet(isPresented: showPostPurchaseSetup) {
                PostPurchaseSetupView()
                    .presentationDetents([.fraction(0.72)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
            }
    }
}
