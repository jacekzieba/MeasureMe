import SwiftUI
import SwiftData

@MainActor
struct RootView: View {
    @StateObject private var premiumStore: PremiumStore
    @StateObject private var metricsStore: ActiveMetricsStore
    @StateObject private var pendingPhotoSaveStore = PendingPhotoSaveStore()
    @StateObject private var onboardingUITestBridge = OnboardingUITestBridge.shared
    @Environment(\.modelContext) private var modelContext
    @AppSetting(\.onboarding.hasCompletedOnboarding) private var hasCompletedOnboarding: Bool = false
    private let autoCheckPaywallPrompt: Bool
    private let runDeferredStartupWork: Bool
    private let isAuditCaptureEnabled = AuditConfig.current.isEnabled
    private let isUITestMode = UITestArgument.isPresent(.mode)
    private let isOnboardingUITestMode = UITestArgument.isPresent(.onboardingMode)
    @State private var didConfigurePendingStore = false
    @State private var didScheduleDeferredStartupWork = false

    private var isShowingOnboarding: Bool {
        !hasCompletedOnboarding
    }

    private var showsOnboardingUITestOverlay: Bool {
        isOnboardingUITestMode && isShowingOnboarding && !isAuditCaptureEnabled
    }

    private var showsTrialReminderDebugOverlay: Bool {
        UITestArgument.isPresent(.showTrialReminderPrompt)
            || (isUITestMode && premiumStore.showTrialReminderOptInPrompt)
    }

    init(
        premiumStore: PremiumStore? = nil,
        metricsStore: ActiveMetricsStore? = nil,
        autoCheckPaywallPrompt: Bool = true,
        runDeferredStartupWork: Bool = true
    ) {
        _premiumStore = StateObject(wrappedValue: premiumStore ?? PremiumStore(startListener: false))
        _metricsStore = StateObject(wrappedValue: metricsStore ?? ActiveMetricsStore())
        self.autoCheckPaywallPrompt = autoCheckPaywallPrompt
        self.runDeferredStartupWork = runDeferredStartupWork
    }

    var body: some View {
        RootContentLayer(
            autoCheckPaywallPrompt: autoCheckPaywallPrompt,
            isShowingOnboarding: isShowingOnboarding,
            showsOnboardingUITestOverlay: showsOnboardingUITestOverlay,
            showsOnboardingUITestStepMarker: isOnboardingUITestMode && isShowingOnboarding && !showsOnboardingUITestOverlay,
            showsTrialReminderDebugOverlay: showsTrialReminderDebugOverlay,
            isUITestMode: isUITestMode,
            onboardingUITestBridge: onboardingUITestBridge,
            postOnboardingUITestNext: postOnboardingUITestNext,
            postOnboardingUITestBack: postOnboardingUITestBack,
            postOnboardingUITestSkip: postOnboardingUITestSkip,
            dismissTrialReminderOptIn: dismissTrialReminderOptIn,
            confirmTrialReminderOptIn: confirmTrialReminderOptIn,
            premiumStore: premiumStore,
            metricsStore: metricsStore,
            pendingPhotoSaveStore: pendingPhotoSaveStore
        )
        .onAppear(perform: handleAppear)
        .environmentObject(premiumStore)
        .environmentObject(metricsStore)
        .environmentObject(pendingPhotoSaveStore)
        .measureBuddyToast()
        .modifier(
            RootPresentationModifier(
                isAuditCaptureEnabled: isAuditCaptureEnabled,
                premiumStore: premiumStore,
                trialReminderOptInPrompt: $premiumStore.showTrialReminderOptInPrompt,
                trialThankYouAlert: $premiumStore.showTrialThankYouAlert,
                trialNotificationPermissionPrompt: $premiumStore.showTrialNotificationPermissionPrompt,
                isPaywallPresented: $premiumStore.isPaywallPresented,
                showPostPurchaseSetup: $premiumStore.showPostPurchaseSetup,
                dismissTrialReminderOptIn: dismissTrialReminderOptIn,
                confirmTrialReminderOptIn: confirmTrialReminderOptIn,
                dismissTrialNotificationPermissionOptIn: dismissTrialNotificationPermissionOptIn,
                confirmTrialNotificationPermissionOptIn: confirmTrialNotificationPermissionOptIn
            )
        )
    }

