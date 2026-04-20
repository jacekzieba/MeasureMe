import SwiftUI
import SwiftData

struct TabBarContainer: View {
    let autoCheckPaywallPrompt: Bool
    let premiumStore: PremiumStore
    @StateObject private var router = AppRouter()
    @Environment(\.modelContext) private var modelContext
    @State private var didApplyAuditRoute = false
    @State private var mountedTabs: Set<AppTab> = TabBarContainer.initialMountedTabs()
    @State private var didSchedulePendingEntryRetry = false
    @State private var didConsumeUITestPendingEntryFallback = false

    var body: some View {
        ZStack {
            AppColorRoles.surfaceCanvas
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
                    .accessibilityIdentifier("tab.home")

                    // MEASUREMENTS
                    Tab(value: AppTab.measurements) {
                        LazyMountedTab(isMounted: mountedTabs.contains(.measurements)) {
                            MeasurementsTabView()
                        }
                    } label: {
                        Label(AppLocalization.string("Measurements"), systemImage: "ruler")
                    }
                    .accessibilityIdentifier("tab.measurements")

                    // COMPOSE
                    Tab(value: AppTab.compose, role: .search) {
                        Color.clear
                    } label: {
                        Label(AppLocalization.string("Add"), systemImage: "plus")
                    }
                    .accessibilityIdentifier("tab.add")

                    // PHOTOS
                    Tab(value: AppTab.photos) {
                        LazyMountedTab(isMounted: mountedTabs.contains(.photos)) {
                            PhotoView()
                        }
                    } label: {
                        Label(AppLocalization.string("Photos"), systemImage: "photo")
                    }
                    .accessibilityIdentifier("tab.photos")

                    // SETTINGS
                    Tab(value: AppTab.settings) {
                        LazyMountedTab(isMounted: mountedTabs.contains(.settings)) {
                            SettingsView()
                        }
                    } label: {
                        Label(AppLocalization.string("Settings"), systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("tab.settings")
                }
                .tint(Color.appAccent)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarBackground(AppColorRoles.surfaceChrome, for: .tabBar)
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
                    .accessibilityIdentifier("tab.home")

                    LazyMountedTab(isMounted: mountedTabs.contains(.measurements)) {
                        MeasurementsTabView()
                    }
                        .tabItem {
                            Label(AppLocalization.string("Measurements"), systemImage: "ruler")
                        }
                        .tag(AppTab.measurements)
                        .accessibilityIdentifier("tab.measurements")

                    Color.clear
                        .tabItem {
                            Label(AppLocalization.string("Add"), systemImage: "plus")
                        }
                        .tag(AppTab.compose)
                        .accessibilityIdentifier("tab.add")

                    LazyMountedTab(isMounted: mountedTabs.contains(.photos)) {
                        PhotoView()
                    }
                        .tabItem {
                            Label(AppLocalization.string("Photos"), systemImage: "photo")
                        }
                        .tag(AppTab.photos)
                        .accessibilityIdentifier("tab.photos")

                    LazyMountedTab(isMounted: mountedTabs.contains(.settings)) {
                        SettingsView()
                    }
                        .tabItem {
                            Label(AppLocalization.string("Settings"), systemImage: "gearshape")
                        }
                        .tag(AppTab.settings)
                        .accessibilityIdentifier("tab.settings")
                }
                .tint(Color.appAccent)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarBackground(AppColorRoles.surfaceChrome, for: .tabBar)
                .applyTabBarMinimizeBehaviorIfAvailable()
                .onChange(of: router.selectedTab) { oldTab, newTab in
                    handleSelectedTabChange(oldTab: oldTab, newTab: newTab)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if shouldForceUITestPendingAddPhotoChooser {
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 36, height: 4)
                        .padding(.top, 8)
                        .padding(.bottom, 16)

                    Text(AppLocalization.string("Add Photo"))
                        .font(AppTypography.displaySection)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    Button("Take Photo") {
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("photos.add.menu.camera")

                    Divider().padding(.leading, 20)

                    Button("Choose from Library") {
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("photos.add.menu.library")

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .accessibilityIdentifier("photos.sourceChooser.visible")
            }
        }
        .overlay(alignment: .topLeading) {
            if UITestArgument.isAnyTestMode {
                VStack(alignment: .leading, spacing: 4) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("uitest.debug.tab.\(router.selectedTab.title.lowercased())")

                    if UITestArgument.value(for: .pendingAppEntryAction) == AppEntryAction.openAddPhoto.rawValue {
                        Color.clear
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("uitest.debug.pendingAddPhoto.active")
                    }

                    if shouldForceUITestPendingAddPhotoChooser {
                        Color.clear
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("uitest.debug.pendingAddPhoto.overlayActive")
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(false)
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
                    ReviewRequestManager.recordMetricEntryAdded(count: 1)
                    router.presentedSheet = nil
                }
            }
        }
        .environmentObject(premiumStore)
        .environmentObject(router)
        .onAppear {
            Task { @MainActor in
                applyAuditRouteIfNeeded()
                mountTabIfNeeded(router.selectedTab)
                consumePendingNavigationRouteIfNeeded()
                consumePendingAppEntryActionIfNeeded()
                schedulePendingAppEntryRetryIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppNavigationRouteDispatcher.didEnqueueNotification)) { notification in
            guard let route = notification.object as? AppNavigationRoute else { return }
            Task { @MainActor in
                let effectiveRoute = AppNavigationRouteDispatcher.consumePendingRoute() ?? route
                handleNavigationRoute(effectiveRoute)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppEntryActionDispatcher.didEnqueueNotification)) { notification in
            guard let action = notification.object as? AppEntryAction else { return }
            Task { @MainActor in
                let effectiveAction = AppEntryActionDispatcher.consumePendingAction() ?? action
                handleAppEntryAction(effectiveAction)
            }
        }
    }

    private func applyAuditRouteIfNeeded() {
        guard let initialRoute = TabBarRoutingCoordinator.initialRoute(didApplyAuditRoute: didApplyAuditRoute) else {
            return
        }
        didApplyAuditRoute = true

        switch initialRoute {
        case .tab(let tab):
            router.selectTab(tab)
            mountTabIfNeeded(tab)
        case .settingsPaywall:
            router.selectTab(.settings)
            mountTabIfNeeded(.settings)
            premiumStore.presentPaywall(reason: .settings)
        }
    }

    private func handleSelectedTabChange(oldTab: AppTab, newTab: AppTab) {
        if newTab == .compose {
            router.presentComposer()
            router.selectTab(oldTab)
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

    private func consumePendingAppEntryActionIfNeeded() {
        guard let result = TabBarRoutingCoordinator.pendingEntryAction(
            didConsumeUITestFallback: didConsumeUITestPendingEntryFallback
        ) else {
            return
        }
        didConsumeUITestPendingEntryFallback = result.consumedUITestFallback
        handleAppEntryAction(result.action)
    }

    private func schedulePendingAppEntryRetryIfNeeded() {
        guard !didSchedulePendingEntryRetry else { return }
        didSchedulePendingEntryRetry = true

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(750))
            consumePendingNavigationRouteIfNeeded()
            consumePendingAppEntryActionIfNeeded()
        }
    }

    private func consumePendingNavigationRouteIfNeeded() {
        guard let route = AppNavigationRouteDispatcher.consumePendingRoute() else { return }
        handleNavigationRoute(route)
    }

    private func handleAppEntryAction(_ action: AppEntryAction) {
        switch action {
        case .openQuickAdd:
            router.presentComposer()
        case .openAddPhoto:
            router.selectTab(.photos)
            mountTabIfNeeded(.photos)
            router.requestPhotoComposer()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                guard router.selectedTab == .photos else { return }
                guard router.photoComposerRequestID != nil else { return }
                router.requestPhotoComposer()
            }
        }
    }

    private func handleNavigationRoute(_ route: AppNavigationRoute) {
        switch route {
        case .home:
            router.selectTab(.home)
            mountTabIfNeeded(.home)
        case .metricDetail(let kindRaw):
            guard let kind = MetricKind(rawValue: kindRaw) else { return }
            router.openMetricDetail(kind)
            mountTabIfNeeded(.measurements)
        case .quickAdd(let kindRaw):
            if let kindRaw, let kind = MetricKind(rawValue: kindRaw) {
                router.selectTab(.measurements)
                mountTabIfNeeded(.measurements)
                router.presentAddSample(for: kind)
            } else {
                router.presentComposer()
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func applyTabBarMinimizeBehaviorIfAvailable() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.never)
        } else {
            self
        }
    }
}

private extension TabBarContainer {
    static func initialMountedTabs() -> Set<AppTab> {
        if UITestArgument.isPresent(.openSettingsTab) {
            return [.settings]
        }
        if UITestArgument.value(for: .pendingAppEntryAction) == AppEntryAction.openAddPhoto.rawValue {
            return [.photos]
        }
        return [.home]
    }

    var shouldForceUITestPendingAddPhotoChooser: Bool {
        UITestArgument.isPresent(.mode)
            && UITestArgument.value(for: .pendingAppEntryAction) == AppEntryAction.openAddPhoto.rawValue
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
