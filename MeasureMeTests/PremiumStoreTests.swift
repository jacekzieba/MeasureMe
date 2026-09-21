/// Cel testow: Weryfikuje logike premium (entitlements), odblokowanie funkcji i zachowanie przy wygasnieciu.
/// Dlaczego to wazne: Bledny stan premium psuje gating funkcji i moze prowadzic do blednego dostepu.
/// Kryteria zaliczenia: Dla roznych stanow entitlement wynik jest zgodny z oczekiwaniem i stabilny.

import XCTest
import StoreKit
import UserNotifications
import RevenueCat
@testable import MeasureMe

private final class MockPremiumBillingClient: PremiumBillingClient {
    var offeringsError: Error?
    var purchaseError: Error?
    var restoreError: Error?
    var customerInfoError: Error?
    var customerInfoResult: CustomerInfo?
    /// Answers for `refreshCustomerInfo()`, consumed in order; the call throws once they run out.
    var refreshResults: [CustomerInfo] = []
    private(set) var refreshCallCount: Int = 0
    private(set) var offeringsCallCount: Int = 0
    private(set) var customerInfoCallCount: Int = 0

    func offerings() async throws -> Offerings {
        offeringsCallCount += 1
        if let offeringsError {
            throw offeringsError
        }
        throw NSError(domain: "test.offerings.unmocked", code: 1)
    }

    func purchase(_ package: Package) async throws -> PurchaseResultData {
        if let purchaseError {
            throw purchaseError
        }
        throw NSError(domain: "test.purchase.unmocked", code: 2)
    }

    func restorePurchases() async throws -> CustomerInfo {
        if let restoreError {
            throw restoreError
        }
        throw NSError(domain: "test.restore.unmocked", code: 3)
    }

    func customerInfo() async throws -> CustomerInfo {
        customerInfoCallCount += 1
        if let customerInfoError {
            throw customerInfoError
        }
        if let customerInfoResult {
            return customerInfoResult
        }
        throw NSError(domain: "test.customerInfo.unmocked", code: 4)
    }

    func refreshCustomerInfo() async throws -> CustomerInfo {
        refreshCallCount += 1
        guard !refreshResults.isEmpty else {
            throw NSError(domain: "test.refreshCustomerInfo.exhausted", code: 5)
        }
        return refreshResults.removeFirst()
    }

    var customerInfoStream: AsyncStream<CustomerInfo> {
        AsyncStream { continuation in continuation.finish() }
    }
}

private final class MockPremiumNotificationManager: PremiumNotificationManaging {
    var notificationsEnabled: Bool = false
    var authorizationStatusValue: UNAuthorizationStatus = .notDetermined
    var requestAuthorizationResult = false
    private(set) var scheduledTrialReminderDays: [Int] = []
    private(set) var requestAuthorizationCallCount: Int = 0

    func scheduleTrialEndingReminder(daysFromNow: Int) {
        scheduledTrialReminderDays.append(daysFromNow)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatusValue
    }

    func requestAuthorization() async -> Bool {
        requestAuthorizationCallCount += 1
        return requestAuthorizationResult
    }
}

private final class MockPremiumAnalyticsClient: AnalyticsClient {
    var isEnabled: Bool = true
    private(set) var trackedSignals: [AnalyticsSignal] = []
    private(set) var trackedCustomSignals: [(name: String, parameters: [String: String])] = []
    private(set) var paywallEvents: [(reason: String, parameters: [String: String])] = []
    private(set) var purchaseEventParameters: [[String: String]] = []

    func setup() {}

    func track(_ signal: AnalyticsSignal) {
        trackedSignals.append(signal)
    }

    func track(signalName: String, parameters: [String : String]) {
        trackedCustomSignals.append((signalName, parameters))
    }

    func trackPaywallShown(reason: String, parameters: [String : String]) {
        paywallEvents.append((reason, parameters))
    }

    func trackPurchaseCompleted(_ transaction: Transaction, parameters: [String : String]) {
        purchaseEventParameters.append(parameters)
    }
}

@MainActor
final class PremiumStoreTests: XCTestCase {
    func testShouldForcePremiumOnSimulatorReturnsFalseWhenRunningTests() {
        let shouldForce = PremiumStore.shouldForcePremiumOnSimulator(
            arguments: [],
            environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]
        )

