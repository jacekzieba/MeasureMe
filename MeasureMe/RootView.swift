import SwiftUI

@MainActor
struct RootView: View {
    @StateObject private var premiumStore: PremiumStore
    @StateObject private var metricsStore: ActiveMetricsStore
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    private let autoCheckPaywallPrompt: Bool

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
                .sheet(isPresented: $premiumStore.isPaywallPresented) {
                    PremiumPaywallView()
                        .environmentObject(premiumStore)
                }

            if !hasCompletedOnboarding {
                OnboardingView()
                    .environmentObject(metricsStore)
                    .environmentObject(premiumStore)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .confirmationDialog(
            AppLocalization.string("premium.trial.reminder.prompt.title"),
            isPresented: $premiumStore.showTrialReminderOptInPrompt,
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
            isPresented: $premiumStore.showTrialThankYouAlert
        ) {
            Button(AppLocalization.string("OK"), role: .cancel) {}
        } message: {
            Text(AppLocalization.string("premium.trial.thankyou.message"))
        }
    }
}
