import XCTest
import StoreKit
import UserNotifications
@testable import MeasureMe

private final class MockPremiumBillingClient: PremiumBillingClient {
    var productsToReturn: [Product] = []
    var productsError: Error?
    var purchaseError: Error?
    var syncError: Error?

    func products(for identifiers: [String]) async throws -> [Product] {
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
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func transactionUpdates() -> AsyncStream<VerificationResult<Transaction>> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

private final class MockPremiumNotificationManager: PremiumNotificationManaging {
    var notificationsEnabled: Bool = false
    var authorizationStatusValue: UNAuthorizationStatus = .notDetermined
    var requestAuthorizationResult = false
    private(set) var scheduledTrialReminderDays: [Int] = []

    func scheduleTrialEndingReminder(daysFromNow: Int) {
        scheduledTrialReminderDays.append(daysFromNow)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatusValue
    }

    func requestAuthorization() async -> Bool {
        requestAuthorizationResult
    }
}

@MainActor
final class PremiumStoreTests: XCTestCase {
    func testLoadProductsErrorSetsFailureState() async {
        let billing = MockPremiumBillingClient()
        billing.productsError = NSError(domain: "test", code: 1)
        let notifications = MockPremiumNotificationManager()
        let store = PremiumStore(
            billingClient: billing,
            notificationManager: notifications,
            startListener: false
        )

        await store.loadProducts()

        XCTAssertTrue(store.products.isEmpty)
        XCTAssertNotNil(store.productsLoadError)
    }

    func testRestorePurchasesFailureSetsErrorMessage() async {
        let billing = MockPremiumBillingClient()
        billing.syncError = NSError(domain: "test", code: 2)
        let notifications = MockPremiumNotificationManager()
        let store = PremiumStore(
            billingClient: billing,
            notificationManager: notifications,
            startListener: false
        )

        await store.restorePurchases()

        XCTAssertTrue(store.actionMessageIsError)
        XCTAssertNotNil(store.actionMessage)
    }

    func testTrialReminderOptInDeniedRollsBackPreference() async {
        let billing = MockPremiumBillingClient()
        let notifications = MockPremiumNotificationManager()
        notifications.notificationsEnabled = true
        notifications.authorizationStatusValue = .denied
        notifications.requestAuthorizationResult = false

        let store = PremiumStore(
            billingClient: billing,
            notificationManager: notifications,
            startListener: false
        )

        await store.confirmTrialReminderOptIn()

        XCTAssertTrue(notifications.notificationsEnabled)
        XCTAssertTrue(store.showTrialThankYouAlert)
        XCTAssertFalse(store.actionMessageIsError)
        XCTAssertEqual(store.actionMessage, AppLocalization.string("premium.purchase.trial.enable.notifications"))
    }

    func testTrialReminderOptInGrantedSchedulesReminder() async {
        let billing = MockPremiumBillingClient()
        let notifications = MockPremiumNotificationManager()
        notifications.authorizationStatusValue = .authorized
        notifications.notificationsEnabled = false

        let store = PremiumStore(
            billingClient: billing,
            notificationManager: notifications,
            startListener: false
        )

        await store.confirmTrialReminderOptIn()

        XCTAssertTrue(notifications.notificationsEnabled)
        XCTAssertEqual(notifications.scheduledTrialReminderDays, [12])
        XCTAssertTrue(store.showTrialThankYouAlert)
        XCTAssertFalse(store.actionMessageIsError)
    }
}
