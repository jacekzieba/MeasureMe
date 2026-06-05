import Foundation
import StoreKit
import UIKit

#if canImport(AppStore)
import AppStore
#endif

enum ReviewRequestManager {
    private static let countKey = "review_prompt_metric_count"
    private static let lifetimeCountKey = "review_prompt_lifetime_metric_count"
    private static let firstEngagementDateKey = "review_prompt_first_engagement_date"
    private static let lastPromptKey = "review_prompt_last_date"
    private static let minimumMetricEntriesBeforePrompt = 3
    private static let minimumDaysBeforeFirstPrompt: TimeInterval = 7 * 24 * 60 * 60
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
        recordEngagementIfNeeded(settings: defaults)

        let newCount = defaults.integer(forKey: countKey) + count
        let newLifetimeCount = defaults.integer(forKey: lifetimeCountKey) + count
        defaults.set(newCount, forKey: countKey)
        defaults.set(newLifetimeCount, forKey: lifetimeCountKey)

        let now = AppClock.now

        let enoughEntries = newCount >= minimumMetricEntriesBeforePrompt
        let matureEnough = isUserMatureEnoughForPrompt(settings: defaults, now: now)
        let enoughTime = hasEnoughTimePassedSinceLastPrompt(settings: defaults, now: now)

        guard enoughEntries, matureEnough, enoughTime else { return }
        presentReview(settings: settings)
    }

    /// Call at high-satisfaction moments (goal achieved, purchase). Bypasses entry count,
    /// but still requires basic user maturity and respects the 2-week cooldown so we don't over-prompt.
    @MainActor
    static func recordHighSatisfactionMoment(settings: AppSettingsStore? = nil) {
        if AuditConfig.current.isEnabled { return }

        let settings = settings ?? .shared
        let now = AppClock.now
        recordEngagementIfNeeded(settings: settings)

        guard isUserMatureEnoughForPrompt(settings: settings, now: now),
              hasEnoughTimePassedSinceLastPrompt(settings: settings, now: now) else { return }
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

    @MainActor
    private static func recordEngagementIfNeeded(settings: AppSettingsStore) {
        if settings.object(forKey: firstEngagementDateKey) as? Date == nil {
            settings.set(AppClock.now, forKey: firstEngagementDateKey)
        }
    }

    @MainActor
    static func isUserMatureEnoughForPrompt(settings: AppSettingsStore, now: Date = AppClock.now) -> Bool {
        guard settings.integer(forKey: lifetimeCountKey) >= minimumMetricEntriesBeforePrompt else { return false }
        guard let firstEngagement = settings.object(forKey: firstEngagementDateKey) as? Date else { return false }
        return now.timeIntervalSince(firstEngagement) >= minimumDaysBeforeFirstPrompt
    }

    @MainActor
    static func hasEnoughTimePassedSinceLastPrompt(settings: AppSettingsStore, now: Date = AppClock.now) -> Bool {
        guard let lastPrompt = settings.object(forKey: lastPromptKey) as? Date else { return true }
        return now.timeIntervalSince(lastPrompt) >= twoWeeks
    }
}
