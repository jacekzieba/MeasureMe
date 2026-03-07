/// Cel testow: Weryfikuje logike premium (entitlements), odblokowanie funkcji i zachowanie przy wygasnieciu.
/// Dlaczego to wazne: Bledny stan premium psuje gating funkcji i moze prowadzic do blednego dostepu.
/// Kryteria zaliczenia: Dla roznych stanow entitlement wynik jest zgodny z oczekiwaniem i stabilny.

import XCTest
import StoreKit
import UserNotifications
@testable import MeasureMe

private final class MockPremiumBillingClient: PremiumBillingClient {
    var productsToReturn: [Product] = []
    var productsError: Error?
    var purchaseError: Error?
    var syncError: Error?
    private(set) var productsCallCount: Int = 0
    private(set) var currentEntitlementsCallCount: Int = 0
    private(set) var transactionUpdatesCallCount: Int = 0

    func products(for identifiers: [String]) async throws -> [Product] {
        productsCallCount += 1
        if let productsError {
            throw productsError
        }
        return productsToReturn
    }

    func purchase(_ product: Product) async throws -> Product.PurchaseResult {
        if let purchaseError {
            throw purchaseError
        }
        return .pending
    }

    func syncPurchases() async throws {
        if let syncError {
            throw syncError
        }
    }

    func currentEntitlements() -> AsyncStream<VerificationResult<Transaction>> {
        currentEntitlementsCallCount += 1
        return AsyncStream<VerificationResult<Transaction>> { continuation in
            continuation.finish()
        }
    }

    func transactionUpdates() -> AsyncStream<VerificationResult<Transaction>> {
        transactionUpdatesCallCount += 1
        return AsyncStream<VerificationResult<Transaction>> { continuation in
            continuation.finish()
        }
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

    /// Co sprawdza: Sprawdza scenariusz: LoadProductsErrorSetsFailureState.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testLoadProductsErrorSetsFailureState() async {
        let billing = MockPremiumBillingClient()
        billing.productsError = NSError(domain: "test", code: 1)
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
        billing.syncError = NSError(domain: "test", code: 2)
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

        XCTAssertTrue(store.showTrialReminderOptInPrompt)
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
        XCTAssertEqual(billing.productsCallCount, 0)
        XCTAssertEqual(billing.currentEntitlementsCallCount, 0)
        XCTAssertEqual(billing.transactionUpdatesCallCount, 0)

        store.startIfNeeded()
        try await waitUntil(timeout: 1.5) {
            billing.productsCallCount > 0 &&
            billing.currentEntitlementsCallCount > 0 &&
            billing.transactionUpdatesCallCount > 0
        }

        let productsAfterFirstStart = billing.productsCallCount
        let entitlementsAfterFirstStart = billing.currentEntitlementsCallCount
        let updatesAfterFirstStart = billing.transactionUpdatesCallCount

        store.startIfNeeded()
        try? await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(billing.productsCallCount, productsAfterFirstStart)
        XCTAssertEqual(billing.currentEntitlementsCallCount, entitlementsAfterFirstStart)
        XCTAssertEqual(billing.transactionUpdatesCallCount, updatesAfterFirstStart)
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

    func testMarkPurchaseTrackedIfNeededDeduplicatesTransactionID() {
        let billing = MockPremiumBillingClient()
        let notifications = MockPremiumNotificationManager()
        let analytics = MockPremiumAnalyticsClient()
        let store = PremiumStore(
            billingClient: billing,
            notificationManager: notifications,
            analytics: analytics,
            startListener: false
        )

        XCTAssertTrue(store.markPurchaseTrackedIfNeeded(transactionID: 42))
        XCTAssertFalse(store.markPurchaseTrackedIfNeeded(transactionID: 42))
        XCTAssertTrue(store.markPurchaseTrackedIfNeeded(transactionID: 43))
    }

    func testPendingPurchaseTracksPendingSignalWithDashboardContext() async {
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
        await store.handlePurchaseResultForTests(.pending)

        XCTAssertEqual(analytics.trackedCustomSignals.count, 1)
        XCTAssertEqual(analytics.trackedCustomSignals.first?.name, "com.jacekzieba.measureme.purchase.pending")
        XCTAssertEqual(analytics.trackedCustomSignals.first?.parameters["measureme.paywall_reason"], "feature_locked")
        XCTAssertEqual(analytics.trackedCustomSignals.first?.parameters["measureme.feature_name"], "photo_compare")
        XCTAssertEqual(analytics.trackedCustomSignals.first?.parameters["measureme.purchase_source"], "direct_purchase")
    }

    func testCancelledPurchaseTracksCancelledSignalWithDashboardContext() async {
        let billing = MockPremiumBillingClient()
        let notifications = MockPremiumNotificationManager()
        let analytics = MockPremiumAnalyticsClient()
        let store = PremiumStore(
            billingClient: billing,
            notificationManager: notifications,
            analytics: analytics,
            startListener: false
        )

        store.presentPaywall(reason: .settings)
        await store.handlePurchaseResultForTests(.userCancelled)

        XCTAssertEqual(analytics.trackedCustomSignals.count, 1)
        XCTAssertEqual(analytics.trackedCustomSignals.first?.name, "com.jacekzieba.measureme.purchase.cancelled")
        XCTAssertEqual(analytics.trackedCustomSignals.first?.parameters["measureme.paywall_reason"], "settings")
        XCTAssertEqual(analytics.trackedCustomSignals.first?.parameters["measureme.purchase_source"], "direct_purchase")
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
