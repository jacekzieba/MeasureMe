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

            if !hasCompletedOnboarding {
                OnboardingView()
                    .environmentObject(metricsStore)
                    .environmentObject(premiumStore)
                    .environmentObject(pendingPhotoSaveStore)
                    .transition(.opacity)
                    .zIndex(2)
            }

            if isOnboardingUITestMode, !hasCompletedOnboarding {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        NotificationCenter.default.post(name: .onboardingUITestNext, object: nil)
                    } label: {
                        Text("UITest Next")
                            .frame(minWidth: 88, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("onboarding.next")
                    .buttonStyle(.borderedProminent)
                    .contentShape(Rectangle())

                    Button {
                        NotificationCenter.default.post(name: .onboardingUITestBack, object: nil)
                    } label: {
                        Text("UITest Back")
                            .frame(minWidth: 88, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("onboarding.back")
                    .buttonStyle(.bordered)
                    .contentShape(Rectangle())

                    Button {
                        NotificationCenter.default.post(name: .onboardingUITestSkip, object: nil)
                    } label: {
                        Text("UITest Skip")
                            .frame(minWidth: 88, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("onboarding.skip")
                    .buttonStyle(.bordered)
                    .contentShape(Rectangle())

                    Text("Privacy note")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(minWidth: 88, minHeight: 44, alignment: .leading)
                        .accessibilityElement()
                        .accessibilityLabel("Privacy note")
                        .accessibilityIdentifier("onboarding.privacy.note")

                    Text(verbatim: "step:\(onboardingUITestBridge.currentStepIndex)")
                        .accessibilityIdentifier("root.onboarding.test.step")
                    Text(verbatim: "icloudViewed:\(onboardingUITestBridge.iCloudViewed)")
                        .accessibilityIdentifier("root.onboarding.test.icloudViewed")
                    Text(verbatim: "icloudSkipped:\(onboardingUITestBridge.iCloudSkipped)")
                        .accessibilityIdentifier("root.onboarding.test.icloudSkipped")
                    Text(verbatim: "icloudEnabled:\(onboardingUITestBridge.iCloudEnabled)")
                        .accessibilityIdentifier("root.onboarding.test.icloudEnabled")
                }
                .font(.system(size: 10, weight: .semibold))
                .padding(8)
                .background(Color.black.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 12)
                .padding(.leading, 8)
                .zIndex(3)
            }

            if UITestArgument.isPresent(.showTrialReminderPrompt)
                || (UITestArgument.isPresent(.mode)
                    && premiumStore.showTrialReminderOptInPrompt) {
                HStack(spacing: 8) {
                    Text("Trial prompt")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("premium.trial.reminder.prompt.visible")

                    Button(AppLocalization.string("premium.trial.reminder.prompt.decline"), role: .cancel) {
                        premiumStore.dismissTrialReminderOptIn()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.2))
                    .foregroundStyle(.white)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("premium.trial.reminder.prompt.decline")

                    Button(AppLocalization.string("premium.trial.reminder.prompt.confirm")) {
                        Task { await premiumStore.confirmTrialReminderOptIn() }
                    }
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

            if isUITestMode {
                Text("ready")
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .clipped()
                    .accessibilityIdentifier("app.root.ready")
            }
        }
        .accessibilityIdentifier("app.root")
        .onAppear {
            Task { @MainActor in
                configurePendingStoreIfNeeded()
                scheduleDeferredStartupWorkIfNeeded()
                if UITestArgument.isPresent(.showTrialReminderPrompt) {
                    premiumStore.showTrialReminderOptInPrompt = true
                }
            }
        }
        .alert(
            AppLocalization.string("premium.trial.reminder.prompt.title"),
            isPresented: trialReminderPromptBinding,
        ) {
            Button(AppLocalization.string("premium.trial.reminder.prompt.decline"), role: .cancel) {
                premiumStore.dismissTrialReminderOptIn()
            }
            .accessibilityIdentifier("premium.trial.reminder.prompt.decline")
            Button(AppLocalization.string("premium.trial.reminder.prompt.confirm")) {
                Task { await premiumStore.confirmTrialReminderOptIn() }
            }
            .accessibilityIdentifier("premium.trial.reminder.prompt.confirm")
        } message: {
            Text(AppLocalization.string("premium.trial.reminder.prompt.message"))
        }
        .confirmationDialog(
            AppLocalization.string("premium.trial.notification_permission.prompt.title"),
            isPresented: trialNotificationPermissionPromptBinding,
            titleVisibility: .visible
        ) {
            Button(AppLocalization.string("Not now"), role: .cancel) {
                premiumStore.dismissTrialNotificationPermissionOptIn()
            }
            Button(AppLocalization.string("premium.trial.notification_permission.prompt.confirm")) {
                Task { await premiumStore.confirmTrialNotificationPermissionOptIn() }
            }
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
