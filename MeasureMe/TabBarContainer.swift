import SwiftUI
import SwiftData
import FabBar

struct TabBarContainer: View {
    let autoCheckPaywallPrompt: Bool
    let premiumStore: PremiumStore
    @StateObject private var router = AppRouter()
    @Environment(\.modelContext) private var modelContext
    @State private var didApplyAuditRoute = false
    @State private var mountedTabs: Set<AppTab> = TabBarContainer.initialMountedTabs()
    @State private var didSchedulePendingEntryRetry = false
    @State private var didConsumeUITestPendingEntryFallback = false
    /// Non-nil while the release-notes sheet is up. Lives here rather than in `RootView`
    /// because `AppRouter` — which the sheet's "open it" button drives — is created here.
    @State private var whatsNewRelease: WhatsNewRelease?
    @AppSetting(\.onboarding.hasCompletedOnboarding) private var hasCompletedOnboarding: Bool = false
    @AppSetting(\.experience.lastSeenWhatsNewVersion) private var lastSeenWhatsNewVersion: String = ""

    var body: some View {
        ZStack {
            AppColorRoles.surfaceCanvas
                .ignoresSafeArea()

            TabView(selection: $router.selectedTab) {
                // HOME
                Tab(value: AppTab.home) {
                    NavigationStack {
                        HomeView(autoCheckPaywallPrompt: autoCheckPaywallPrompt)
                    }
                    .hideSystemTabBarWhenFabBarIsUsed()
                } label: {
                    Label(AppLocalization.string("Home"), systemImage: "house.fill")
                }
                .accessibilityIdentifier("tab.home")

                // MEASUREMENTS
                Tab(value: AppTab.measurements) {
                    LazyMountedTab(isMounted: shouldRenderTab(.measurements)) {
                        MeasurementsTabView()
                    }
                    .hideSystemTabBarWhenFabBarIsUsed()
                } label: {
                    Label(AppLocalization.string("Measurements"), systemImage: "ruler")
                }
                .accessibilityIdentifier("tab.measurements")

                // COMPOSE
                // Zakładka zostaje dla przypadków, w których pasek rysuje system: iOS 18–25
                // oraz iPad (FabBar chowa się przy regular size class). Na iPhonie z iOS 26
                // systemowy pasek jest ukryty, więc widoczne jest „+” z FabBara.
                Tab(value: AppTab.compose, role: .search) {
                    Color.clear
                } label: {
                    Label(AppLocalization.string("Add"), systemImage: "plus")
                }
                .accessibilityIdentifier("tab.add")

                // PHOTOS
                Tab(value: AppTab.photos) {
                    LazyMountedTab(isMounted: shouldRenderTab(.photos)) {
                        PhotoView()
                    }
                    .hideSystemTabBarWhenFabBarIsUsed()
                } label: {
                    Label(AppLocalization.string("Photos"), systemImage: "photo")
                }
                .accessibilityIdentifier("tab.photos")

                // SETTINGS
                Tab(value: AppTab.settings) {
                    LazyMountedTab(isMounted: shouldRenderTab(.settings)) {
                        SettingsView()
                    }
                    .hideSystemTabBarWhenFabBarIsUsed()
                } label: {
                    Label(AppLocalization.string("Settings"), systemImage: "gearshape")
                }
                .accessibilityIdentifier("tab.settings")
            }
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(AppColorRoles.surfaceChrome, for: .tabBar)
            .applyTabBarMinimizeBehaviorIfAvailable()
            .applyFabBarIfAvailable(selection: $router.selectedTab) {
                router.presentComposer()
            }
            // `.tint` musi być NAD `.applyFabBarIfAvailable`: FabBar dokłada pasek jako
            // rodzeństwo modyfikowanego widoku, więc tint nałożony pod spodem by go ominął
            // i przycisk „+” zostałby systemowo niebieski.
            .tint(Color.appAccent)
            .onChange(of: router.selectedTab) { oldTab, newTab in
                handleSelectedTabChange(oldTab: oldTab, newTab: newTab)
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

                    Button(AppLocalization.string("Take Photo")) {
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("photos.add.menu.camera")

                    Divider().padding(.leading, 20)

                    Button(AppLocalization.string("Choose from Library")) {
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
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
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
        .sheet(item: $whatsNewRelease) { release in
            WhatsNewSheet(release: release) {
                router.openBodyModel()
            }
            .presentationDragIndicator(.visible)
        }
        .environmentObject(premiumStore)
        .environmentObject(router)
        .task { @MainActor in
            applyAuditRouteIfNeeded()
            resolveWhatsNew()
            mountTabIfNeeded(router.selectedTab)
            consumePendingNavigationRouteIfNeeded()
            consumePendingAppEntryActionIfNeeded()
            schedulePendingAppEntryRetryIfNeeded()
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

    /// Opens the release notes once per version, and stamps the version either way so the
    /// sheet cannot come back on the next launch.
    private func resolveWhatsNew() {
        guard !AuditConfig.current.isEnabled else { return }

        // A sheet nobody asked for derails every other UI test, so test mode suppresses it —
        // but then nothing could ever exercise it, so one flag opts back in explicitly.
        // Same shape as `-uiTestShowTrialReminderPrompt`.
        if UITestArgument.isPresent(.showWhatsNew) {
            whatsNewRelease = WhatsNewRelease.catalogue.first
            return
        }
        guard !UITestArgument.isAnyTestMode else { return }

        switch WhatsNewGate.decide(
            currentVersion: WhatsNewGate.currentVersion,
            lastSeenVersion: lastSeenWhatsNewVersion,
            hasCompletedOnboarding: hasCompletedOnboarding
        ) {
        case let .present(release):
            lastSeenWhatsNewVersion = release.version
            whatsNewRelease = release
        case let .stampOnly(version):
            lastSeenWhatsNewVersion = version
        case .none:
            break
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

    private func shouldRenderTab(_ tab: AppTab) -> Bool {
        mountedTabs.contains(tab) || router.selectedTab == tab
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
        case .measurements:
            router.selectTab(.measurements)
            mountTabIfNeeded(.measurements)
        case .settings:
            router.selectTab(.settings)
            mountTabIfNeeded(.settings)
        case .metricDetail(let kindRaw):
            guard let kind = MetricKind(rawValue: kindRaw) else { return }
            mountTabIfNeeded(.measurements)
            router.openMetricDetail(kind)
        case .quickAdd(let kindRaw):
            if let kindRaw, let kind = MetricKind(rawValue: kindRaw) {
                mountTabIfNeeded(.measurements)
                router.selectTab(.measurements)
                router.presentAddSample(for: kind)
            } else {
                router.presentComposer()
            }
        }
    }
}

/// Chowa systemowy pasek tylko tam, gdzie FabBar faktycznie się rysuje.
///
/// FabBar wyświetla się wyłącznie przy compact horizontal size class (iPhone) — na iPadzie sam
/// się chowa. Bez tego warunku iPad zostałby bez jakiegokolwiek paska zakładek.
@available(iOS 26.0, *)
private struct SystemTabBarVisibility: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        content
            .fabBarSafeAreaPadding()
            .toolbarVisibility(horizontalSizeClass == .compact ? .hidden : .automatic, for: .tabBar)
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

    /// Od iOS 26 pasek rysuje FabBar, więc systemowy trzeba schować — inaczej byłyby dwa.
    @ViewBuilder
    func hideSystemTabBarWhenFabBarIsUsed() -> some View {
        if #available(iOS 26.0, *) {
            self.modifier(SystemTabBarVisibility())
        } else {
            self
        }
    }

    /// Podmienia systemowy pasek na FabBar: te same cztery zakładki plus odczepione „+” po prawej.
    ///
    /// Systemowy `Tab(role: .search)` rysował „+” osobno tylko do iOS 26 — na iOS 27 trzyma go
    /// w pasku, na końcu rzędu. FabBar składa pasek z segmentowanego kontrolek i przycisku FAB
    /// w jednym `UIGlassContainerEffect`, więc wygląd nie zależy już od wersji systemu.
    @ViewBuilder
    func applyFabBarIfAvailable(
        selection: Binding<AppTab>,
        onCompose: @escaping () -> Void
    ) -> some View {
        if #available(iOS 26.0, *) {
            self.fabBar(
                selection: selection,
                tabs: [
                    FabBarTab(value: AppTab.home, title: AppLocalization.string("Home"), systemImage: "house.fill"),
                    FabBarTab(value: AppTab.measurements, title: AppLocalization.string("Measurements"), systemImage: "ruler"),
                    FabBarTab(value: AppTab.photos, title: AppLocalization.string("Photos"), systemImage: "photo"),
                    FabBarTab(value: AppTab.settings, title: AppLocalization.string("Settings"), systemImage: "gearshape"),
                ],
                action: FabBarAction(
                    systemImage: "plus",
                    accessibilityLabel: AppLocalization.string("Add"),
                    action: onCompose
                )
            )
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
        if let route = UITestArgument.value(for: .pendingNavigationRoute) {
            if route == "measurements" || route.hasPrefix("metricDetail:") || route.hasPrefix("quickAdd:") {
                return [.measurements]
            }
            if route == "settings" {
                return [.settings]
            }
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
