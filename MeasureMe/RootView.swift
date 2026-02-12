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
    }
}
