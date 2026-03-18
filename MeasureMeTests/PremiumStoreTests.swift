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
        throw NSError(domain: "test.customerInfo.unmocked", code: 4)
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
