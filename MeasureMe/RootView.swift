import SwiftUI

struct RootView: View {
    @StateObject private var premiumStore = PremiumStore()
    @StateObject private var metricsStore = ActiveMetricsStore()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var body: some View {
        ZStack {
            TabBarContainer()
                .environmentObject(premiumStore)
                .environmentObject(metricsStore)
                .sheet(isPresented: $premiumStore.isPaywallPresented) {
                    PremiumPaywallView()
                        .environmentObject(premiumStore)
                }
                .onAppear {
                    premiumStore.checkSevenDayPromptIfNeeded()
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
