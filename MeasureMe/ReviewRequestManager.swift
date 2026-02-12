import Foundation
import StoreKit
import UIKit

#if canImport(AppStore)
import AppStore
#endif

enum ReviewRequestManager {
    private static let countKey = "review_prompt_metric_count"
    private static let lastPromptKey = "review_prompt_last_date"

    @MainActor
    static func recordMetricEntryAdded(count: Int = 1) {
        guard count > 0 else { return }

        let defaults = UserDefaults.standard
        let newCount = defaults.integer(forKey: countKey) + count
        defaults.set(newCount, forKey: countKey)

        let now = Date()
        let lastPrompt = defaults.object(forKey: lastPromptKey) as? Date
        let twoWeeks: TimeInterval = 14 * 24 * 60 * 60

        let enoughEntries = newCount >= 3
        let enoughTime = lastPrompt == nil || now.timeIntervalSince(lastPrompt ?? now) >= twoWeeks

        guard enoughEntries, enoughTime else { return }

        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            if #available(iOS 18.0, *) {
                AppStore.requestReview(in: scene)
            } else {
                SKStoreReviewController.requestReview(in: scene)
            }
            defaults.set(now, forKey: lastPromptKey)
            defaults.set(0, forKey: countKey)
        }
    }
}
