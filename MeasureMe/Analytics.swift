import Foundation
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
}

enum AnalyticsFirstEventTracker {
    private static let firstMetricTrackedKey = "analytics_first_metric_added_tracked"
    private static let firstPhotoTrackedKey = "analytics_first_photo_added_tracked"
    private static let onboardingCompletedKey = "hasCompletedOnboarding"

    static func trackFirstMetricIfNeeded(previousMetricCount: Int) {
        guard previousMetricCount == 0 else { return }
        guard shouldTrackFirstEvent(forKey: firstMetricTrackedKey) else { return }

        Analytics.shared.track(.firstMetricAdded)
        UserDefaults.standard.set(true, forKey: firstMetricTrackedKey)
    }

    static func trackFirstPhotoIfNeeded(previousPhotoCount: Int) {
        guard previousPhotoCount == 0 else { return }
        guard shouldTrackFirstEvent(forKey: firstPhotoTrackedKey) else { return }

        Analytics.shared.track(.firstPhotoAdded)
        UserDefaults.standard.set(true, forKey: firstPhotoTrackedKey)
    }

    static func metricCount(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<MetricSample>())) ?? 0
    }

    static func photoCount(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<PhotoEntry>())) ?? 0
    }

    private static func shouldTrackFirstEvent(forKey key: String) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: onboardingCompletedKey) else { return false }
        guard defaults.bool(forKey: key) == false else { return false }
        return true
    }
}