        XCTAssertFalse(shouldForce)
    }

    func testShouldForcePremiumOnSimulatorDefaultsToRuntimePlatform() {
        let shouldForce = PremiumStore.shouldForcePremiumOnSimulator(
            arguments: [],
            environment: [:]
        )

        #if targetEnvironment(simulator)
        XCTAssertTrue(shouldForce)
        #else
        XCTAssertFalse(shouldForce)
        #endif
    }

    func testShouldForcePremiumOnSimulatorCanBeDisabledForPurchaseTesting() {
        let shouldForce = PremiumStore.shouldForcePremiumOnSimulator(
            arguments: [],
            environment: ["MEASUREME_DISABLE_FORCE_PREMIUM_ON_SIMULATOR": "1"]
        )

        XCTAssertFalse(shouldForce)
    }

    /// Co sprawdza: Sprawdza, ze IsEntitlementActive zwraca false w oczekiwanym scenariuszu.
    /// Dlaczego: Zapewnia stabilny gating premium i poprawne odblokowanie funkcji.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testIsEntitlementActiveReturnsFalseForExpiredOutsideGracePeriod() {
        let now = Date()
        let isActive = PremiumStore.isEntitlementActive(
            productID: PremiumConstants.monthlyProductID,
            revocationDate: nil,
            expirationDate: now.addingTimeInterval(-60),
            isInBillingGracePeriod: false,
            allowedProductIDs: [PremiumConstants.monthlyProductID, PremiumConstants.yearlyProductID],
            now: now
        )

        XCTAssertFalse(isActive)
    }

    /// Co sprawdza: Sprawdza, ze IsEntitlementActive zwraca true w oczekiwanym scenariuszu.
    /// Dlaczego: Zapewnia stabilny gating premium i poprawne odblokowanie funkcji.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testIsEntitlementActiveReturnsTrueForExpiredInsideGracePeriod() {
        let now = Date()
        let isActive = PremiumStore.isEntitlementActive(
            productID: PremiumConstants.monthlyProductID,
            revocationDate: nil,
            expirationDate: now.addingTimeInterval(-60),
            isInBillingGracePeriod: true,
            allowedProductIDs: [PremiumConstants.monthlyProductID, PremiumConstants.yearlyProductID],
            now: now
        )

        XCTAssertTrue(isActive)
    }

    /// Co sprawdza: Sprawdza, ze IsEntitlementActive zwraca false w oczekiwanym scenariuszu.
    /// Dlaczego: Zapewnia stabilny gating premium i poprawne odblokowanie funkcji.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testIsEntitlementActiveReturnsFalseForRevokedTransaction() {
        let now = Date()
        let isActive = PremiumStore.isEntitlementActive(
            productID: PremiumConstants.yearlyProductID,
            revocationDate: now.addingTimeInterval(-60),
            expirationDate: now.addingTimeInterval(24 * 60 * 60),
            isInBillingGracePeriod: false,
            allowedProductIDs: [PremiumConstants.monthlyProductID, PremiumConstants.yearlyProductID],
            now: now
        )

        XCTAssertFalse(isActive)
    }

    /// Co sprawdza: Sprawdza, ze IsEntitlementActive zwraca true w oczekiwanym scenariuszu.
    /// Dlaczego: Zapewnia stabilny gating premium i poprawne odblokowanie funkcji.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testIsEntitlementActiveReturnsTrueForNonExpiredSubscription() {
        let now = Date()
        let isActive = PremiumStore.isEntitlementActive(
            productID: PremiumConstants.yearlyProductID,
            revocationDate: nil,
            expirationDate: now.addingTimeInterval(24 * 60 * 60),
            isInBillingGracePeriod: false,
            allowedProductIDs: [PremiumConstants.monthlyProductID, PremiumConstants.yearlyProductID],
            now: now
        )

        XCTAssertTrue(isActive)
    }

    func testIsEntitlementActiveReturnsTrueForLifetimeWithoutExpiration() {
        let now = Date()
        let isActive = PremiumStore.isEntitlementActive(
            productID: PremiumConstants.lifetimeProductID,
            revocationDate: nil,
            expirationDate: nil,
            isInBillingGracePeriod: false,
            allowedProductIDs: [
                PremiumConstants.monthlyProductID,
                PremiumConstants.yearlyProductID,
                PremiumConstants.lifetimeProductID
            ],
            now: now
        )

        XCTAssertTrue(isActive)
    }

    /// Co sprawdza: Pytanie o przypomnienie przed koncem triala pojawia sie po zamknieciu arkusza konfiguracji, i tylko raz.
    /// Dlaczego: Wywolane od razu kolidowalo z zamykajacym sie paywallem i otwierajacym arkuszem, wiec SwiftUI je gubil i uzytkownik nigdy go nie widzial.
    /// Kryteria: Po handlePostPurchaseSetupDismissed prompt jest true; kolejne zamkniecie go nie wznawia.
    func testTrialReminderPromptFollowsTheSetupSheetOnce() async {
        let store = makeStore(billing: MockPremiumBillingClient())

        await store.handleTrialActivated()
        store.handlePostPurchaseSetupDismissed()
        XCTAssertTrue(store.showTrialReminderOptInPrompt)

        store.showTrialReminderOptInPrompt = false
        store.handlePostPurchaseSetupDismissed()
        XCTAssertFalse(store.showTrialReminderOptInPrompt, "The question is asked once per trial")
    }

    /// Co sprawdza: Zamkniecie arkusza konfiguracji po zwyklym zakupie (bez triala) nie wywoluje pytania o przypomnienie.
    /// Dlaczego: Pytanie dotyczy wylacznie triala.
    /// Kryteria: Prompt zostaje false.
    func testClosingTheSetupSheetWithoutATrialRaisesNoReminderPrompt() {
        let store = makeStore(billing: MockPremiumBillingClient())

        store.handlePostPurchaseSetupDismissed()

        XCTAssertFalse(store.showTrialReminderOptInPrompt)
    }

    /// Co sprawdza: Sprawdza scenariusz: LoadProductsErrorSetsFailureState.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testLoadProductsErrorSetsFailureState() async {
        let billing = MockPremiumBillingClient()
        billing.offeringsError = NSError(domain: "test", code: 1)
        let notifications = MockPremiumNotificationManager()
        let analytics = MockPremiumAnalyticsClient()
        let store = PremiumStore(
            billingClient: billing,
            notificationManager: notifications,
            analytics: analytics,
            startListener: false
        )

        await store.loadProducts()

        XCTAssertTrue(store.products.isEmpty)
        XCTAssertNotNil(store.productsLoadError)
    }

    /// Co sprawdza: Sprawdza scenariusz: RestorePurchasesFailureSetsErrorMessage.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testRestorePurchasesFailureSetsErrorMessage() async {
        let billing = MockPremiumBillingClient()
        billing.restoreError = NSError(domain: "test", code: 2)
        let notifications = MockPremiumNotificationManager()
        let analytics = MockPremiumAnalyticsClient()
        let store = PremiumStore(
            billingClient: billing,
            notificationManager: notifications,
            analytics: analytics,
            startListener: false
        )

        await store.restorePurchases()

        XCTAssertTrue(store.actionMessageIsError)
        XCTAssertNotNil(store.actionMessage)
    }

    /// Co sprawdza: Aktywacja triala pokazuje najpierw prompt intencji przypomnienia.
    func testHandleTrialActivated_ShowsReminderIntentPrompt() async {
        let billing = MockPremiumBillingClient()
        let notifications = MockPremiumNotificationManager()
        let analytics = MockPremiumAnalyticsClient()
        let store = PremiumStore(
            billingClient: billing,
            notificationManager: notifications,
            analytics: analytics,
            startListener: false
        )

        await store.handleTrialActivated()

        // Raised now, the prompt lands while the paywall is closing and the setup sheet is opening,
        // and SwiftUI drops it - so it waits for the sheet (see the next test).
        XCTAssertFalse(store.showTrialReminderOptInPrompt)
        XCTAssertTrue(store.showPostPurchaseSetup)
        XCTAssertFalse(store.showTrialNotificationPermissionPrompt)
        XCTAssertEqual(notifications.requestAuthorizationCallCount, 0)
        XCTAssertTrue(notifications.scheduledTrialReminderDays.isEmpty)
    }

    /// Co sprawdza: Odrzucenie kroku 1 nie pyta o permissions i kończy flow podziękowaniem.
    func testTrialReminderIntentNo_ShowsThankYouWithoutAuthorizationRequest() async {
        let billing = MockPremiumBillingClient()
        let notifications = MockPremiumNotificationManager()
        let analytics = MockPremiumAnalyticsClient()
        let store = PremiumStore(
            billingClient: billing,
            notificationManager: notifications,
            analytics: analytics,
            startListener: false
        )

        await store.handleTrialActivated()
        store.dismissTrialReminderOptIn()

        XCTAssertFalse(store.showTrialReminderOptInPrompt)
        XCTAssertFalse(store.showTrialNotificationPermissionPrompt)
        XCTAssertTrue(store.showTrialThankYouAlert)
        XCTAssertEqual(store.actionMessage, AppLocalization.string("premium.purchase.trial.success"))
        XCTAssertEqual(notifications.requestAuthorizationCallCount, 0)
        XCTAssertTrue(notifications.scheduledTrialReminderDays.isEmpty)
    }

    /// Co sprawdza: Potwierdzenie kroku 1 przy istniejącej autoryzacji planuje reminder bez kroku 2.
    func testTrialReminderIntentYes_Authorized_SchedulesReminderWithoutSecondPrompt() async {
        let billing = MockPremiumBillingClient()
        let notifications = MockPremiumNotificationManager()
        notifications.authorizationStatusValue = .authorized
        notifications.notificationsEnabled = false
        let analytics = MockPremiumAnalyticsClient()

        let store = PremiumStore(
            billingClient: billing,
            notificationManager: notifications,
            analytics: analytics,
            startListener: false
        )

        await store.handleTrialActivated()
        await store.confirmTrialReminderOptIn()

        XCTAssertTrue(notifications.notificationsEnabled)
        XCTAssertEqual(notifications.scheduledTrialReminderDays, [12])
        XCTAssertFalse(store.showTrialNotificationPermissionPrompt)
        XCTAssertTrue(store.showTrialThankYouAlert)
        XCTAssertFalse(store.actionMessageIsError)
        XCTAssertEqual(notifications.requestAuthorizationCallCount, 0)
    }

    /// Co sprawdza: Potwierdzenie kroku 1 bez autoryzacji otwiera krok 2 bez systemowego promptu.
    func testTrialReminderIntentYes_NotDetermined_ShowsPermissionPromptWithoutAuthorizationRequest() async {
        let billing = MockPremiumBillingClient()
        let notifications = MockPremiumNotificationManager()
        notifications.authorizationStatusValue = .notDetermined
        notifications.notificationsEnabled = true
        let analytics = MockPremiumAnalyticsClient()

        let store = PremiumStore(
            billingClient: billing,
            notificationManager: notifications,
            analytics: analytics,
            startListener: false
        )

        await store.handleTrialActivated()
        await store.confirmTrialReminderOptIn()

        XCTAssertFalse(store.showTrialReminderOptInPrompt)
        XCTAssertTrue(store.showTrialNotificationPermissionPrompt)
        XCTAssertFalse(store.showTrialThankYouAlert)
        XCTAssertEqual(notifications.requestAuthorizationCallCount, 0)
        XCTAssertTrue(notifications.scheduledTrialReminderDays.isEmpty)
    }

    /// Co sprawdza: Potwierdzenie kroku 2 pyta system i planuje reminder przy zgodzie.
    func testTrialPermissionPromptGranted_RequestsAuthorizationAndSchedulesReminder() async {
        let billing = MockPremiumBillingClient()
        let notifications = MockPremiumNotificationManager()
        notifications.authorizationStatusValue = .notDetermined
        notifications.requestAuthorizationResult = true
        notifications.notificationsEnabled = false
        let analytics = MockPremiumAnalyticsClient()

        let store = PremiumStore(
            billingClient: billing,
            notificationManager: notifications,
            analytics: analytics,
            startListener: false
        )

        await store.handleTrialActivated()
        await store.confirmTrialReminderOptIn()
        await store.confirmTrialNotificationPermissionOptIn()

        XCTAssertTrue(notifications.notificationsEnabled)
        XCTAssertEqual(notifications.scheduledTrialReminderDays, [12])
        XCTAssertEqual(notifications.requestAuthorizationCallCount, 1)
        XCTAssertFalse(store.showTrialNotificationPermissionPrompt)
        XCTAssertTrue(store.showTrialThankYouAlert)
        XCTAssertFalse(store.actionMessageIsError)
    }

    /// Co sprawdza: Odmowa w kroku 2 nie planuje remindera i przywraca preferencję.
    func testTrialPermissionPromptDenied_DoesNotScheduleReminderAndRestoresPreference() async {
        let billing = MockPremiumBillingClient()
        let notifications = MockPremiumNotificationManager()
        notifications.authorizationStatusValue = .notDetermined
        notifications.requestAuthorizationResult = false
        notifications.notificationsEnabled = true
        let analytics = MockPremiumAnalyticsClient()

        let store = PremiumStore(
            billingClient: billing,
            notificationManager: notifications,
            analytics: analytics,
            startListener: false
        )

        await store.handleTrialActivated()
        await store.confirmTrialReminderOptIn()
        await store.confirmTrialNotificationPermissionOptIn()

        XCTAssertTrue(notifications.notificationsEnabled)
        XCTAssertEqual(notifications.requestAuthorizationCallCount, 1)
        XCTAssertTrue(notifications.scheduledTrialReminderDays.isEmpty)
        XCTAssertFalse(store.showTrialNotificationPermissionPrompt)
        XCTAssertTrue(store.showTrialThankYouAlert)
        XCTAssertEqual(store.actionMessage, AppLocalization.string("premium.purchase.trial.enable.notifications"))
    }

    func testStartIfNeeded_DoesNotStartInInitWhenDisabledAndIsIdempotent() async throws {
        let billing = MockPremiumBillingClient()
        let notifications = MockPremiumNotificationManager()
        let analytics = MockPremiumAnalyticsClient()
        let store = PremiumStore(
            billingClient: billing,
            notificationManager: notifications,
            analytics: analytics,
            startListener: false
        )

        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(billing.offeringsCallCount, 0)
        XCTAssertEqual(billing.customerInfoCallCount, 0)

        store.startIfNeeded()
        try await waitUntil(timeout: 1.5) {
            billing.offeringsCallCount > 0 &&
            billing.customerInfoCallCount > 0
        }

        let offeringsAfterFirstStart = billing.offeringsCallCount
        let customerInfoAfterFirstStart = billing.customerInfoCallCount

        store.startIfNeeded()
        try? await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(billing.offeringsCallCount, offeringsAfterFirstStart)
        XCTAssertEqual(billing.customerInfoCallCount, customerInfoAfterFirstStart)
    }

    func testPresentPaywallTracksTelemetryDeckRevenueContext() {
        let billing = MockPremiumBillingClient()
        let notifications = MockPremiumNotificationManager()
        let analytics = MockPremiumAnalyticsClient()
        let store = PremiumStore(
            billingClient: billing,
            notificationManager: notifications,
            analytics: analytics,
            startListener: false
        )

        store.presentPaywall(reason: .feature("photo_compare"))

        XCTAssertEqual(analytics.paywallEvents.count, 1)
        XCTAssertEqual(analytics.paywallEvents.first?.reason, "feature_locked")
        XCTAssertEqual(analytics.paywallEvents.first?.parameters["measureme.feature_name"], "photo_compare")
    }

    func testMarkPurchaseTrackedIfNeededDeduplicatesPurchaseKey() {
        let billing = MockPremiumBillingClient()
        let notifications = MockPremiumNotificationManager()
        let analytics = MockPremiumAnalyticsClient()
        let store = PremiumStore(
            billingClient: billing,
            notificationManager: notifications,
            analytics: analytics,
            startListener: false
        )

        XCTAssertTrue(store.markPurchaseTrackedIfNeeded(purchaseKey: "monthly"))
        XCTAssertFalse(store.markPurchaseTrackedIfNeeded(purchaseKey: "monthly"))
        XCTAssertTrue(store.markPurchaseTrackedIfNeeded(purchaseKey: "yearly"))
    }

    func test_premiumConstants_includeLifetimeProductIdentifiers() {
        XCTAssertEqual(PremiumConstants.lifetimeProductID, "com.measureme.premium.lifetime")
        XCTAssertTrue(PremiumConstants.allowedPackageIDs.contains(PremiumConstants.lifetimePackageID))
        XCTAssertTrue(PremiumConstants.allowedPackageIDs.contains(PremiumConstants.revenueCatLifetimePackageID))
    }

    // MARK: - PaywallReason context shape (Premium refresh)

    @MainActor
    func test_paywallReason_initialSlideKind_routesToCorrectSlide() {
        XCTAssertEqual(PremiumStore.PaywallReason.aiInsights.initialSlideKind, .analyst)
        XCTAssertEqual(PremiumStore.PaywallReason.photoComparison.initialSlideKind, .photos)
        XCTAssertEqual(PremiumStore.PaywallReason.premiumMetric.initialSlideKind, .beyondScale)
        XCTAssertEqual(PremiumStore.PaywallReason.iCloudSync.initialSlideKind, .iCloud)
        XCTAssertEqual(PremiumStore.PaywallReason.export.initialSlideKind, .export)
        XCTAssertEqual(PremiumStore.PaywallReason.widgets.initialSlideKind, .everything)
        XCTAssertEqual(PremiumStore.PaywallReason.settings.initialSlideKind, .analyst)
    }

    @MainActor
    func test_paywallReason_allowsLifetime_everywhereExceptOnboarding() {
        XCTAssertTrue(PremiumStore.PaywallReason.settings.allowsLifetime)
        XCTAssertTrue(PremiumStore.PaywallReason.aiInsights.allowsLifetime)
        XCTAssertTrue(PremiumStore.PaywallReason.photoComparison.allowsLifetime)
        XCTAssertTrue(PremiumStore.PaywallReason.export.allowsLifetime)
        XCTAssertTrue(PremiumStore.PaywallReason.iCloudSync.allowsLifetime)
        XCTAssertTrue(PremiumStore.PaywallReason.widgets.allowsLifetime)
        XCTAssertTrue(PremiumStore.PaywallReason.premiumMetric.allowsLifetime)
        XCTAssertTrue(PremiumStore.PaywallReason.timedPrompt.allowsLifetime)
        XCTAssertTrue(PremiumStore.PaywallReason.postMeasurementPrompt.allowsLifetime)
        XCTAssertTrue(PremiumStore.PaywallReason.activation.allowsLifetime)
        XCTAssertTrue(PremiumStore.PaywallReason.checklist.allowsLifetime)
        XCTAssertTrue(PremiumStore.PaywallReason.feature("test").allowsLifetime)
        XCTAssertTrue(PremiumStore.PaywallReason.sevenDayPrompt.allowsLifetime)
        XCTAssertFalse(PremiumStore.PaywallReason.onboarding.allowsLifetime)
    }

    // MARK: - PremiumPromptCoordinator (frequency caps)

    @MainActor
    func test_promptCoordinator_suppressesPromptWhenPremium() {
        let store = AppSettingsStore(defaults: makeIsolatedDefaults())
        let coordinator = PremiumPromptCoordinator(settings: store, isPremium: { true })
        XCTAssertFalse(coordinator.shouldShow(.sevenDay))
        XCTAssertFalse(coordinator.shouldShow(.postMeasurement))
        XCTAssertFalse(coordinator.shouldShow(.homeDiscoveryCard))
    }

    @MainActor
    func test_promptCoordinator_suppressesAfterTwoDismissals() {
        let store = AppSettingsStore(defaults: makeIsolatedDefaults())
        let coordinator = PremiumPromptCoordinator(settings: store, isPremium: { false })
        XCTAssertTrue(coordinator.shouldShow(.postMeasurement))
        coordinator.markDismissed(.postMeasurement)
        // Still allowed after one dismissal (caps at 2). Need a fresh coordinator
        // because in-session flag has not been set (markShown wasn't called).
        let coordinator2 = PremiumPromptCoordinator(settings: store, isPremium: { false })
        XCTAssertTrue(coordinator2.shouldShow(.postMeasurement))
        coordinator2.markDismissed(.postMeasurement)
        let coordinator3 = PremiumPromptCoordinator(settings: store, isPremium: { false })
        XCTAssertFalse(coordinator3.shouldShow(.postMeasurement))
    }

    @MainActor
    func test_promptCoordinator_oneAutomaticPromptPerSession() {
        let store = AppSettingsStore(defaults: makeIsolatedDefaults())
        let coordinator = PremiumPromptCoordinator(settings: store, isPremium: { false })
        XCTAssertTrue(coordinator.shouldShow(.sevenDay))
        coordinator.markShown(.sevenDay)
        XCTAssertFalse(coordinator.shouldShow(.postMeasurement))
        XCTAssertFalse(coordinator.shouldShow(.homeDiscoveryCard))
    }

    @MainActor
    func test_promptCoordinator_enforcesSevenDayGap() {
        let store = AppSettingsStore(defaults: makeIsolatedDefaults())
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let coordinator = PremiumPromptCoordinator(
            settings: store,
            isPremium: { false },
            now: { clock }
        )
        XCTAssertTrue(coordinator.shouldShow(.sevenDay))
        coordinator.markShown(.sevenDay)

        // 6 days later — still suppressed (uses fresh coordinator to clear session flag).
        clock = clock.addingTimeInterval(6 * 24 * 3_600)
        let later = PremiumPromptCoordinator(settings: store, isPremium: { false }, now: { clock })
        XCTAssertFalse(later.shouldShow(.postMeasurement))

        // 8 days later — allowed.
        clock = clock.addingTimeInterval(2 * 24 * 3_600)
        let muchLater = PremiumPromptCoordinator(settings: store, isPremium: { false }, now: { clock })
        XCTAssertTrue(muchLater.shouldShow(.postMeasurement))
    }

    /// Co sprawdza: Spozniona, starsza odpowiedz z RevenueCat nie odbiera premium przyznanego przez swiezy zakup.
    /// Dlaczego: Zakup zatwierdzony w App Store nie odblokowywal aplikacji do restartu, bo starszy fetch nadpisywal wynik zakupu.
    /// Kryteria: Po zakupie i pozniejszym syncEntitlements ze starszym stanem isPremium nadal jest true.
    func testStaleCustomerInfoDoesNotRevokePremiumGrantedByPurchase() async throws {
        let billing = MockPremiumBillingClient()
        let purchaseTime = Date(timeIntervalSince1970: 2_000)
        // The in-flight fetch was answered by the server before the purchase was processed.
        billing.customerInfoResult = makeCustomerInfo(entitled: false, requestDate: purchaseTime.addingTimeInterval(-30))
        let store = makeStore(billing: billing)

        await store.handlePurchaseResultForTests(
            (transaction: nil, customerInfo: makeCustomerInfo(entitled: true, requestDate: purchaseTime), userCancelled: false),
            purchasedProduct: try makeProduct()
        )
        XCTAssertTrue(store.isPremium, "Purchase result should unlock premium")

        await store.syncEntitlements()

        XCTAssertTrue(store.isPremium, "An older entitlement snapshot must not lock the app again")
    }

    /// Co sprawdza: Diagnostyka zakupu odroznia entitlement aktywny tylko w innym srodowisku (sandbox/produkcja) od aktywnego tutaj.
    /// Dlaczego: To najbardziej prawdopodobna przyczyna zakupu, ktory sie udal, a premium sie nie wlaczylo - na TestFlight trzeba to zobaczyc w logu.
    /// Kryteria: Opis zawiera flagi srodowiska, a brak entitlementu jest opisany jako present=false.
    func testEntitlementDiagnosticsShowWhichEnvironmentTheEntitlementIsActiveIn() {
        let now = Date(timeIntervalSince1970: 3_000)

        let here = PremiumStore.entitlementDiagnostics(for: makeCustomerInfo(entitled: true, requestDate: now))
        XCTAssertTrue(here.contains("present=true"))
        XCTAssertTrue(here.contains("activeAnyEnvironment=true"))
        XCTAssertTrue(here.contains("activeThisEnvironment=true"))

        // The simulator counts as sandbox, so a production entitlement is active elsewhere only.
        let elsewhere = PremiumStore.entitlementDiagnostics(for: makeCustomerInfo(entitled: true, requestDate: now, sandbox: false))
        XCTAssertTrue(elsewhere.contains("activeAnyEnvironment=true"))
        XCTAssertTrue(elsewhere.contains("activeThisEnvironment=false"))
        XCTAssertTrue(elsewhere.contains("sandbox=false"))

        let none = PremiumStore.entitlementDiagnostics(for: makeCustomerInfo(entitled: false, requestDate: now))
        XCTAssertTrue(none.contains("present=false"))
    }

    /// Co sprawdza: Zakup, po ktorym wynik nie zawiera jeszcze entitlementu, jest weryfikowany ponownie i odblokowuje premium.
    /// Dlaczego: Wczesniej brak entitlementu w wyniku konczyl sie komunikatem "pending" i premium pojawialo sie dopiero po restarcie.
    /// Kryteria: Po ponownym pobraniu z entitlementem isPremium = true, komunikat sukcesu, dalsze proby sie nie wykonuja.
    func testPurchaseWithoutEntitlementInResultRechecksAndUnlocksPremium() async throws {
        let billing = MockPremiumBillingClient()
        let purchaseTime = Date(timeIntervalSince1970: 2_000)
        billing.refreshResults = [makeCustomerInfo(entitled: true, requestDate: purchaseTime.addingTimeInterval(5))]
        let store = makeStore(billing: billing, entitlementRecheckDelays: [.zero, .zero])

        await store.handlePurchaseResultForTests(
            (transaction: nil, customerInfo: makeCustomerInfo(entitled: false, requestDate: purchaseTime), userCancelled: false),
            purchasedProduct: try makeProduct()
        )

        XCTAssertTrue(store.isPremium)
        XCTAssertEqual(billing.refreshCallCount, 1, "Rechecking should stop as soon as premium is confirmed")
        XCTAssertEqual(store.actionMessage, AppLocalization.string("premium.purchase.success"))
    }

    /// Co sprawdza: Gdy entitlement nie pojawia sie mimo ponownych prob, store konczy je i pokazuje "pending".
    /// Dlaczego: Ponowne sprawdzanie nie moze trwac w nieskonczonosc ani oszukiwac uzytkownika.
    /// Kryteria: Liczba prob rowna liczbie opoznien, isPremium = false, komunikat "pending".
    func testPurchaseThatNeverBecomesEntitledReportsPendingAfterBoundedRechecks() async throws {
        let billing = MockPremiumBillingClient()
        let purchaseTime = Date(timeIntervalSince1970: 2_000)
        billing.refreshResults = [
            makeCustomerInfo(entitled: false, requestDate: purchaseTime.addingTimeInterval(1)),
            makeCustomerInfo(entitled: false, requestDate: purchaseTime.addingTimeInterval(2))
        ]
        let store = makeStore(billing: billing, entitlementRecheckDelays: [.zero, .zero])

        await store.handlePurchaseResultForTests(
            (transaction: nil, customerInfo: makeCustomerInfo(entitled: false, requestDate: purchaseTime), userCancelled: false),
            purchasedProduct: try makeProduct()
        )

        XCTAssertFalse(store.isPremium)
        XCTAssertEqual(billing.refreshCallCount, 2)
        XCTAssertEqual(store.actionMessage, AppLocalization.string("premium.purchase.pending"))
    }

    private func makeStore(
        billing: MockPremiumBillingClient,
        notifications: MockPremiumNotificationManager = MockPremiumNotificationManager(),
        entitlementRecheckDelays: [Duration] = []
    ) -> PremiumStore {
        PremiumStore(
            billingClient: billing,
            notificationManager: notifications,
            settings: AppSettingsStore(defaults: makeIsolatedDefaults()),
            analytics: MockPremiumAnalyticsClient(),
            startListener: false,
            entitlementRecheckDelays: entitlementRecheckDelays
        )
    }

    private func makeCustomerInfo(entitled: Bool, requestDate: Date, sandbox: Bool = true) -> CustomerInfo {
        let entitlements: [String: EntitlementInfo] = entitled
            ? [PremiumConstants.entitlementID: EntitlementInfo(
                identifier: PremiumConstants.entitlementID,
                isActive: true,
                willRenew: true,
                periodType: .normal,
                store: .appStore,
                productIdentifier: PremiumConstants.monthlyProductID,
                isSandbox: sandbox, // the simulator reports a sandbox environment
                ownershipType: .purchased
            )]
            : [:]
        return CustomerInfo(
            entitlements: EntitlementInfos(entitlements: entitlements),
            requestDate: requestDate,
            firstSeen: Date(timeIntervalSince1970: 1_000),
            originalAppUserId: "test-user"
        )
    }

    private func makeProduct() throws -> PremiumProduct {
        let storeProduct = TestStoreProduct(
            localizedTitle: "Monthly",
            price: 4.99,
            localizedPriceString: "$4.99",
            productIdentifier: PremiumConstants.monthlyProductID,
            productType: .autoRenewableSubscription,
            localizedDescription: "Monthly premium"
        ).toStoreProduct()
        let package = Package(
            identifier: PremiumConstants.monthlyPackageID,
            packageType: .monthly,
            storeProduct: storeProduct,
            offeringIdentifier: "default",
            webCheckoutUrl: nil
        )
        return PremiumProduct(package: package)
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "PremiumStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private extension PremiumStoreTests {
    func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(40))
        }
        XCTFail("Condition was not met before timeout")
    }
}
