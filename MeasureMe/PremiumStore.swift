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
    var customerInfoStream: AsyncStream<CustomerInfo> { get }
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

    var customerInfoStream: AsyncStream<CustomerInfo> {
        Purchases.shared.customerInfoStream
    }
}

/// Slide kinds shown in the Premium paywall carousel. Made internal so that
/// `PaywallReason` can carry an `initialSlideKind` and the paywall view can
/// jump directly to the slide most relevant to the trigger.
enum PremiumSlideKind: Int, CaseIterable, Equatable {
    case analyst         // 0 – Your Personal Body Analyst (AI insights)
    case photos          // 1 – Visual Progress, Side by Side
    case beyondScale     // 2 – Beyond the Scale (indicators)
    case iCloud          // 3 – iCloud Sync & Restore
    case export          // 4 – Export Your Data
    case everything      // 5 – Everything in Premium

    var ordinal: Int { rawValue }
    static var slideCount: Int { Self.allCases.count }
}

/// Identifies an *automatic* (non-user-initiated) paywall prompt. Used by
/// `PremiumPromptCoordinator` to apply frequency caps per prompt kind so the
/// app does not nag the same user repeatedly with the same prompt.
enum AutomaticPromptKind: String, CaseIterable {
    case sevenDay = "seven_day"
    case postMeasurement = "post_measurement"
    case homeDiscoveryCard = "home_discovery_card"
}

@MainActor
final class PremiumStore: ObservableObject {
    enum PaywallReason: Equatable {
        case settings
        case feature(String)
        case sevenDayPrompt
        case onboarding
        case activation
        case checklist
        // Typed feature contexts — drive initial slide + plan availability.
        case aiInsights
        case photoComparison
        case export
        case iCloudSync
        case widgets
        case premiumMetric
        case postMeasurementPrompt
        case timedPrompt

        /// Slide that the carousel should open on for this reason.
        var initialSlideKind: PremiumSlideKind {
            switch self {
            case .settings, .sevenDayPrompt, .onboarding, .activation, .checklist, .timedPrompt:
                return .analyst
            case .feature:
                return .everything
            case .aiInsights, .postMeasurementPrompt:
                return .analyst
            case .photoComparison:
                return .photos
            case .premiumMetric:
                return .beyondScale
            case .iCloudSync:
                return .iCloud
            case .export:
                return .export
            case .widgets:
                return .everything
            }
        }

        /// Lifetime is hidden only during onboarding. All other premium entry
        /// points can show the non-consumable option alongside subscriptions.
        var allowsLifetime: Bool {
            switch self {
            case .onboarding:
                return false
            default:
                return true
            }
        }
    }

    @Published var products: [PremiumProduct] = []
    @Published var productsLoadError: String? = nil
    @Published var actionMessage: String? = nil
    @Published var actionMessageIsError: Bool = false
    @Published var isPremium: Bool = false
    @Published var showTrialThankYouAlert: Bool = false
    @Published var showTrialReminderOptInPrompt: Bool = false
    @Published var showTrialNotificationPermissionPrompt: Bool = false
    @Published var showPostPurchaseSetup: Bool = false
    @Published var isLoading: Bool = false
    @Published var isPurchasing: Bool = false
    @Published var isPaywallPresented: Bool = false
    @Published var paywallReason: PaywallReason = .settings

    private let productIDs = [
        PremiumConstants.legacyMonthlyProductID,
        PremiumConstants.legacyYearlyProductID,
        PremiumConstants.monthlyProductID,
        PremiumConstants.yearlyProductID,
        PremiumConstants.lifetimeProductID
    ]

    private let billingClient: PremiumBillingClient
    private let notificationManager: PremiumNotificationManaging
    private let settings: AppSettingsStore
    private let analytics: AnalyticsClient
    #if DEBUG
    private let forcePremiumForUITests: Bool
    private let forceNonPremiumForUITests: Bool
    private let forcePremiumOnSimulator: Bool
    #endif
    private var hasStarted = false
    @Published var currentOffering: Offering?
    @Published var customerInfo: CustomerInfo?

