import Foundation
import StoreKit
import UIKit

#if canImport(AppStore)
import AppStore
#endif

enum ReviewRequestManager {
    private static let countKey = "review_prompt_metric_count"
    private static let lastPromptKey = "review_prompt_last_date"
    private static let twoWeeks: TimeInterval = 14 * 24 * 60 * 60

    @MainActor
    static func recordMetricEntryAdded(
        count: Int = 1,
        settings: AppSettingsStore
    ) {
        if AuditConfig.current.isEnabled {
            return
        }
        guard count > 0 else { return }

        let defaults = settings
        let newCount = defaults.integer(forKey: countKey) + count
        defaults.set(newCount, forKey: countKey)

        let now = AppClock.now
        let lastPrompt = defaults.object(forKey: lastPromptKey) as? Date

        let enoughEntries = newCount >= 3
        let enoughTime = lastPrompt == nil || now.timeIntervalSince(lastPrompt ?? now) >= twoWeeks

        guard enoughEntries, enoughTime else { return }
        presentReview(settings: settings)
    }

    /// Call at high-satisfaction moments (goal achieved, purchase). Bypasses entry count,
    /// but still respects the 2-week cooldown so we don't over-prompt.
    @MainActor
    static func recordHighSatisfactionMoment(settings: AppSettingsStore? = nil) {
        if AuditConfig.current.isEnabled { return }

        let settings = settings ?? .shared
        let now = AppClock.now
        let lastPrompt = settings.object(forKey: lastPromptKey) as? Date
        let enoughTime = lastPrompt == nil || now.timeIntervalSince(lastPrompt ?? now) >= twoWeeks
        guard enoughTime else { return }
        presentReview(settings: settings)
    }

    @MainActor
    static func recordMetricEntryAdded(count: Int = 1) {
        recordMetricEntryAdded(count: count, settings: .shared)
    }

    @MainActor
    private static func presentReview(settings: AppSettingsStore) {
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            if #available(iOS 18.0, *) {
                AppStore.requestReview(in: scene)
            } else {
                SKStoreReviewController.requestReview(in: scene)
            }
            settings.set(AppClock.now, forKey: lastPromptKey)
            settings.set(0, forKey: countKey)
        }
    }
}
