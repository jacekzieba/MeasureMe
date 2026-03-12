import SwiftUI
import SwiftData

@MainActor
struct RootView: View {
    @StateObject private var premiumStore: PremiumStore
    @StateObject private var metricsStore: ActiveMetricsStore
    @StateObject private var pendingPhotoSaveStore = PendingPhotoSaveStore()
    @Environment(\.modelContext) private var modelContext
    @AppSetting(\.onboarding.hasCompletedOnboarding) private var hasCompletedOnboarding: Bool = false
    private let autoCheckPaywallPrompt: Bool
    private let isAuditCaptureEnabled = AuditConfig.current.isEnabled
    private let isUITestMode = ProcessInfo.processInfo.arguments.contains("-uiTestMode")
    @State private var didConfigurePendingStore = false
    @State private var didScheduleDeferredStartupWork = false

    init(
        premiumStore: PremiumStore? = nil,
        metricsStore: ActiveMetricsStore? = nil,
        autoCheckPaywallPrompt: Bool = true
    ) {
        _premiumStore = StateObject(wrappedValue: premiumStore ?? PremiumStore(startListener: false))
        _metricsStore = StateObject(wrappedValue: metricsStore ?? ActiveMetricsStore())
        self.autoCheckPaywallPrompt = autoCheckPaywallPrompt
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

            if ProcessInfo.processInfo.arguments.contains("-uiTestMode"),
               premiumStore.showTrialReminderOptInPrompt {
                VStack(spacing: 0) {
                    Text("prompt")
                        .font(.system(size: 1))
                        .foregroundStyle(.clear)
                        .accessibilityIdentifier("premium.trial.reminder.prompt.visible")
                        .frame(width: 1, height: 1)
                        .clipped()

                    Button(AppLocalization.string("premium.trial.reminder.prompt.decline"), role: .cancel) {
                        premiumStore.dismissTrialReminderOptIn()
                    }
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .clipped()
                    .accessibilityIdentifier("premium.trial.reminder.prompt.decline")

                    Button(AppLocalization.string("premium.trial.reminder.prompt.confirm")) {
                        Task { await premiumStore.confirmTrialReminderOptIn() }
                    }
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .clipped()
                    .accessibilityIdentifier("premium.trial.reminder.prompt.confirm")
                }
            }
        }
        .accessibilityIdentifier(isUITestMode ? "app.root.ready" : "app.root")
        .onAppear {
            Task { @MainActor in
                configurePendingStoreIfNeeded()
                scheduleDeferredStartupWorkIfNeeded()
                if ProcessInfo.processInfo.arguments.contains("-uiTestShowTrialReminderPrompt") {
                    try? await Task.sleep(for: .milliseconds(800))
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
        guard !didScheduleDeferredStartupWork else { return }
        didScheduleDeferredStartupWork = true

        Task(priority: .utility) { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))

            premiumStore.startIfNeeded()

            let pendingRestoreState = StartupInstrumentation.begin("PendingRestore")
            StartupInstrumentation.event("PendingRestoreStart")
            await pendingPhotoSaveStore.restoreAndResumeAsync()
            StartupInstrumentation.event("PendingRestoreEnd")
            StartupInstrumentation.end("PendingRestore", state: pendingRestoreState)
        }
    }
}
