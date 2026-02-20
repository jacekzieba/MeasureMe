import Foundation

enum QuickAddMath {
    /// Wylicza widoczny zakres miarki wycentrowany na `base`, ograniczony do `validRange`.
    /// Zwraca `validRange`, gdy `base` to NaN/Infinity albo granice sa niepoprawne.
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

    /// Calkowity indeks kroku dla haptyki. Zwraca 0 dla danych niefinitywnych.
    static func stepIndex(value: Double, lowerBound: Double, step: Double) -> Int {
        let raw = (value - lowerBound) / step
        return raw.isFinite ? Int(raw) : 0
    }

    /// Czy pokazywac miarke dla danej metryki.
    /// Returns `true` when we have a sensible base value — either from
    /// a previous measurement or because the user just typed one.
    static func shouldShowRuler(hasLatest: Bool, currentInput: Double?) -> Bool {
        hasLatest || currentInput != nil
    }
}
