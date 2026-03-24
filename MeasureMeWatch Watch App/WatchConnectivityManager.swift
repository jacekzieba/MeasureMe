import WatchConnectivity
import SwiftUI
import Combine
import WidgetKit

/// Manages WatchConnectivity on the watchOS side.
/// Receives config (active metrics, premium status) from iOS and sends measurements back.
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var activeMetrics: [WatchMetricKind] = []
    @Published var keyMetrics: [WatchMetricKind] = []
    @Published var unitsSystem: String = "metric"
    #if targetEnvironment(simulator)
    @Published var isPremium: Bool = true
    #else
    @Published var isPremium: Bool = false
    #endif

    /// When true, bypasses premium check and shows default metrics (for simulator/dev).
    private var useFallbackDefaults: Bool {
        !WCSession.isSupported() || WCSession.default.activationState != .activated
    }

    private override init() {
        super.init()
        #if targetEnvironment(simulator)
        activeMetrics = [.weight, .bodyFat, .waist]
        keyMetrics = [.weight, .bodyFat, .waist]
        #endif
    }

    func activate() {
        guard WCSession.isSupported() else {
            loadFallbackDefaults()
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Provides sensible defaults when WCSession is unavailable (simulator).
    private func loadFallbackDefaults() {
        isPremium = true
        activeMetrics = [.weight, .bodyFat, .waist]
        keyMetrics = [.weight, .bodyFat, .waist]
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

            // Write widget data to watch App Group so complication extension can read it
            if let widgetBlobs = context["widgetData"] as? [String: Data],
               let defaults = UserDefaults(suiteName: watchAppGroupID) {
                for (kindRaw, data) in widgetBlobs {
                    defaults.set(data, forKey: "widget_data_\(kindRaw)")
                }
                WidgetCenter.shared.reloadTimelines(ofKind: "MeasureMeComplication")
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
