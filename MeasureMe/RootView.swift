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
        isOnboardingUITestMode && isShowingOnboarding
    }

    private var showsTrialReminderDebugOverlay: Bool {
        UITestArgument.isPresent(.showTrialReminderPrompt)
            || (isUITestMode && premiumStore.showTrialReminderOptInPrompt)
    }

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
        ZStack {
            TabBarContainer(autoCheckPaywallPrompt: autoCheckPaywallPrompt)
                .environmentObject(premiumStore)
                .environmentObject(metricsStore)
                .environmentObject(pendingPhotoSaveStore)
                .sheet(isPresented: $premiumStore.isPaywallPresented) {
                    PremiumPaywallView()
                        .environmentObject(premiumStore)
                }

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
        .accessibilityIdentifier("app.root")
        .onAppear(perform: handleAppear)
        .alert(
            AppLocalization.string("premium.trial.reminder.prompt.title"),
            isPresented: trialReminderPromptBinding,
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
        .sheet(isPresented: $premiumStore.showPostPurchaseSetup) {
            PostPurchaseSetupView()
                .presentationDetents([.fraction(0.72)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private func handleAppear() {
        configurePendingStoreIfNeeded()
        scheduleDeferredStartupWorkIfNeeded()

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
}

private struct OnboardingUITestOverlay: View {
    @ObservedObject var bridge: OnboardingUITestBridge
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OnboardingUITestButton(
                title: "UITest Next",
                identifier: "onboarding.next",
                style: .borderedProminent,
                action: onNext
            )

            OnboardingUITestButton(
                title: "UITest Back",
                identifier: "onboarding.back",
                style: .bordered,
                action: onBack
            )

            OnboardingUITestButton(
                title: "UITest Skip",
                identifier: "onboarding.skip",
                style: .bordered,
                action: onSkip
            )

            Text("Privacy note")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .frame(minWidth: 88, minHeight: 44, alignment: .leading)
                .accessibilityElement()
                .accessibilityLabel("Privacy note")
                .accessibilityIdentifier("onboarding.privacy.note")

            Text(verbatim: "step:\(bridge.currentStepIndex)")
                .accessibilityIdentifier("root.onboarding.test.step")
            Text(verbatim: "icloudViewed:\(bridge.iCloudViewed)")
                .accessibilityIdentifier("root.onboarding.test.icloudViewed")
            Text(verbatim: "icloudSkipped:\(bridge.iCloudSkipped)")
                .accessibilityIdentifier("root.onboarding.test.icloudSkipped")
            Text(verbatim: "icloudEnabled:\(bridge.iCloudEnabled)")
                .accessibilityIdentifier("root.onboarding.test.icloudEnabled")
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(8)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 12)
        .padding(.leading, 8)
    }
}

private struct OnboardingUITestButton: View {
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

private struct OnboardingUITestButtonStyleModifier: ViewModifier {
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

private struct TrialReminderPromptOverlay: View {
    let declineTitle: String
    let confirmTitle: String
    let onDecline: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Trial prompt")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("premium.trial.reminder.prompt.visible")

            Button(declineTitle, role: .cancel, action: onDecline)
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.2))
                .foregroundStyle(.white)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("premium.trial.reminder.prompt.decline")

            Button(confirmTitle, action: onConfirm)
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.2))
                .foregroundStyle(.white)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("premium.trial.reminder.prompt.confirm")
        }
        .padding(8)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 12)
        .padding(.trailing, 8)
    }
}

private struct RootReadyMarker: View {
    var body: some View {
        Text("ready")
            .font(.system(size: 1))
            .foregroundStyle(.clear)
            .frame(width: 1, height: 1)
            .clipped()
            .accessibilityIdentifier("app.root.ready")
    }
}
