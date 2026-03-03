import SwiftUI
import SwiftData

struct TabBarContainer: View {
    let autoCheckPaywallPrompt: Bool
    @StateObject private var router = AppRouter()
    @AppSetting(\.home.homeTabScrollOffset) private var homeTabScrollOffset: Double = 0.0
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var premiumStore: PremiumStore
    @State private var didApplyAuditRoute = false
    @State private var mountedTabs: Set<AppTab> = [.home]

    var body: some View {
        let tabBarShouldBeVisible = router.selectedTab != .home || homeTabScrollOffset < -14

        ZStack {
            Color.black
                .ignoresSafeArea()

            if #available(iOS 18.0, *) {
                TabView(selection: $router.selectedTab) {
                    // HOME
                    Tab(value: AppTab.home) {
                        NavigationStack {
                            HomeView(autoCheckPaywallPrompt: autoCheckPaywallPrompt)
                        }
                    } label: {
                        Label(AppLocalization.string("Home"), systemImage: "house.fill")
                    }

                    // MEASUREMENTS
                    Tab(value: AppTab.measurements) {
                        LazyMountedTab(isMounted: mountedTabs.contains(.measurements)) {
                            MeasurementsTabView()
                        }
                    } label: {
                        Label(AppLocalization.string("Measurements"), systemImage: "ruler")
                    }

                    // COMPOSE
                    Tab(value: AppTab.compose, role: .search) {
                        Color.clear
                    } label: {
                        Label(AppLocalization.string("Add"), systemImage: "plus")
                    }

                    // PHOTOS
                    Tab(value: AppTab.photos) {
                        LazyMountedTab(isMounted: mountedTabs.contains(.photos)) {
                            PhotoView()
                        }
                    } label: {
                        Label(AppLocalization.string("Photos"), systemImage: "photo")
                    }

                    // SETTINGS
                    Tab(value: AppTab.settings) {
                        LazyMountedTab(isMounted: mountedTabs.contains(.settings)) {
                            SettingsView()
                        }
                    } label: {
                        Label(AppLocalization.string("Settings"), systemImage: "gearshape")
                    }
                }
                .tint(Color(hex: "#FCA311"))
                .toolbarBackground(tabBarShouldBeVisible ? .visible : .hidden, for: .tabBar)
                .toolbarBackground(.ultraThinMaterial, for: .tabBar)
                .applyTabBarMinimizeBehaviorIfAvailable()
                .onChange(of: router.selectedTab) { oldTab, newTab in
                    handleSelectedTabChange(oldTab: oldTab, newTab: newTab)
                }
            } else {
                TabView(selection: $router.selectedTab) {
                    NavigationStack {
                        HomeView(autoCheckPaywallPrompt: autoCheckPaywallPrompt)
                    }
                    .tabItem {
                        Label(AppLocalization.string("Home"), systemImage: "house.fill")
                    }
                    .tag(AppTab.home)

                    LazyMountedTab(isMounted: mountedTabs.contains(.measurements)) {
                        MeasurementsTabView()
                    }
                        .tabItem {
                            Label(AppLocalization.string("Measurements"), systemImage: "ruler")
                        }
                        .tag(AppTab.measurements)

                    Color.clear
                        .tabItem {
                            Label(AppLocalization.string("Add"), systemImage: "plus")
                        }
                        .tag(AppTab.compose)

                    LazyMountedTab(isMounted: mountedTabs.contains(.photos)) {
                        PhotoView()
                    }
                        .tabItem {
                            Label(AppLocalization.string("Photos"), systemImage: "photo")
                        }
                        .tag(AppTab.photos)

                    LazyMountedTab(isMounted: mountedTabs.contains(.settings)) {
                        SettingsView()
                    }
                        .tabItem {
                            Label(AppLocalization.string("Settings"), systemImage: "gearshape")
                        }
                        .tag(AppTab.settings)
                }
                .tint(Color(hex: "#FCA311"))
                .toolbarBackground(tabBarShouldBeVisible ? .visible : .hidden, for: .tabBar)
                .toolbarBackground(.ultraThinMaterial, for: .tabBar)
                .applyTabBarMinimizeBehaviorIfAvailable()
                .onChange(of: router.selectedTab) { oldTab, newTab in
                    handleSelectedTabChange(oldTab: oldTab, newTab: newTab)
                }
            }
        }
        .sheet(item: $router.presentedSheet) { sheet in
            switch sheet {
            case .composer:
                QuickAddContainerView {
                    router.presentedSheet = nil
                }
            case .addSample(let kind):
                AddMetricSampleView(kind: kind) { date, metricValue in
                    let sample = MetricSample(kind: kind, value: metricValue, date: date)
                    modelContext.insert(sample)
                    router.presentedSheet = nil
                }
            }
        }
        .environmentObject(router)
        .onAppear {
            DispatchQueue.main.async {
                applyAuditRouteIfNeeded()
                mountTabIfNeeded(router.selectedTab)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func applyAuditRouteIfNeeded() {
        guard AuditConfig.current.isEnabled else { return }
        guard !didApplyAuditRoute else { return }
        didApplyAuditRoute = true

        guard let route = AuditConfig.current.route else { return }
        switch route {
        case .dashboard:
            router.selectedTab = .home
        case .measurements:
            router.selectedTab = .measurements
        case .photos:
            router.selectedTab = .photos
        case .settings:
            router.selectedTab = .settings
        case .paywall:
            router.selectedTab = .settings
            premiumStore.presentPaywall(reason: .settings)
        }
    }

    private func handleSelectedTabChange(oldTab: AppTab, newTab: AppTab) {
        if newTab == .compose {
            router.presentedSheet = .composer(mode: .newPost)
            router.selectedTab = oldTab
            return
        }

        mountTabIfNeeded(newTab)

        if let signal = newTab.analyticsSelectionSignal {
            Analytics.shared.track(signal)
        }
    }

    private func mountTabIfNeeded(_ tab: AppTab) {
        guard tab != .compose else { return }
        mountedTabs.insert(tab)
    }
}

private extension View {
    @ViewBuilder
    func applyTabBarMinimizeBehaviorIfAvailable() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}

private struct LazyMountedTab<Content: View>: View {
    let isMounted: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isMounted {
            content()
        } else {
            Color.clear
        }
    }
}
