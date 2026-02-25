import SwiftUI
import SwiftData

@MainActor
struct RootView: View {
    @StateObject private var premiumStore: PremiumStore
    @StateObject private var metricsStore: ActiveMetricsStore
    @StateObject private var pendingPhotoSaveStore = PendingPhotoSaveStore()
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    private let autoCheckPaywallPrompt: Bool
    private let isAuditCaptureEnabled = AuditConfig.current.isEnabled
    @State private var didConfigurePendingStore = false

    init(
        premiumStore: PremiumStore? = nil,
        metricsStore: ActiveMetricsStore? = nil,
        autoCheckPaywallPrompt: Bool = true
    ) {
        _premiumStore = StateObject(wrappedValue: premiumStore ?? PremiumStore())
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
        }
        .onAppear {
            configurePendingStoreIfNeeded()
        }
        .confirmationDialog(
            AppLocalization.string("premium.trial.reminder.prompt.title"),
            isPresented: trialReminderPromptBinding,
            titleVisibility: .visible
        ) {
            Button(AppLocalization.string("Not now"), role: .cancel) {
                premiumStore.dismissTrialReminderOptIn()
            }
            Button(AppLocalization.string("Enable reminders")) {
                Task { await premiumStore.confirmTrialReminderOptIn() }
            }
        } message: {
            Text(AppLocalization.string("premium.trial.reminder.prompt.message"))
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

    private func configurePendingStoreIfNeeded() {
        guard !didConfigurePendingStore else { return }
        didConfigurePendingStore = true
        pendingPhotoSaveStore.configure(container: modelContext.container)
        pendingPhotoSaveStore.restoreAndResume()
    }
}
