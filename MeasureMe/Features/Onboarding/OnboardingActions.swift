import SwiftUI

extension OnboardingView {
    func safeCardHeight(from containerHeight: CGFloat, reserved: CGFloat, extra: CGFloat = 0) -> CGFloat {
        guard containerHeight.isFinite, containerHeight > 0 else { return 1 }
        let safeReserved = reserved.isFinite ? max(reserved, 0) : 82
        let safeExtra = extra.isFinite ? extra : 0
        let candidate = containerHeight - safeReserved + safeExtra
        let minimumRatio: CGFloat = dynamicTypeSize.isAccessibilitySize ? 0.62 : 0.55
        let minimumCardHeight = min(max(containerHeight * minimumRatio, 180), containerHeight)
        let maxInset: CGFloat = dynamicTypeSize.isAccessibilitySize ? 44 : 10
        let maximumCardHeight = max(containerHeight - maxInset, minimumCardHeight)
        guard candidate.isFinite else {
            return minimumCardHeight
        }
        return min(max(candidate, minimumCardHeight), maximumCardHeight)
    }

}
