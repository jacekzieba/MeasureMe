import Foundation
import StoreKit
import SwiftData

enum Analytics {
    static let shared: AnalyticsClient = DynamicAnalyticsClient(
        primary: TelemetryDeckAnalyticsClient(),
        fallback: NoopAnalyticsClient()
    )
}

final class DynamicAnalyticsClient: AnalyticsClient {
    private let primary: AnalyticsClient
    private let fallback: AnalyticsClient

    init(primary: AnalyticsClient, fallback: AnalyticsClient) {
        self.primary = primary
        self.fallback = fallback
    }

    var isEnabled: Bool {
        AnalyticsPolicy.isEnabled()
    }

    func setup() {
        guard isEnabled else {
            fallback.setup()
            return
        }
        primary.setup()
    }

    func track(_ signal: AnalyticsSignal) {
        guard isEnabled else {
            fallback.track(signal)
            return
        }
        primary.setup()
        primary.track(signal)
    }

    func track(signalName: String, parameters: [String : String]) {
        guard isEnabled else {
            fallback.track(signalName: signalName, parameters: parameters)
            return
        }
        primary.setup()
        primary.track(signalName: signalName, parameters: parameters)
    }

    func trackPaywallShown(reason: String, parameters: [String: String]) {
        guard isEnabled else {
            fallback.trackPaywallShown(reason: reason, parameters: parameters)
            return
        }
        primary.setup()
        primary.trackPaywallShown(reason: reason, parameters: parameters)
    }

    func trackPurchaseCompleted(_ transaction: StoreKit.Transaction, parameters: [String : String]) {
        guard isEnabled else {
            fallback.trackPurchaseCompleted(transaction, parameters: parameters)
            return
        }
        primary.setup()
        primary.trackPurchaseCompleted(transaction, parameters: parameters)
    }
}

enum AnalyticsFirstEventTracker {
    static var settings: AppSettingsStore = .shared

    static func trackFirstMetricIfNeeded(previousMetricCount: Int) {
        guard previousMetricCount == 0 else { return }
        guard shouldTrackFirstMetricEvent() else { return }

        Analytics.shared.track(.firstMetricAdded)
        settings.set(\.analytics.firstMetricAddedTracked, true)
    }

    static func trackFirstPhotoIfNeeded(previousPhotoCount: Int) {
        guard previousPhotoCount == 0 else { return }
        guard shouldTrackFirstPhotoEvent() else { return }

        Analytics.shared.track(.firstPhotoAdded)
        settings.set(\.analytics.firstPhotoAddedTracked, true)
    }

    static func metricCount(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<MetricSample>())) ?? 0
    }

    static func photoCount(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<PhotoEntry>())) ?? 0
    }

    private static func shouldTrackFirstMetricEvent() -> Bool {
        let snapshot = settings.snapshot
        guard snapshot.onboarding.hasCompletedOnboarding else { return false }
        return snapshot.analytics.firstMetricAddedTracked == false
    }

    private static func shouldTrackFirstPhotoEvent() -> Bool {
        let snapshot = settings.snapshot
        guard snapshot.onboarding.hasCompletedOnboarding else { return false }
        return snapshot.analytics.firstPhotoAddedTracked == false
    }
}
