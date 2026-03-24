import WatchConnectivity
import SwiftUI
import Combine

/// Manages WatchConnectivity on the watchOS side.
/// Receives config (active metrics, premium status) from iOS and sends measurements back.
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var activeMetrics: [WatchMetricKind] = []
    @Published var keyMetrics: [WatchMetricKind] = []
    @Published var unitsSystem: String = "metric"
    @Published var isPremium: Bool = false

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - Send Measurements to iPhone

    func sendMeasurements(entries: [(kind: String, metricValue: Double)], date: Date) {
        guard WCSession.default.activationState == .activated else { return }

        let entriesPayload: [[String: Any]] = entries.map { entry in
            [
                "kind": entry.kind,
                "metricValue": entry.metricValue,
                "date": date.timeIntervalSince1970
            ]
        }

        let payload: [String: Any] = [
            "type": "measurement",
            "entries": entriesPayload
        ]

        WCSession.default.transferUserInfo(payload)
    }

    // MARK: - Apply Config

    private func applyApplicationContext(_ context: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if let activeRaw = context["activeMetrics"] as? [String] {
                self.activeMetrics = activeRaw.compactMap { WatchMetricKind(rawValue: $0) }
            }

            if let keyRaw = context["keyMetrics"] as? [String] {
                self.keyMetrics = keyRaw.compactMap { WatchMetricKind(rawValue: $0) }
            }

            if let units = context["unitsSystem"] as? String {
                self.unitsSystem = units
            }

            if let premium = context["isPremium"] as? Bool {
                self.isPremium = premium
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            applyApplicationContext(session.receivedApplicationContext)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyApplicationContext(applicationContext)
    }
}
