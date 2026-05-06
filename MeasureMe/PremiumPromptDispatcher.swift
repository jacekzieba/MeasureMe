import Foundation

/// Bridge between non-SwiftUI services (e.g. `QuickAddSaveService`) and the live
/// `PremiumStore`. Configured once at app startup with the active store; the
/// dispatcher then proxies *automatic* paywall triggers through the store's
/// frequency-cap coordinator. User-initiated paywalls (feature taps) bypass it
/// and call `presentPaywall(reason:)` directly.
@MainActor
final class PremiumPromptDispatcher {
    static let shared = PremiumPromptDispatcher()

    private weak var store: PremiumStore?

    private init() {}

    func configure(with store: PremiumStore) {
        self.store = store
    }

    /// Fire-and-forget: the store's `PremiumPromptCoordinator` will silently
    /// drop the prompt if any cap (Premium, session, 7-day gap, dismissal
    /// count) is hit, so callers don't need to gate themselves.
    func maybePresentPostMeasurementPrompt() {
        store?.presentAutomaticPaywall(reason: .postMeasurementPrompt, promptKind: .postMeasurement)
    }

    func maybePresentHomeDiscoveryPrompt() {
        store?.presentAutomaticPaywall(reason: .aiInsights, promptKind: .homeDiscoveryCard)
    }
}
