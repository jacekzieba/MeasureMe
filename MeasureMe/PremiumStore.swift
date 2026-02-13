import SwiftUI
import StoreKit
import UIKit
import Combine
import UserNotifications

protocol PremiumBillingClient {
    func products(for identifiers: [String]) async throws -> [Product]
    func purchase(_ product: Product) async throws -> Product.PurchaseResult
    func syncPurchases() async throws
    func currentEntitlements() -> AsyncStream<VerificationResult<StoreKit.Transaction>>
    func transactionUpdates() -> AsyncStream<VerificationResult<StoreKit.Transaction>>
}

protocol PremiumNotificationManaging: AnyObject {
    var notificationsEnabled: Bool { get set }
    func scheduleTrialEndingReminder(daysFromNow: Int)
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> Bool
}

extension NotificationManager: PremiumNotificationManaging {}

struct StoreKitBillingClient: PremiumBillingClient {
    func products(for identifiers: [String]) async throws -> [Product] {
        try await Product.products(for: identifiers)
    }

    func purchase(_ product: Product) async throws -> Product.PurchaseResult {
        try await product.purchase()
    }

    func syncPurchases() async throws {
        try await AppStore.sync()
    }

    func currentEntitlements() -> AsyncStream<VerificationResult<StoreKit.Transaction>> {
        AsyncStream { continuation in
            let task = Task {
                for await result in StoreKit.Transaction.currentEntitlements {
                    continuation.yield(result)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func transactionUpdates() -> AsyncStream<VerificationResult<StoreKit.Transaction>> {
        AsyncStream { continuation in
            let task = Task {
                for await result in StoreKit.Transaction.updates {
                    continuation.yield(result)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

@MainActor
final class PremiumStore: ObservableObject {
    enum PaywallReason: Equatable {
        case settings
        case feature(String)
        case sevenDayPrompt
        case onboarding
    }

    @Published var products: [Product] = []
    @Published var productsLoadError: String? = nil
    @Published var actionMessage: String? = nil
    @Published var actionMessageIsError: Bool = false
    @Published var isPremium: Bool = false
    @Published var showTrialThankYouAlert: Bool = false
    @Published var showTrialReminderOptInPrompt: Bool = false
    @Published var isLoading: Bool = false
    @Published var isPaywallPresented: Bool = false
    @Published var paywallReason: PaywallReason = .settings

    private let productIDs = [
        PremiumConstants.monthlyProductID,
        PremiumConstants.yearlyProductID
    ]

    private let firstLaunchKey = "premium_first_launch_date"
    private let lastNagKey = "premium_last_nag_date"
    private let entitlementKey = "premium_entitlement"
    private let billingClient: PremiumBillingClient
    private let notificationManager: PremiumNotificationManaging
    #if DEBUG
    private let forcePremiumForUITests: Bool
    #endif
    private var updateListenerTask: Task<Void, Never>?

    init(
        billingClient: PremiumBillingClient? = nil,
        notificationManager: PremiumNotificationManaging? = nil,
        startListener: Bool = true
    ) {
        self.billingClient = billingClient ?? StoreKitBillingClient()
        self.notificationManager = notificationManager ?? NotificationManager.shared
        #if DEBUG
        self.forcePremiumForUITests = ProcessInfo.processInfo.arguments.contains("-uiTestForcePremium")
        #endif
        let defaults = UserDefaults.standard
        if defaults.double(forKey: firstLaunchKey) == 0 {
            defaults.set(Date().timeIntervalSince1970, forKey: firstLaunchKey)
        }
        #if DEBUG
        if forcePremiumForUITests {
            isPremium = true
            defaults.set(true, forKey: entitlementKey)
        }
        #endif

        if startListener {
            updateListenerTask = Task {
                await loadProducts()
                await refreshEntitlements()
                await listenForUpdates()
            }
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    func presentPaywall(reason: PaywallReason) {
        paywallReason = reason
        isPaywallPresented = true
    }

    func dismissPaywall() {
        isPaywallPresented = false
    }

    func clearActionMessage() {
        actionMessage = nil
        actionMessageIsError = false
    }

    func checkSevenDayPromptIfNeeded() {
        guard !isPremium else { return }
        let defaults = UserDefaults.standard
        let firstLaunch = defaults.double(forKey: firstLaunchKey)
        guard firstLaunch > 0 else { return }

        let now = Date()
        let daysSinceLaunch = now.timeIntervalSince1970 - firstLaunch
        guard daysSinceLaunch >= 7 * 24 * 3600 else { return }

        let lastNag = defaults.double(forKey: lastNagKey)
        if lastNag > 0, now.timeIntervalSince1970 - lastNag < 24 * 3600 {
            return
        }

        defaults.set(now.timeIntervalSince1970, forKey: lastNagKey)
        presentPaywall(reason: .sevenDayPrompt)
    }

    func loadProducts() async {
        isLoading = true
        productsLoadError = nil
        do {
            let fetched = try await billingClient.products(for: productIDs)
            products = fetched.sorted { $0.price < $1.price }
            if products.isEmpty {
                productsLoadError = AppLocalization.string("No products returned by StoreKit.")
            }
        } catch {
            products = []
            productsLoadError = error.localizedDescription
        }
        isLoading = false
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await billingClient.purchase(product)
            await handlePurchaseResult(result)
        } catch {
            actionMessage = AppLocalization.string("premium.purchase.failed", error.localizedDescription)
            actionMessageIsError = true
        }
    }

    private func handleTrialActivated() async {
        let status = await notificationManager.authorizationStatus()
        let isAuthorized = status == .authorized || status == .provisional || status == .ephemeral

        if notificationManager.notificationsEnabled && isAuthorized {
            showTrialThankYouAlert = true
            notificationManager.scheduleTrialEndingReminder(daysFromNow: 12)
            actionMessage = AppLocalization.string("premium.purchase.trial.success")
            actionMessageIsError = false
            return
        }

        showTrialReminderOptInPrompt = true
    }

    func confirmTrialReminderOptIn() async {
        let previousNotificationsPreference = notificationManager.notificationsEnabled
        let status = await notificationManager.authorizationStatus()
        let isAuthorized = status == .authorized || status == .provisional || status == .ephemeral

        let granted: Bool
        if isAuthorized {
            granted = true
        } else {
            granted = await notificationManager.requestAuthorization()
        }

        if granted {
            notificationManager.notificationsEnabled = true
            notificationManager.scheduleTrialEndingReminder(daysFromNow: 12)
            actionMessage = AppLocalization.string("premium.purchase.trial.success")
        } else {
            notificationManager.notificationsEnabled = previousNotificationsPreference
            actionMessage = AppLocalization.string("premium.purchase.trial.enable.notifications")
        }

        showTrialReminderOptInPrompt = false
        showTrialThankYouAlert = true
        actionMessageIsError = false
    }

    func dismissTrialReminderOptIn() {
        showTrialReminderOptInPrompt = false
        showTrialThankYouAlert = true
        actionMessage = AppLocalization.string("premium.purchase.trial.enable.notifications")
        actionMessageIsError = false
    }

    func restorePurchases() async {
        let wasPremium = isPremium
        do {
            try await billingClient.syncPurchases()
            await refreshEntitlements()
            if isPremium {
                actionMessage = wasPremium
                    ? AppLocalization.string("premium.restore.already.active")
                    : AppLocalization.string("premium.restore.success")
                actionMessageIsError = false
            } else {
                actionMessage = AppLocalization.string("premium.restore.none")
                actionMessageIsError = false
            }
        } catch {
            actionMessage = AppLocalization.string("premium.restore.failed", error.localizedDescription)
            actionMessageIsError = true
        }
    }

    func openManageSubscriptions() {
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
    }

    private func refreshEntitlements() async {
        #if DEBUG
        if forcePremiumForUITests {
            isPremium = true
            UserDefaults.standard.set(true, forKey: entitlementKey)
            return
        }
        #endif

        var active = false
        for await result in billingClient.currentEntitlements() {
            guard case .verified(let transaction) = result else { continue }
            guard productIDs.contains(transaction.productID) else { continue }
            if let revocation = transaction.revocationDate, revocation <= Date() {
                continue
            }
            if let expiration = transaction.expirationDate, expiration <= Date() {
                continue
            }
            active = true
        }
        isPremium = active
        UserDefaults.standard.set(active, forKey: entitlementKey)
    }

    private func listenForUpdates() async {
        for await result in billingClient.transactionUpdates() {
            guard case .verified(let transaction) = result else { continue }
            if productIDs.contains(transaction.productID) {
                await transaction.finish()
                await refreshEntitlements()
            }
        }
    }

    private func handlePurchaseResult(_ result: Product.PurchaseResult) async {
        switch result {
        case .success(let verification):
            do {
                let transaction = try verification.payloadValue
                let startedIntroTrial = transaction.offer?.type == .introductory
                await transaction.finish()
                await refreshEntitlements()
                if startedIntroTrial {
                    await handleTrialActivated()
                } else {
                    actionMessage = AppLocalization.string("premium.purchase.success")
                    actionMessageIsError = false
                }
            } catch {
                actionMessage = AppLocalization.string("premium.purchase.failed", error.localizedDescription)
                actionMessageIsError = true
            }
        case .userCancelled:
            actionMessage = AppLocalization.string("premium.purchase.cancelled")
            actionMessageIsError = false
        case .pending:
            actionMessage = AppLocalization.string("premium.purchase.pending")
            actionMessageIsError = false
        @unknown default:
            actionMessage = AppLocalization.string("premium.purchase.pending")
            actionMessageIsError = false
        }
    }
}

enum PremiumConstants {
    static let monthlyProductID = "com.measureme.premium.monthly"
    static let yearlyProductID = "com.measureme.premium.yearly"
}
