import SwiftUI
import RevenueCat
import UIKit
import Combine
import UserNotifications
import Foundation

protocol PremiumBillingClient {
    func offerings() async throws -> Offerings
    func purchase(_ package: Package) async throws -> PurchaseResultData
    func restorePurchases() async throws -> CustomerInfo
    func customerInfo() async throws -> CustomerInfo
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

struct PremiumProduct: Identifiable {
    let package: Package

    var id: String {
        package.identifier
    }

    var productIdentifier: String {
        package.storeProduct.productIdentifier
    }

    var displayName: String {
        package.storeProduct.localizedTitle
    }

    var displayPrice: String {
        package.storeProduct.localizedPriceString
    }

    var price: Decimal {
        package.storeProduct.price
    }

    var priceFormatter: NumberFormatter? {
        package.storeProduct.priceFormatter
    }

    var subscriptionPeriod: SubscriptionPeriod? {
        package.storeProduct.subscriptionPeriod
    }
}

struct RevenueCatBillingClient: PremiumBillingClient {
    func offerings() async throws -> Offerings {
        try await Purchases.shared.offerings()
    }

    func purchase(_ package: Package) async throws -> PurchaseResultData {
        try await Purchases.shared.purchase(package: package)
    }

    func restorePurchases() async throws -> CustomerInfo {
        try await Purchases.shared.restorePurchases()
    }