    private func handleAppear() {
        configurePendingStoreIfNeeded()
        scheduleDeferredStartupWorkIfNeeded()
        PremiumPromptDispatcher.shared.configure(with: premiumStore)

        if UITestArgument.isPresent(.showTrialReminderPrompt) {
            premiumStore.showTrialReminderOptInPrompt = true
        }
    }

    private func postOnboardingUITestNext() {
        postOnboardingUITestNotification(.onboardingUITestNext)
    }

    private func postOnboardingUITestBack() {
        postOnboardingUITestNotification(.onboardingUITestBack)
    }

    private func postOnboardingUITestSkip() {
        postOnboardingUITestNotification(.onboardingUITestSkip)
    }

    private func postOnboardingUITestNotification(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }

    private func dismissTrialReminderOptIn() {
        premiumStore.dismissTrialReminderOptIn()
    }

    private func confirmTrialReminderOptIn() {
        Task { await premiumStore.confirmTrialReminderOptIn() }
    }

    private func dismissTrialNotificationPermissionOptIn() {
        premiumStore.dismissTrialNotificationPermissionOptIn()
    }

    private func confirmTrialNotificationPermissionOptIn() {
        Task { await premiumStore.confirmTrialNotificationPermissionOptIn() }
    }

    private func configurePendingStoreIfNeeded() {
        guard !didConfigurePendingStore else { return }
        didConfigurePendingStore = true
        pendingPhotoSaveStore.configure(container: modelContext.container)
        StartupInstrumentation.event("RootViewConfigured")
    }

    private func scheduleDeferredStartupWorkIfNeeded() {
        guard runDeferredStartupWork else { return }
        guard !didScheduleDeferredStartupWork else { return }
        didScheduleDeferredStartupWork = true

        Task { @MainActor in
            await RootDeferredStartupCoordinator.run(
                hasCompletedOnboarding: hasCompletedOnboarding,
                premiumStore: premiumStore,
                pendingPhotoSaveStore: pendingPhotoSaveStore
            )
        }
    }
}

struct OnboardingUITestOverlay: View {
    @ObservedObject var bridge: OnboardingUITestBridge
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OnboardingUITestButton(
                title: "UITest Next",
                identifier: "onboarding.test.next",
                style: .borderedProminent,
                action: onNext
            )

            OnboardingUITestButton(
                title: "UITest Back",
                identifier: "onboarding.test.back",
                style: .bordered,
                action: onBack
            )

            OnboardingUITestButton(
                title: "UITest Skip",
                identifier: "onboarding.test.skip",
                style: .bordered,
                action: onSkip
            )

            Color.clear
                .frame(minWidth: 88, minHeight: 44, alignment: .leading)
                .accessibilityHidden(true)
                .accessibilityIdentifier("onboarding.privacy.note")

            Text(verbatim: "step:\(bridge.currentStepIndex)")
                .accessibilityIdentifier("root.onboarding.test.step")
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(AppSpacing.xs)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 12)
        .padding(.leading, 8)
    }
}

struct OnboardingUITestButton: View {
    enum Style {
        case bordered
        case borderedProminent
    }

    let title: String
    let identifier: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(minWidth: 88, minHeight: 44, alignment: .leading)
        }
        .accessibilityIdentifier(identifier)
        .modifier(OnboardingUITestButtonStyleModifier(style: style))
        .contentShape(Rectangle())
    }
}

struct OnboardingUITestButtonStyleModifier: ViewModifier {
    let style: OnboardingUITestButton.Style

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .bordered:
            content.buttonStyle(.bordered)
        case .borderedProminent:
            content.buttonStyle(.borderedProminent)
        }
    }
}

struct TrialReminderPromptOverlay: View {
    let declineTitle: String
    let confirmTitle: String
    let onDecline: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Color.clear
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHidden(true)
                .accessibilityIdentifier("premium.trial.reminder.prompt.visible")

            Button(declineTitle, role: .cancel, action: onDecline)
                .buttonStyle(AppSecondaryButtonStyle(cornerRadius: AppRadius.sm))
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("premium.trial.reminder.prompt.decline")

            Button(confirmTitle, action: onConfirm)
                .buttonStyle(AppCTAButtonStyle(size: .compact, cornerRadius: AppRadius.sm))
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("premium.trial.reminder.prompt.confirm")
        }
        .padding(AppSpacing.xs)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 12)
        .padding(.trailing, 8)
    }
}

struct RootReadyMarker: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .clipped()
            .accessibilityHidden(true)
            .accessibilityIdentifier("app.root.ready")
    }
}
