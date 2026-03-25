import Foundation

/// Pure computation helpers for QuickAdd — ruler ranges, base values, formatting, validation.
/// Extracted from QuickAddSheetView to enable unit testing without SwiftUI.
enum QuickAddMetricLogic {

    // MARK: - Base Value

    /// Returns a sensible starting value for the ruler, based on the latest measurement or a fallback default.
    static func baseValue(
        for kind: MetricKind,
        currentInput: Double?,
        latestMetricValue: Double?,
        unitsSystem: String
    ) -> Double {
        if let current = currentInput {
            return current
        }
        if let last = latestMetricValue {
            return kind.valueForDisplay(fromMetric: last, unitsSystem: unitsSystem)
        }
        return defaultBaseValue(for: kind, unitsSystem: unitsSystem)
    }

    /// Fallback when there is no latest measurement.
    static func defaultBaseValue(for kind: MetricKind, unitsSystem: String) -> Double {
        switch kind.unitCategory {
        case .percent:
            return 20
        case .weight:
            return unitsSystem == "imperial" ? 170 : 75
        case .length:
            return unitsSystem == "imperial" ? 35 : 90
        }
    }

    // MARK: - Ruler Range

    static func rulerRange(
        for kind: MetricKind,
        rulerBaseValue: Double?,
        currentInput: Double?,
        latestMetricValue: Double?,
        unitsSystem: String
    ) -> ClosedRange<Double> {
        let base = rulerBaseValue ?? baseValue(
            for: kind,
            currentInput: currentInput,
            latestMetricValue: latestMetricValue,
            unitsSystem: unitsSystem
        )
        let span: Double
        switch kind.unitCategory {
        case .percent:
            span = 20
        case .weight:
            span = unitsSystem == "imperial" ? 66 : 30
        case .length:
            span = unitsSystem == "imperial" ? 20 : 40
        }
        let validRange = MetricInputValidator.metricDisplayRange(for: kind, unitsSystem: unitsSystem)
        return QuickAddMath.rulerRange(base: base, span: span, validRange: validRange)
    }

    // MARK: - Ruler Step

    static func rulerStep(for kind: MetricKind) -> Double {
        switch kind.unitCategory {
        case .percent:
            return 0.1
        case .weight, .length:
            return 0.1
        }
    }

    // MARK: - Formatting

    static func formatted(_ value: Double, for kind: MetricKind, unitsSystem: String) -> String {
        kind.formattedDisplayValue(value, unitsSystem: unitsSystem)
    }

    // MARK: - Validation

    static func validationMessage(value: Double?, kind: MetricKind, unitsSystem: String) -> String? {
        guard let value else { return nil }
        let result = MetricInputValidator.validateOptionalMetricDisplayValue(
            value,
            kind: kind,
            unitsSystem: unitsSystem
        )
        return result.isValid ? nil : result.message
    }

    // MARK: - Last Summary

    static func lastSummary(
        for kind: MetricKind,
        latestValue: Double,
        latestDate: Date,
        unitsSystem: String
    ) -> String {
        let shown = kind.valueForDisplay(fromMetric: latestValue, unitsSystem: unitsSystem)
        let dateText = latestDate.formatted(date: .abbreviated, time: .omitted)
        return AppLocalization.string(
            "quickadd.last.summary",
            kind.formattedDisplayValue(shown, unitsSystem: unitsSystem),
            dateText
        )
    }
}
