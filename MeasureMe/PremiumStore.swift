import SwiftUI
import StoreKit
import UIKit
import Combine

@MainActor
final class PremiumStore: ObservableObject {
    enum PaywallReason: Equatable {
        case settings
        case feature(String)
        case sevenDayPrompt
        case onboarding
    }

    @Published var products: [Product] = []
    @Published var isPremium: Bool = false
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

    init() {
        let defaults = UserDefaults.standard
        if defaults.double(forKey: firstLaunchKey) == 0 {
            defaults.set(Date().timeIntervalSince1970, forKey: firstLaunchKey)
        }

        Task {
            await loadProducts()
            await refreshEntitlements()
            await listenForUpdates()
        }
    }

    func presentPaywall(reason: PaywallReason) {
        paywallReason = reason
        isPaywallPresented = true
    }

    func dismissPaywall() {
        isPaywallPresented = false
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
        do {
            let fetched = try await Product.products(for: productIDs)
            products = fetched.sorted { $0.price < $1.price }
        } catch {
            products = []
        }
        isLoading = false
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verification.payloadValue
                await transaction.finish()
                await refreshEntitlements()
            default:
                break
            }
        } catch {
            // ignore for now
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            // ignore
        }
    }

    func openManageSubscriptions() {
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
    }

    private func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
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
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            if productIDs.contains(transaction.productID) {
                await transaction.finish()
                await refreshEntitlements()
            }
        }
    }
}

enum PremiumConstants {
    static let monthlyProductID = "com.measureme.premium.monthly"
    static let yearlyProductID = "com.measureme.premium.yearly"
}
