import Foundation

enum QuickAddMath {
    /// Computes the visible ruler range centred on `base`, clamped to `validRange`.
    /// Returns `validRange` when `base` is NaN/Infinity or when computed bounds are invalid.
    static func rulerRange(
        base: Double,
        span: Double,
        validRange: ClosedRange<Double>
    ) -> ClosedRange<Double> {
        let lo = max(base - span, validRange.lowerBound)
        let hi = min(base + span, validRange.upperBound)
        guard lo <= hi else { return validRange }
        return lo...hi
    }

    /// Number of tick marks for the ruler, clamped to 8...40.
    static func tickCount(span: Double, step: Double) -> Int {
        let raw = span / max(step * 5, 1) + 1
        return max(8, min(40, raw.isFinite ? Int(raw) : 8))
    }

    /// Integer step index for haptic feedback. Returns 0 for non-finite inputs.
    static func stepIndex(value: Double, lowerBound: Double, step: Double) -> Int {
        let raw = (value - lowerBound) / step
        return raw.isFinite ? Int(raw) : 0
    }

    /// Whether to show the ruler for a given metric.
    /// Returns `true` when we have a sensible base value — either from
    /// a previous measurement or because the user just typed one.
    static func shouldShowRuler(hasLatest: Bool, currentInput: Double?) -> Bool {
        hasLatest || currentInput != nil
    }
}