    private var updateListenerTask: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?
    private var trackedPurchaseKeys: Set<String> = []
    private var shouldPresentPostPurchaseSetupAfterPaywallDismissal = false
    private(set) lazy var promptCoordinator: PremiumPromptCoordinator = PremiumPromptCoordinator(
        settings: settings,
        isPremium: { [weak self] in self?.isPremium ?? false }
    )

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
        self.forcePremiumForUITests = UITestArgument.isPresent(.forcePremium)
        self.forceNonPremiumForUITests = UITestArgument.isPresent(.forceNonPremium)
        self.forcePremiumOnSimulator = Self.shouldForcePremiumOnSimulator(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
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
                applyPremiumEntitlement(true)
            }
        } else if forceNonPremiumForUITests {
            Task { @MainActor in
                self.isPremium = false
                applyPremiumEntitlement(false)
            }
        } else if forcePremiumOnSimulator {
            Task { @MainActor in
                self.isPremium = true
                applyPremiumEntitlement(true)
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
        analytics.track(
            AnalyticsEvents.paywallPresented(
                source: reason.telemetrySource,
                reason: reason.analyticsReason
            )
        )
        analytics.trackPaywallShown(
            reason: reason.analyticsReason,
            parameters: reason.analyticsParameters
        )
        isPaywallPresented = true
        #if DEBUG
        if UITestArgument.isAnyTestMode {
            NotificationCenter.default.post(name: .premiumStoreDidPresentPaywallForUITests, object: nil)
        }
        #endif
    }

    func setPurchaseContext(reason: PaywallReason) {
        paywallReason = reason
    }

    func dismissPaywall() {
        isPaywallPresented = false
    }

    func handlePaywallDismissed() {
        guard shouldPresentPostPurchaseSetupAfterPaywallDismissal else { return }
        shouldPresentPostPurchaseSetupAfterPaywallDismissal = false
        showPostPurchaseSetup = true
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
            // Listen for real-time entitlement changes (renewals, expirations, refunds)
            #if DEBUG
            guard !forcePremiumForUITests, !forceNonPremiumForUITests, !forcePremiumOnSimulator else { return }
            #endif
            for await info in billingClient.customerInfoStream {
                applyCustomerInfo(info)
            }
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

        // Frequency cap: respect coordinator (session + 7-day gap + dismissal cap).
        guard promptCoordinator.shouldShow(.sevenDay) else { return }

        settings.set(\.premium.premiumLastNagDate, now.timeIntervalSince1970)
        presentAutomaticPaywall(reason: .timedPrompt, promptKind: .sevenDay)
    }

    /// Present a paywall triggered by an *automatic* surface (timed nag, post-
    /// measurement nudge, home discovery card). Goes through the coordinator
    /// for frequency capping. Returns whether the paywall was actually shown.
    @discardableResult
    func presentAutomaticPaywall(reason: PaywallReason, promptKind: AutomaticPromptKind) -> Bool {
        guard promptCoordinator.shouldShow(promptKind) else { return false }
        promptCoordinator.markShown(promptKind)
        analytics.track(
            AnalyticsEvents.premiumSoftPromptSeen(promptType: promptKind.rawValue)
        )
        presentPaywall(reason: reason)
        return true
    }

    /// Notify the coordinator that the user dismissed the automatic prompt that
    /// is currently presented (so we count toward the dismissal cap).
    func recordAutomaticPromptDismissal(_ kind: AutomaticPromptKind) {
        promptCoordinator.markDismissed(kind)
        analytics.track(
            AnalyticsEvents.premiumSoftPromptDismissed(promptType: kind.rawValue)
        )
    }

    func loadProducts() async {
        guard !isLoading else { return }

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
        guard !isPurchasing else { return }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await billingClient.purchase(product.package)
            await handlePurchaseResult(result, purchasedProduct: product)
        } catch {
            actionMessage = AppLocalization.string("premium.purchase.failed", error.localizedDescription)
            actionMessageIsError = true
        }
    }

    var canSimulateTrialActivationForUITests: Bool {
        #if DEBUG
        return UITestArgument.isAnyTestMode && UITestArgument.shouldSimulateTrialActivation
        #else
        false
        #endif
    }

    func activateTrialForUITestsIfNeeded() async -> Bool {
        guard canSimulateTrialActivationForUITests else { return false }
        guard !isPurchasing else { return true }

        isPurchasing = true
        defer { isPurchasing = false }

        isPremium = true
        applyPremiumEntitlement(true)
        currentOffering = nil
        productsLoadError = nil
        actionMessage = nil
        actionMessageIsError = false
        showTrialReminderOptInPrompt = false
        showTrialNotificationPermissionPrompt = false
        showTrialThankYouAlert = false
        showPostPurchaseSetup = true
        return true
    }

    func handleTrialActivated() async {
        showTrialNotificationPermissionPrompt = false
        #if DEBUG
        if UITestArgument.isAnyTestMode {
            showTrialReminderOptInPrompt = false
            await presentPostPurchaseSetupAfterCurrentModalDismisses()
            return
        }
        #endif
        showTrialReminderOptInPrompt = true
        showPostPurchaseSetup = true
    }

    func confirmTrialReminderOptIn() async {
        let status = await notificationManager.authorizationStatus()
        let isAuthorized = status == .authorized || status == .provisional || status == .ephemeral

        if isAuthorized {
            notificationManager.notificationsEnabled = true
            notificationManager.scheduleTrialEndingReminder(daysFromNow: 12)
            analytics.track(
                AnalyticsEvents.remindersSeeded(source: .premiumTrial, repeatRule: .once)
            )
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
        analytics.track(AnalyticsEvents.notificationsPermissionPrompted(source: .premiumTrial))
        let granted = await notificationManager.requestAuthorization()

        if granted {
            notificationManager.notificationsEnabled = true
            notificationManager.scheduleTrialEndingReminder(daysFromNow: 12)
            analytics.track(
                AnalyticsEvents.notificationsPermissionResolved(source: .premiumTrial, result: "granted")
            )
            analytics.track(
                AnalyticsEvents.remindersSeeded(source: .premiumTrial, repeatRule: .once)
            )
            actionMessage = AppLocalization.string("premium.purchase.trial.success")
        } else {
            notificationManager.notificationsEnabled = previousNotificationsPreference
            analytics.track(
                AnalyticsEvents.notificationsPermissionResolved(source: .premiumTrial, result: "denied")
            )
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

    func restorePurchases(source: PurchaseRestoreSource = .settings) async {
        analytics.track(AnalyticsEvents.purchaseRestoreStarted(source: source))
        let wasPremium = isPremium
        do {
            let info = try await billingClient.restorePurchases()
            applyCustomerInfo(info)
            if isPremium {
                analytics.track(
                    AnalyticsEvents.purchaseRestoreCompleted(
                        source: source,
                        result: wasPremium ? "already_active" : "restored"
                    )
                )
                actionMessage = wasPremium
                    ? AppLocalization.string("premium.restore.already.active")
                    : AppLocalization.string("premium.restore.success")
                actionMessageIsError = false
            } else {
                analytics.track(
                    AnalyticsEvents.purchaseRestoreCompleted(source: source, result: "none")
                )
                actionMessage = AppLocalization.string("premium.restore.none")
                actionMessageIsError = false
            }
        } catch {
            analytics.track(
                AnalyticsEvents.purchaseRestoreCompleted(source: source, result: "failed")
            )
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
            applyPremiumEntitlement(true)
            return
        }
        if forceNonPremiumForUITests {
            isPremium = false
            applyPremiumEntitlement(false)
            return
        }
        if forcePremiumOnSimulator {
            isPremium = true
            applyPremiumEntitlement(true)
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
            await refreshEntitlements()
            if isPremium {
                actionMessage = AppLocalization.string("premium.purchase.success")
                actionMessageIsError = false
                await presentPostPurchaseSetupAfterCurrentModalDismisses()
                return
            }
            analytics.track(
                AnalyticsEvents.purchaseCancelled(
                    parameters: purchaseContextParameters(source: "direct_purchase")
                )
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

            let startedIntroTrial = result.customerInfo.entitlements[PremiumConstants.entitlementID]?.periodType == .trial
            if startedIntroTrial {
                await handleTrialActivated()
            } else {
                actionMessage = AppLocalization.string("premium.purchase.success")
                actionMessageIsError = false
                ReviewRequestManager.recordHighSatisfactionMoment()
                await presentPostPurchaseSetupAfterCurrentModalDismisses()
            }
        } else {
            analytics.track(
                AnalyticsEvents.purchasePending(
                    parameters: purchaseContextParameters(source: "direct_purchase")
                )
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

    private func presentPostPurchaseSetupAfterCurrentModalDismisses() async {
        if showPostPurchaseSetup {
            return
        }

        if isPaywallPresented {
            shouldPresentPostPurchaseSetupAfterPaywallDismissal = true
            dismissPaywall()
            return
        }

        showPostPurchaseSetup = true
    }

    private func applyCustomerInfo(_ info: CustomerInfo) {
        customerInfo = info
        let isEntitled = info.entitlements
            .activeInCurrentEnvironment
            .keys
            .contains(PremiumConstants.entitlementID)
        isPremium = isEntitled
        applyPremiumEntitlement(isEntitled)
    }

    private func applyPremiumEntitlement(_ isEntitled: Bool) {
        settings.set(\.premium.premiumEntitlement, isEntitled)
        WidgetDataWriter.syncPremiumAndReload(isPremium: isEntitled)
        WatchSessionManager.shared.sendApplicationContext()
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
            AnalyticsEvents.purchaseCompleted(parameters: parameters)
        )
    }

    private func purchaseContextParameters(source: String) -> [String: String] {
        var parameters = paywallReason.analyticsParameters
        parameters["measureme.purchase_source"] = source
        parameters["measureme.paywall_reason"] = paywallReason.analyticsReason
        return parameters
    }

    #if DEBUG
    static func shouldForcePremiumOnSimulator(
        arguments: [String],
        environment: [String: String]
    ) -> Bool {
        if arguments.contains(UITestArgument.forcePremium.rawValue) {
            return true
        }
        if arguments.contains(UITestArgument.forceNonPremium.rawValue) {
            return false
        }
        #if targetEnvironment(simulator)
        let isRunningTests = environment["XCTestConfigurationFilePath"] != nil
        guard !isRunningTests else {
            return false
        }
        if environment["MEASUREME_FORCE_PREMIUM_ON_SIMULATOR"] == "0" ||
            environment["MEASUREME_DISABLE_FORCE_PREMIUM_ON_SIMULATOR"] == "1" ||
            environment["MEASUREME_RC_TEST_STORE"] == "1" {
            return false
        }
        return true
        #else
        return false
        #endif
    }
    #endif
}

enum PremiumConstants {
    static let entitlementID = "MeasureMe Pro"
    static let monthlyPackageID = "monthly"
    static let yearlyPackageID = "yearly"
    static let lifetimePackageID = "lifetime"
    static let revenueCatMonthlyPackageID = "$rc_monthly"
    static let revenueCatYearlyPackageID = "$rc_annual"
    static let revenueCatLifetimePackageID = "$rc_lifetime"
    static let allowedPackageIDs: Set<String> = [
        monthlyPackageID,
        yearlyPackageID,
        lifetimePackageID,
        revenueCatMonthlyPackageID,
        revenueCatYearlyPackageID,
        revenueCatLifetimePackageID
    ]
    static let legacyMonthlyProductID = "monthly"
    static let legacyYearlyProductID = "yearly"
    static let monthlyProductID = "com.measureme.premium.monthly"
    static let yearlyProductID = "com.measureme.premium.yearly"
    static let lifetimeProductID = "com.measureme.premium.lifetime"
}

extension PremiumStore.PaywallReason {
    var analyticsReason: String {
        switch self {
        case .settings:                return "settings"
        case .feature:                 return "feature_locked"
        case .sevenDayPrompt:          return "seven_day_prompt"
        case .onboarding:              return "onboarding"
        case .activation:              return "activation"
        case .checklist:               return "checklist"
        case .aiInsights:              return "ai_insights"
        case .photoComparison:         return "photo_comparison"
        case .export:                  return "export"
        case .iCloudSync:              return "icloud_sync"
        case .widgets:                 return "widgets"
        case .premiumMetric:           return "premium_metric"
        case .postMeasurementPrompt:   return "post_measurement_prompt"
        case .timedPrompt:             return "timed_prompt"
        }
    }

    var analyticsParameters: [String: String] {
        switch self {
        case .feature(let featureName):
            return ["measureme.feature_name": featureName]
        default:
            return [:]
        }
    }

    var telemetrySource: PaywallTelemetrySource {
        switch self {
        case .settings, .sevenDayPrompt, .timedPrompt, .postMeasurementPrompt:
            return .settings
        case .feature, .aiInsights, .photoComparison, .export, .iCloudSync, .widgets, .premiumMetric:
            return .feature
        case .onboarding:
            return .onboarding
        case .activation:
            return .activation
        case .checklist:
            return .checklist
        }
    }
}

// MARK: - Automatic Prompt Coordinator

/// Frequency-capping coordinator for *automatic* paywall prompts. User-initiated
/// taps (feature locks) bypass this — only timed/discovery surfaces consult it.
///
/// Rules:
///  • Never prompt if already Premium.
///  • Never show more than one automatic prompt per app session.
///  • Never show *any* automatic prompt within 7 days of the last one.
///  • Stop showing a specific prompt kind after it's been dismissed twice.
@MainActor
final class PremiumPromptCoordinator {
    private let settings: AppSettingsStore
    private let isPremium: () -> Bool
    private let now: () -> Date
    private var didShowAutomaticPromptThisSession: Bool = false

    static let minimumGapBetweenAutomaticPromptsSeconds: TimeInterval = 7 * 24 * 3_600
    static let maxDismissalsPerKind: Int = 2

    init(
        settings: AppSettingsStore,
        isPremium: @escaping () -> Bool,
        now: @escaping () -> Date = { AppClock.now }
    ) {
        self.settings = settings
        self.isPremium = isPremium
        self.now = now
    }

    func shouldShow(_ kind: AutomaticPromptKind) -> Bool {
        if isPremium() { return false }
        if didShowAutomaticPromptThisSession { return false }

        let dismissals = settings.integer(forKey: dismissalKey(kind))
        if dismissals >= Self.maxDismissalsPerKind { return false }

        let last = settings.snapshot.premium.lastAutomaticPromptDate
        if last > 0 {
            let elapsed = now().timeIntervalSince1970 - last
            if elapsed < Self.minimumGapBetweenAutomaticPromptsSeconds {
                return false
            }
        }
        return true
    }

    func markShown(_ kind: AutomaticPromptKind) {
        didShowAutomaticPromptThisSession = true
        settings.set(\.premium.lastAutomaticPromptDate, now().timeIntervalSince1970)
        settings.set(\.premium.lastAutomaticPromptKind, kind.rawValue)
    }

    func markDismissed(_ kind: AutomaticPromptKind) {
        let current = settings.integer(forKey: dismissalKey(kind))
        settings.set(current + 1, forKey: dismissalKey(kind))
    }

    private func dismissalKey(_ kind: AutomaticPromptKind) -> String {
        AppSettingsKeys.Premium.automaticPromptDismissalPrefix + kind.rawValue
    }
}