    func customerInfo() async throws -> CustomerInfo {
        try await Purchases.shared.customerInfo()
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

    @Published var products: [PremiumProduct] = []
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
        PremiumConstants.legacyMonthlyProductID,
        PremiumConstants.legacyYearlyProductID,
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
    @Published var currentOffering: Offering?
    @Published var customerInfo: CustomerInfo?

    private var updateListenerTask: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?
    private var trackedPurchaseKeys: Set<String> = []

    init(
        billingClient: PremiumBillingClient? = nil,
        notificationManager: PremiumNotificationManaging? = nil,
        settings: AppSettingsStore,
        analytics: AnalyticsClient? = nil,
        startListener: Bool = true
    ) {
        self.billingClient = billingClient ?? RevenueCatBillingClient()
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

    func setPurchaseContext(reason: PaywallReason) {
        paywallReason = reason
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
            let fetched = try await offeringsWithTimeout()
            currentOffering = fetched.current

            let candidatePackages = fetched.current?.availablePackages ?? []
            let filteredPackages = candidatePackages.filter { package in
                let isKnownPackage = PremiumConstants.allowedPackageIDs.contains(package.identifier)
                let isKnownProduct = productIDs.contains(package.storeProduct.productIdentifier)
                return isKnownPackage || isKnownProduct
            }

            let packagesToDisplay = filteredPackages.isEmpty ? candidatePackages : filteredPackages
            products = packagesToDisplay
                .map { PremiumProduct(package: $0) }
                .sorted { $0.price < $1.price }
            if products.isEmpty {
                productsLoadError = AppLocalization.string("No products returned by RevenueCat.")
            }
        } catch {
            currentOffering = nil
            products = []
            productsLoadError = error.localizedDescription
        }
        isLoading = false
    }

    private func offeringsWithTimeout(seconds: Double = 8) async throws -> Offerings {
        try await withThrowingTaskGroup(of: Offerings.self) { group in
            group.addTask {
                try await self.billingClient.offerings()
            }
            group.addTask {
                let nanos = UInt64(max(seconds, 1) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanos)
                throw PremiumStoreTimeoutError.operationTimedOut
            }
            guard let result = try await group.next() else {
                throw PremiumStoreTimeoutError.operationTimedOut
            }
            group.cancelAll()
            return result
        }
    }

    func purchase(_ product: PremiumProduct) async {
        do {
            let result = try await billingClient.purchase(product.package)
            await handlePurchaseResult(result, purchasedProduct: product)
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
            let info = try await billingClient.restorePurchases()
            applyCustomerInfo(info)
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
        if let url = customerInfo?.managementURL ?? URL(string: "https://apps.apple.com/account/subscriptions") {
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
        do {
            let info = try await billingClient.customerInfo()
            applyCustomerInfo(info)
        } catch {
            actionMessage = AppLocalization.string("premium.purchase.failed", error.localizedDescription)
            actionMessageIsError = true
        }
    }

    private func handlePurchaseResult(_ result: PurchaseResultData, purchasedProduct: PremiumProduct) async {
        if result.userCancelled {
            analytics.track(
                signalName: PremiumTelemetrySignal.purchaseCancelled,
                parameters: purchaseContextParameters(source: "direct_purchase")
            )
            actionMessage = AppLocalization.string("premium.purchase.cancelled")
            actionMessageIsError = false
            return
        }

        applyCustomerInfo(result.customerInfo)
        if isPremium {
            var analyticsParameters = paywallReason.analyticsParameters
            analyticsParameters["measureme.purchase_source"] = "direct_purchase"
            analyticsParameters["measureme.paywall_reason"] = paywallReason.analyticsReason
            trackPurchaseIfNeeded(
                purchaseKey: purchasedProduct.productIdentifier,
                parameters: analyticsParameters
            )

            let startedIntroTrial = purchasedProduct.package.storeProduct.introductoryDiscount != nil
            if startedIntroTrial {
                await handleTrialActivated()
            } else {
                actionMessage = AppLocalization.string("premium.purchase.success")
                actionMessageIsError = false
            }
        } else {
            analytics.track(
                signalName: PremiumTelemetrySignal.purchasePending,
                parameters: purchaseContextParameters(source: "direct_purchase")
            )
            actionMessage = AppLocalization.string("premium.purchase.pending")
            actionMessageIsError = false
        }
    }

    #if DEBUG
    func handlePurchaseResultForTests(_ result: PurchaseResultData, purchasedProduct: PremiumProduct) async {
        await handlePurchaseResult(result, purchasedProduct: purchasedProduct)
    }
    #endif

    private func applyCustomerInfo(_ info: CustomerInfo) {
        customerInfo = info
        let isEntitled = info.entitlements
            .activeInCurrentEnvironment
            .keys
            .contains(PremiumConstants.entitlementID)
        isPremium = isEntitled
        settings.set(\.premium.premiumEntitlement, isEntitled)
    }

    func markPurchaseTrackedIfNeeded(purchaseKey: String) -> Bool {
        trackedPurchaseKeys.insert(purchaseKey).inserted
    }

    private func trackPurchaseIfNeeded(
        purchaseKey: String,
        parameters: [String: String]
    ) {
        guard markPurchaseTrackedIfNeeded(purchaseKey: purchaseKey) else { return }
        analytics.track(
            signalName: PremiumTelemetrySignal.purchaseCompleted,
            parameters: parameters
        )
    }

    private func purchaseContextParameters(source: String) -> [String: String] {
        var parameters = paywallReason.analyticsParameters
        parameters["measureme.purchase_source"] = source
        parameters["measureme.paywall_reason"] = paywallReason.analyticsReason
        return parameters
    }
}

enum PremiumConstants {
    static let entitlementID = "MeasureMe Pro"
    static let monthlyPackageID = "monthly"
    static let yearlyPackageID = "yearly"
    static let revenueCatMonthlyPackageID = "$rc_monthly"
    static let revenueCatYearlyPackageID = "$rc_annual"
    static let allowedPackageIDs: Set<String> = [
        monthlyPackageID,
        yearlyPackageID,
        revenueCatMonthlyPackageID,
        revenueCatYearlyPackageID
    ]
    static let legacyMonthlyProductID = "monthly"
    static let legacyYearlyProductID = "yearly"
    static let monthlyProductID = "com.measureme.premium.monthly"
    static let yearlyProductID = "com.measureme.premium.yearly"
}

private enum PremiumTelemetrySignal {
    static let purchaseCompleted = "com.jacekzieba.measureme.purchase.completed"
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
