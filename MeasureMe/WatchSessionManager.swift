import WatchConnectivity
import SwiftData
import Foundation
import Combine

/// iOS-side WatchConnectivity delegate.
/// Sends config (active metrics, premium status, units) to the watch.
/// Receives measurements from the watch and persists them via QuickAddSaveService.
@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    private var modelContainer: ModelContainer?
    private var healthKitSyncing: HealthKitSyncing?
    private var settingsObserver: AnyCancellable?

    private override init() {
        super.init()
    }

    func configure(container: ModelContainer, healthKit: HealthKitSyncing?) {
        self.modelContainer = container
        self.healthKitSyncing = healthKit
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()

        // Re-send config to watch whenever settings change (metrics, units, premium)
        settingsObserver = AppSettingsStore.shared.objectWillChange
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.sendApplicationContext()
            }
    }

    // MARK: - Send Config to Watch

    func sendApplicationContext() {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        let canSendContext = Self.shouldSendApplicationContext(
            activationState: session.activationState,
            isPaired: session.isPaired,
            isWatchAppInstalled: session.isWatchAppInstalled,
            isRunningOnSimulator: Self.isRunningOnSimulator
        )
        guard canSendContext else { return }

        let settings = AppSettingsStore.shared
        let activeStore = ActiveMetricsStore(settings: settings)

        let activeRaw = activeStore.activeKinds.map(\.rawValue)
        let keyRaw = activeStore.keyMetrics.map(\.rawValue)
        let units = settings.snapshot.profile.unitsSystem
        let isPremium = settings.snapshot.premium.premiumEntitlement

        var context: [String: Any] = [
            "activeMetrics": activeRaw,
            "keyMetrics": keyRaw,
            "unitsSystem": units,
            "isPremium": isPremium
        ]

        // Include widget data so the watch complication extension can read it
        if let defaults = UserDefaults(suiteName: WidgetDataWriter.appGroupID) {
            var widgetBlobs: [String: Data] = [:]
            for kind in MetricKind.allCases {
                let key = "widget_data_\(kind.rawValue)"
                if let data = defaults.data(forKey: key) {
                    widgetBlobs[kind.rawValue] = data
                }
            }
            if !widgetBlobs.isEmpty {
                context["widgetData"] = widgetBlobs
            }
        }

        try? session.updateApplicationContext(context)
    }

    nonisolated static func shouldSendApplicationContext(
        activationState: WCSessionActivationState,
        isPaired: Bool,
        isWatchAppInstalled: Bool,
        isRunningOnSimulator: Bool
    ) -> Bool {
        guard activationState == .activated else { return false }
        if isRunningOnSimulator { return true }
        return isPaired && isWatchAppInstalled
    }

    nonisolated private static var isRunningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    // MARK: - Handle Incoming Measurements

    nonisolated private func handleReceivedMeasurements(_ userInfo: [String: Any]) {
        guard let entries = userInfo["entries"] as? [[String: Any]] else { return }

        Task { @MainActor [weak self] in
            guard let self, let container = self.modelContainer else { return }

            let context = ModelContext(container)
            let saveService = QuickAddSaveService(
                context: context,
                healthKit: self.healthKitSyncing,
                widgetWriter: LiveWidgetDataWriter()
            )

            let units = AppSettingsStore.shared.snapshot.profile.unitsSystem

            var saveEntries: [QuickAddSaveService.Entry] = []
            for entry in entries {
                guard let kindRaw = entry["kind"] as? String,
                      let kind = MetricKind(rawValue: kindRaw),
                      let metricValue = entry["metricValue"] as? Double else { continue }
                saveEntries.append(QuickAddSaveService.Entry(kind: kind, metricValue: metricValue))
            }

            let date: Date
            if let timestamp = entries.first?["date"] as? TimeInterval {
                date = Date(timeIntervalSince1970: timestamp)
            } else {
                date = Date()
            }

            guard !saveEntries.isEmpty else { return }

            do {
                try saveService.save(entries: saveEntries, date: date, unitsSystem: units)
                await saveService.syncHealthKit(entries: saveEntries, date: date)
            } catch {
                AppLog.debug("⚠️ Watch measurement save failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            Task { @MainActor in
                self.sendApplicationContext()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard userInfo["type"] as? String == "measurement" else { return }
        handleReceivedMeasurements(userInfo)
    }
}
