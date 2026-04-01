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

struct RootPresentationModifier: ViewModifier {
    let isAuditCaptureEnabled: Bool
    @ObservedObject var premiumStore: PremiumStore
    let dismissTrialReminderOptIn: () -> Void
    let confirmTrialReminderOptIn: () -> Void
    let dismissTrialNotificationPermissionOptIn: () -> Void
    let confirmTrialNotificationPermissionOptIn: () -> Void

    private var trialReminderPromptBinding: Binding<Bool> {
        if isAuditCaptureEnabled {
            return .constant(false)
        }
        return $premiumStore.showTrialReminderOptInPrompt
    }

    private var trialThankYouAlertBinding: Binding<Bool> {
        if isAuditCaptureEnabled {
            return .constant(false)
        }
        return $premiumStore.showTrialThankYouAlert
    }

    private var trialNotificationPermissionPromptBinding: Binding<Bool> {
        if isAuditCaptureEnabled {
            return .constant(false)
        }
        return $premiumStore.showTrialNotificationPermissionPrompt
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
            .sheet(isPresented: $premiumStore.isPaywallPresented) {
                PremiumPaywallView()
                    .environmentObject(premiumStore)
            }
            .onChange(of: premiumStore.isPaywallPresented) { _, isPresented in
                guard !isPresented else { return }
                premiumStore.handlePaywallDismissed()
            }
            .sheet(isPresented: $premiumStore.showPostPurchaseSetup) {
                PostPurchaseSetupView()
                    .presentationDetents([.fraction(0.72)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
            }
    }
}
