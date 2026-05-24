import SwiftUI
import SwiftData

// MARK: - Refreshing Root (onChange observers + pull-to-refresh)

private extension HomeView {

    func refreshingHomeRoot<Content: View>(_ content: Content) -> some View {
        let contentWithMeasurementObservers = content
            .onChange(of: recentSamplesSignature) { _, _ in
                refreshMeasurementCaches()
            }
            .onChange(of: metricsStore.activeKinds) { _, _ in
                refreshMeasurementCaches()
                rebuildVisiblePhotoTilesCache()
            }
            .onChange(of: goals.count) { _, _ in
                rebuildGoalsCache()
                refreshActivationProgress()
                rebuildDashboardItemsCache()
            }

        let contentWithChecklistObservers = contentWithMeasurementObservers
            .onChange(of: settingsStore.snapshot.homeLayout.layoutData) { _, _ in
                rebuildDashboardItemsCache()
            }
            .onChange(of: horizontalSizeClass) { _, _ in
                rebuildDashboardItemsCache()
            }
            .onChange(of: isSyncEnabled) { _, _ in
                refreshChecklistState()
                fetchHealthKitData()
            }
            .onChange(of: recentPhotos.count) { _, _ in
                refreshPhotoStoreState()
                refreshChecklistState()
                if viewModel.didRunStartupPhases {
                    scheduleDeferredStartupPhaseC(delayMilliseconds: 900)
                }
            }
            .onChange(of: pendingPhotoItemsSignature) { _, _ in
                refreshPhotoStoreState()
            }
            .onChange(of: onboardingChecklistMetricsCompleted) { _, _ in
                refreshChecklistState()
            }
            .onChange(of: onboardingChecklistPremiumExplored) { _, _ in
                refreshChecklistState()
            }
            .onChange(of: onboardingSkippedHealthKit) { _, _ in
                refreshChecklistState()
            }
            .onChange(of: onboardingSkippedReminders) { _, _ in
                refreshChecklistState()
            }
            .onChange(of: activationCurrentTaskID) { _, _ in
                rebuildDashboardItemsCache()
                trackCurrentActivationTaskViewed()
            }
            .onChange(of: activationIsDismissed) { _, _ in
                rebuildDashboardItemsCache()
            }
            .onChange(of: onboardingFlowVersion) { _, _ in
                rebuildDashboardItemsCache()
            }

        let observedContent = contentWithChecklistObservers
            .onChange(of: showMeasurementsOnHome) { _, _ in
                rebuildDashboardItemsCache()
                rebuildNextFocusInsightCache()
            }
            .onChange(of: showLastPhotosOnHome) { _, _ in
                rebuildDashboardItemsCache()
            }
            .onChange(of: showHealthMetricsOnHome) { _, _ in
                rebuildDashboardItemsCache()
            }
            .onChange(of: router.selectedTab) { _, newTab in
                if newTab == .home {
                    refreshChecklistState()
                }
                if newTab == .measurements && !onboardingChecklistMetricsExplored && isWelcomeHomeState {
                    onboardingChecklistMetricsExplored = true
                    withAnimation(AppMotion.animation(AppMotion.sectionEnter, enabled: shouldAnimate)) {
                        rebuildDashboardItemsCache()
                    }
                }
            }

        return observedContent
            .refreshable {
                await refreshHomeContent()
            }
    }
}
