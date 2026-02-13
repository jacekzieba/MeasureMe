import Foundation

enum MetricInputValidator {
    struct ValidationResult {
        let isValid: Bool
        let message: String?

        static let valid = ValidationResult(isValid: true, message: nil)
    }

    static func validateMetricDisplayValue(
        _ value: Double,
        kind: MetricKind,
        unitsSystem: String
    ) -> ValidationResult {
        guard value.isFinite else {
            return ValidationResult(
                isValid: false,
                message: AppLocalization.string("Enter a valid number.")
            )
        }

        let range = metricDisplayRange(for: kind, unitsSystem: unitsSystem)
        guard range.contains(value) else {
            return ValidationResult(
                isValid: false,
                message: AppLocalization.string(
                    "validation.metric.range",
                    range.lowerBound,
                    range.upperBound,
                    kind.unitSymbol(unitsSystem: unitsSystem)
                )
            )
        }

        return .valid
    }

    static func validateOptionalMetricDisplayValue(
        _ value: Double?,
        kind: MetricKind,
        unitsSystem: String
    ) -> ValidationResult {
        guard let value else { return .valid }
        return validateMetricDisplayValue(value, kind: kind, unitsSystem: unitsSystem)
    }

    static func validateAgeValue(_ age: Int?) -> ValidationResult {
        guard let age else {
            return ValidationResult(
                isValid: false,
                message: AppLocalization.string("Age must be between 5 and 120.")
            )
        }
        guard (5...120).contains(age) else {
            return ValidationResult(
                isValid: false,
                message: AppLocalization.string("Age must be between 5 and 120.")
            )
        }
        return .valid
    }

    static func validateHeightMetricValue(_ centimeters: Double) -> ValidationResult {
        guard centimeters.isFinite else {
            return ValidationResult(
                isValid: false,
                message: AppLocalization.string("Enter a valid number.")
            )
        }
        guard (50.0...300.0).contains(centimeters) else {
            return ValidationResult(
                isValid: false,
                message: AppLocalization.string("Height must be between 50 and 300 cm.")
            )
        }
        return .valid
    }

    static func validateHeightImperial(feet: Int?, inches: Int?) -> ValidationResult {
        guard let feet, let inches else {
            return ValidationResult(
                isValid: false,
                message: AppLocalization.string("Height must be between 1 and 8 ft 11 in.")
            )
        }
        guard (0...11).contains(inches) else {
            return ValidationResult(
                isValid: false,
                message: AppLocalization.string("Height must be between 1 and 8 ft 11 in.")
            )
        }
        let totalInches = feet * 12 + inches
        guard totalInches >= 12 && totalInches <= 107 else {
            return ValidationResult(
                isValid: false,
                message: AppLocalization.string("Height must be between 1 and 8 ft 11 in.")
            )
        }
        return .valid
    }

    static func metricDisplayRange(for kind: MetricKind, unitsSystem: String) -> ClosedRange<Double> {
        switch kind.unitCategory {
        case .percent:
            return 0.0...100.0
        case .weight:
            return unitsSystem == "imperial" ? 0.1...660.0 : 0.1...300.0
        case .length:
            return unitsSystem == "imperial" ? 0.1...120.0 : 0.1...300.0
        }
    }
}
