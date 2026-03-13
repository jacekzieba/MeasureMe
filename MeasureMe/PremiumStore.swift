import SwiftUI
import StoreKit
import UIKit
import Combine
import UserNotifications
import Foundation

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

private enum PremiumStoreTimeoutError: LocalizedError {
    case operationTimedOut

    var errorDescription: String? {
        "The operation timed out."
    }
}

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
    @Published var showTrialNotificationPermissionPrompt: Bool = false
    @Published var isLoading: Bool = false
    @Published var isPaywallPresented: Bool = false
    @Published var paywallReason: PaywallReason = .settings

    private let productIDs = [
        PremiumConstants.monthlyProductID,
        PremiumConstants.yearlyProductID
    ]

    private let billingClient: PremiumBillingClient
    private let notificationManager: PremiumNotificationManaging
    private let settings: AppSettingsStore
    private let analytics: AnalyticsClient
    #if DEBUG
    private let forcePremiumForUITests: Bool
    private let forceNonPremiumForUITests: Bool
    #endif
    private var hasStarted = false
    private var updateListenerTask: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?
    private var trackedPurchaseTransactionIDs: Set<UInt64> = []

    init(
        billingClient: PremiumBillingClient? = nil,
        notificationManager: PremiumNotificationManaging? = nil,
        settings: AppSettingsStore,
        analytics: AnalyticsClient? = nil,
        startListener: Bool = true
    ) {
        self.billingClient = billingClient ?? StoreKitBillingClient()
        self.notificationManager = notificationManager ?? NotificationManager.shared
        self.settings = settings
        self.analytics = analytics ?? Analytics.shared
        self.isPremium = settings.snapshot.premium.premiumEntitlement
        #if DEBUG
        self.forcePremiumForUITests = ProcessInfo.processInfo.arguments.contains("-uiTestForcePremium")
        self.forceNonPremiumForUITests = ProcessInfo.processInfo.arguments.contains("-uiTestForceNonPremium")
        #endif
        if settings.snapshot.premium.premiumFirstLaunchDate == 0 {
            Task { @MainActor in
                settings.set(\.premium.premiumFirstLaunchDate, AppClock.now.timeIntervalSince1970)
            }
        }
        #if DEBUG
        if forcePremiumForUITests {
            Task { @MainActor in
                self.isPremium = true
                settings.set(\.premium.premiumEntitlement, true)
            }
        }
        #endif

        if startListener {
            startIfNeeded()
        }
    }

    convenience init(
        billingClient: PremiumBillingClient? = nil,
        notificationManager: PremiumNotificationManaging? = nil,
        analytics: AnalyticsClient? = nil,
        startListener: Bool = true
    ) {
        self.init(
            billingClient: billingClient,
            notificationManager: notificationManager,
            settings: .shared,
            analytics: analytics,
            startListener: startListener
        )
    }

    deinit {
        updateListenerTask?.cancel()
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    func presentPaywall(reason: PaywallReason) {
        paywallReason = reason
        analytics.trackPaywallShown(
            reason: reason.analyticsReason,
            parameters: reason.analyticsParameters
        )
        isPaywallPresented = true
    }

    func dismissPaywall() {
        isPaywallPresented = false
    }

    func clearActionMessage() {
        actionMessage = nil
        actionMessageIsError = false
    }

    func syncEntitlements() async {
        await refreshEntitlements()
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.syncEntitlements()
            }
        }
        updateListenerTask = Task {
            await loadProducts()
            await refreshEntitlements()
            await listenForUpdates()
        }
    }

    func checkSevenDayPromptIfNeeded() {
        if AuditConfig.current.isEnabled {
            return
        }
        guard !isPremium else { return }
        let firstLaunch = settings.snapshot.premium.premiumFirstLaunchDate
        guard firstLaunch > 0 else { return }

        let now = AppClock.now
        let daysSinceLaunch = now.timeIntervalSince1970 - firstLaunch
        guard daysSinceLaunch >= 7 * 24 * 3600 else { return }

        let lastNag = settings.snapshot.premium.premiumLastNagDate
        if lastNag > 0, now.timeIntervalSince1970 - lastNag < 24 * 3600 {
            return
        }

        settings.set(\.premium.premiumLastNagDate, now.timeIntervalSince1970)
        presentPaywall(reason: .sevenDayPrompt)
    }

    func loadProducts() async {
        if AuditConfig.current.disablePaywallNetwork || AuditConfig.current.isEnabled {
            isLoading = false
            products = []
            productsLoadError = AppLocalization.string("premium.subscription.disabled")
            return
        }

        isLoading = true
        productsLoadError = nil
        do {
            let fetched = try await productsWithTimeout()
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

    private func productsWithTimeout(seconds: Double = 8) async throws -> [Product] {
        try await withThrowingTaskGroup(of: [Product].self) { group in
            group.addTask {
                try await self.billingClient.products(for: self.productIDs)
            }
            group.addTask {
                let nanos = UInt64(max(seconds, 1) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanos)
                throw PremiumStoreTimeoutError.operationTimedOut
            }
            let result = try await group.next() ?? []
            group.cancelAll()
            return result
        }
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

    func handleTrialActivated() async {
        showTrialNotificationPermissionPrompt = false
        showTrialReminderOptInPrompt = true
    }

    func confirmTrialReminderOptIn() async {
        let status = await notificationManager.authorizationStatus()
        let isAuthorized = status == .authorized || status == .provisional || status == .ephemeral

        if isAuthorized {
            notificationManager.notificationsEnabled = true
            notificationManager.scheduleTrialEndingReminder(daysFromNow: 12)
            actionMessage = AppLocalization.string("premium.purchase.trial.success")
            showTrialReminderOptInPrompt = false
            showTrialNotificationPermissionPrompt = false
            showTrialThankYouAlert = true
            actionMessageIsError = false
        } else {
            showTrialReminderOptInPrompt = false
            showTrialNotificationPermissionPrompt = true
            showTrialThankYouAlert = false
        }
    }

    func confirmTrialNotificationPermissionOptIn() async {
        let previousNotificationsPreference = notificationManager.notificationsEnabled
        let granted = await notificationManager.requestAuthorization()

        if granted {
            notificationManager.notificationsEnabled = true
            notificationManager.scheduleTrialEndingReminder(daysFromNow: 12)
            actionMessage = AppLocalization.string("premium.purchase.trial.success")
        } else {
            notificationManager.notificationsEnabled = previousNotificationsPreference
            actionMessage = AppLocalization.string("premium.purchase.trial.enable.notifications")
        }

        showTrialReminderOptInPrompt = false
        showTrialNotificationPermissionPrompt = false
        showTrialThankYouAlert = true
        actionMessageIsError = false
    }

    func dismissTrialReminderOptIn() {
        showTrialReminderOptInPrompt = false
        showTrialNotificationPermissionPrompt = false
        showTrialThankYouAlert = true
        actionMessage = AppLocalization.string("premium.purchase.trial.success")
        actionMessageIsError = false
    }

    func dismissTrialNotificationPermissionOptIn() {
        showTrialReminderOptInPrompt = false
        showTrialNotificationPermissionPrompt = false
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

    static func isEntitlementActive(
        productID: String,
        revocationDate: Date?,
        expirationDate: Date?,
        isInBillingGracePeriod: Bool,
        allowedProductIDs: Set<String>,
        now: Date = Date()
    ) -> Bool {
        guard allowedProductIDs.contains(productID) else { return false }
        if let revocationDate, revocationDate <= now {
            return false
        }
        guard let expirationDate else {
            return true
        }
        if expirationDate > now {
            return true
        }
        return isInBillingGracePeriod
    }

    private func refreshEntitlements() async {
        #if DEBUG
        if forcePremiumForUITests {
            isPremium = true
            settings.set(\.premium.premiumEntitlement, true)
            return
        }
        if forceNonPremiumForUITests {
            isPremium = false
            settings.set(\.premium.premiumEntitlement, false)
            return
        }
        #endif

        var active = false
        var sawVerifiedEntitlement = false
        var sawUnverifiedEntitlement = false
        let allowedProductIDs = Set(productIDs)
        let now = AppClock.now

        if await hasActiveSubscriptionStatus(allowedProductIDs: allowedProductIDs, now: now) {
            active = true
        } else {
            // Zapasowe rozwiazanie dla przypadkow brzegowych, gdy pobranie statusu jest niedostepne.
            for await result in billingClient.currentEntitlements() {
                switch result {
                case .verified(let transaction):
                    sawVerifiedEntitlement = true
                    if Self.isEntitlementActive(
                        productID: transaction.productID,
                        revocationDate: transaction.revocationDate,
                        expirationDate: transaction.expirationDate,
                        isInBillingGracePeriod: false,
                        allowedProductIDs: allowedProductIDs,
                        now: now
                    ) {
                        active = true
                        break
                    }
                case .unverified:
                    // Nie zaniżaj stanu premium na podstawie nieweryfikowalnych danych.
                    sawUnverifiedEntitlement = true
                }
            }
        }

        if !active && !sawVerifiedEntitlement && sawUnverifiedEntitlement {
            return
        }

        isPremium = active
        settings.set(\.premium.premiumEntitlement, active)
    }

    private func hasActiveSubscriptionStatus(allowedProductIDs: Set<String>, now: Date) async -> Bool {
        guard !products.isEmpty else { return false }
        let entitlementProducts = products

        for product in entitlementProducts where allowedProductIDs.contains(product.id) {
            guard let subscription = product.subscription else { continue }
            guard let statuses = try? await subscription.status else { continue }
            for status in statuses {
                guard case .verified(let transaction) = status.transaction else { continue }
                guard case .verified(let renewalInfo) = status.renewalInfo else { continue }

                let inGraceByState = status.state == .inGracePeriod
                let inGraceByDate = (renewalInfo.gracePeriodExpirationDate ?? .distantPast) > now
                let isInGracePeriod = inGraceByState || inGraceByDate

                if Self.isEntitlementActive(
                    productID: transaction.productID,
                    revocationDate: transaction.revocationDate,
                    expirationDate: transaction.expirationDate,
                    isInBillingGracePeriod: isInGracePeriod,
                    allowedProductIDs: allowedProductIDs,
                    now: now
                ) {
                    return true
                }
            }
        }
        return false
    }

    private func listenForUpdates() async {
        for await result in billingClient.transactionUpdates() {
            guard case .verified(let transaction) = result else { continue }
            if productIDs.contains(transaction.productID) {
                trackPurchaseIfNeeded(
                    transaction,
                    parameters: ["measureme.purchase_source": "transaction_update"]
                )
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
                // Natychmiast odblokuj premium po zweryfikowanym zakupie.
                isPremium = true
                settings.set(\.premium.premiumEntitlement, true)
                var analyticsParameters = paywallReason.analyticsParameters
                analyticsParameters["measureme.purchase_source"] = "direct_purchase"
                analyticsParameters["measureme.paywall_reason"] = paywallReason.analyticsReason
                trackPurchaseIfNeeded(transaction, parameters: analyticsParameters)
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
            analytics.track(
                signalName: PremiumTelemetrySignal.purchaseCancelled,
                parameters: purchaseContextParameters(source: "direct_purchase")
            )
            actionMessage = AppLocalization.string("premium.purchase.cancelled")
            actionMessageIsError = false
        case .pending:
            analytics.track(
                signalName: PremiumTelemetrySignal.purchasePending,
                parameters: purchaseContextParameters(source: "direct_purchase")
            )
            actionMessage = AppLocalization.string("premium.purchase.pending")
            actionMessageIsError = false
        @unknown default:
            analytics.track(
                signalName: PremiumTelemetrySignal.purchasePending,
                parameters: purchaseContextParameters(source: "direct_purchase")
            )
            actionMessage = AppLocalization.string("premium.purchase.pending")
            actionMessageIsError = false
        }
    }

    #if DEBUG
    func handlePurchaseResultForTests(_ result: Product.PurchaseResult) async {
        await handlePurchaseResult(result)
    }
    #endif

    func markPurchaseTrackedIfNeeded(transactionID: UInt64) -> Bool {
        trackedPurchaseTransactionIDs.insert(transactionID).inserted
    }

    private func trackPurchaseIfNeeded(
        _ transaction: StoreKit.Transaction,
        parameters: [String: String]
    ) {
        guard markPurchaseTrackedIfNeeded(transactionID: transaction.id) else { return }
        analytics.trackPurchaseCompleted(transaction, parameters: parameters)
    }

    private func purchaseContextParameters(source: String) -> [String: String] {
        var parameters = paywallReason.analyticsParameters
        parameters["measureme.purchase_source"] = source
        parameters["measureme.paywall_reason"] = paywallReason.analyticsReason
        return parameters
    }
}

enum PremiumConstants {
    static let monthlyProductID = "com.measureme.premium.monthly"
    static let yearlyProductID = "com.measureme.premium.yearly"
}

private enum PremiumTelemetrySignal {
    static let purchaseCancelled = "com.jacekzieba.measureme.purchase.cancelled"
    static let purchasePending = "com.jacekzieba.measureme.purchase.pending"
}

private extension PremiumStore.PaywallReason {
    var analyticsReason: String {
        switch self {
        case .settings:
            return "settings"
        case .feature:
            return "feature_locked"
        case .sevenDayPrompt:
            return "seven_day_prompt"
        case .onboarding:
            return "onboarding"
        }
    }

    var analyticsParameters: [String: String] {
        switch self {
        case .feature(let featureName):
            return ["measureme.feature_name": featureName]
        case .settings, .sevenDayPrompt, .onboarding:
            return [:]
        }
    }
}
