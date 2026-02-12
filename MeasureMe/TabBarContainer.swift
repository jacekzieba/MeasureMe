import SwiftUI

struct TabBarContainer: View {
    @State private var router = AppRouter()
    @AppStorage("home_tab_scroll_offset") private var homeTabScrollOffset: Double = 0.0

    var body: some View {
        @Bindable var router = router
        let tabBarShouldBeVisible = router.selectedTab != .home || homeTabScrollOffset < -14

        ZStack {
            Color.black
                .ignoresSafeArea()

            if #available(iOS 18.0, *) {
                TabView(selection: $router.selectedTab) {
                    // HOME
                    Tab(value: AppTab.home) {
                        NavigationStack {
                            HomeView()
                        }
                    } label: {
                        Label(AppLocalization.string("Home"), systemImage: "house.fill")
                    }

                    // MEASUREMENTS
                    Tab(value: AppTab.measurements) {
                        MeasurementsTabView()
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
                        PhotoView()
                    } label: {
                        Label(AppLocalization.string("Photos"), systemImage: "photo")
                    }

                    // SETTINGS
                    Tab(value: AppTab.settings) {
                        SettingsView()
                    } label: {
                        Label(AppLocalization.string("Settings"), systemImage: "gearshape")
                    }
                }
                .tint(Color(hex: "#FCA311"))
                .toolbarBackground(tabBarShouldBeVisible ? .visible : .hidden, for: .tabBar)
                .toolbarBackground(.ultraThinMaterial, for: .tabBar)
                .applyTabBarMinimizeBehaviorIfAvailable()
                .onChange(of: router.selectedTab) { oldTab, newTab in
                    if newTab == .compose {
                        router.presentedSheet = .composer(mode: .newPost)
                        router.selectedTab = oldTab
                    }
                }
            } else {
                TabView(selection: $router.selectedTab) {
                    NavigationStack {
                        HomeView()
                    }
                    .tabItem {
                        Label(AppLocalization.string("Home"), systemImage: "house.fill")
                    }
                    .tag(AppTab.home)

                    MeasurementsTabView()
                        .tabItem {
                            Label(AppLocalization.string("Measurements"), systemImage: "ruler")
                        }
                        .tag(AppTab.measurements)

                    Color.clear
                        .tabItem {
                            Label(AppLocalization.string("Add"), systemImage: "plus")
                        }
                        .tag(AppTab.compose)

                    PhotoView()
                        .tabItem {
                            Label(AppLocalization.string("Photos"), systemImage: "photo")
                        }
                        .tag(AppTab.photos)

                    SettingsView()
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
                    if newTab == .compose {
                        router.presentedSheet = .composer(mode: .newPost)
                        router.selectedTab = oldTab
                    }
                }
            }
        }
        .sheet(item: $router.presentedSheet) { sheet in
            switch sheet {
            case .composer:
                QuickAddContainerView {
                    router.presentedSheet = nil
                }
            }
        }
        .environment(router)
        .preferredColorScheme(.dark)
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
