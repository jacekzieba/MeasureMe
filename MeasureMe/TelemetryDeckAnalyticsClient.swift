import Foundation
import StoreKit
import TelemetryDeck

final class TelemetryDeckAnalyticsClient: AnalyticsClient {
    private let appID: String
    private let namespace: String
    private var didSetup = false
    private let lock = NSLock()

    init(
        appID: String = "FCE97447-95B2-4966-A2E0-080806AD7834",
        namespace: String = "com.jacekzieba"
    ) {
        self.appID = appID
        self.namespace = namespace
    }

    var isEnabled: Bool {
        AnalyticsPolicy.isEnabled()
    }

    func setup() {
        lock.lock()
        defer { lock.unlock() }
        guard !didSetup else { return }

        let config = TelemetryDeck.Config(appID: appID, namespace: namespace)
        TelemetryDeck.initialize(config: config)
        didSetup = true
    }

    func track(_ signal: AnalyticsSignal) {
        TelemetryDeck.signal(signal.rawValue)
    }

    func track(signalName: String, parameters: [String : String]) {
        TelemetryDeck.signal(signalName, parameters: parameters)
    }

    func trackPaywallShown(reason: String, parameters: [String: String]) {
        TelemetryDeck.paywallShown(reason: reason, parameters: parameters)
    }

    func trackPurchaseCompleted(_ transaction: StoreKit.Transaction, parameters: [String: String]) {
        TelemetryDeck.purchaseCompleted(transaction: transaction, parameters: parameters)
    }
}
